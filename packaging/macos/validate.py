#!/usr/bin/env python3
"""Checks the macOS release zip. It runs anywhere; package.sh runs it last.

    python3 packaging/macos/validate.py dist/builds/linguini-macos-universal.zip

Verifies the zip, the app bundle's Info.plist (bundle id, minimum macOS, local
network usage string), that the executable and the extension are Universal 2
(arm64 + x86_64) Mach-O with a code signature in every slice, that the
extension links only system libraries (/usr/lib and system frameworks), that
the game data is packed, and that the README and licences are present. It
doesn't launch the app.
"""
import plistlib
import stat
import struct
import sys
import zipfile

BUNDLE_ID = "org.linguini.client"
EXTENSION = "liblinguini.macos.template_release"
MIN_MACOS = "11.0"

FAT_MAGIC = 0xCAFEBABE
MH_MAGIC_64 = 0xFEEDFACF
CPU = {0x01000007: "x86_64", 0x0100000C: "arm64"}
LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_CODE_SIGNATURE = 0x1D
LC_BUILD_VERSION = 0x32
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0


def macho_slices(data: bytes) -> dict:
    """Returns {arch: {"dylibs": [...], "signed": bool, "minos": "x.y"}} for a fat Mach-O."""
    magic, count = struct.unpack_from(">II", data)
    if magic != FAT_MAGIC:
        raise AssertionError("not a universal (fat) Mach-O")
    slices = {}
    for i in range(count):
        cpu, _, offset, size, _ = struct.unpack_from(">IIIII", data, 8 + i * 20)
        arch = CPU.get(cpu, hex(cpu))
        assert offset + size <= len(data), f"{arch} slice runs past the end of the file"
        assert struct.unpack_from("<I", data, offset)[0] == MH_MAGIC_64, f"{arch} slice isn't 64-bit Mach-O"
        ncmds = struct.unpack_from("<I", data, offset + 16)[0]
        cursor = offset + 32
        info = {"dylibs": [], "signed": False, "minos": None}
        for _ in range(ncmds):
            cmd, length = struct.unpack_from("<II", data, cursor)
            assert length >= 8
            if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB):
                name_offset = struct.unpack_from("<I", data, cursor + 8)[0]
                raw = data[cursor + name_offset:cursor + length]
                info["dylibs"].append(raw.split(b"\0", 1)[0].decode())
            elif cmd == LC_CODE_SIGNATURE:
                sig_offset, sig_size = struct.unpack_from("<II", data, cursor + 8)
                assert sig_size > 0 and sig_offset + sig_size <= size
                assert struct.unpack_from(">I", data, offset + sig_offset)[0] == CSMAGIC_EMBEDDED_SIGNATURE
                info["signed"] = True
            elif cmd == LC_BUILD_VERSION:
                minos = struct.unpack_from("<I", data, cursor + 12)[0]
                info["minos"] = f"{minos >> 16}.{(minos >> 8) & 0xFF}"
            cursor += length
        slices[arch] = info
    return slices


def main(path: str) -> int:
    problems = []

    def check(ok, message):
        if not ok:
            problems.append(message)

    with zipfile.ZipFile(path) as z:
        check(z.testzip() is None, "zip integrity check failed")
        names = z.namelist()
        plists = [n for n in names if n.endswith(".app/Contents/Info.plist")]
        if len(plists) != 1:
            print(f"FAIL: expected one app bundle, found {len(plists)}")
            return 1
        app = plists[0].removesuffix("Contents/Info.plist")
        top = app.split("/", 1)[0] + "/" if "/" in app.rstrip("/") else ""

        info = plistlib.loads(z.read(plists[0]))
        check(info.get("CFBundleIdentifier") == BUNDLE_ID, f"bundle id is {info.get('CFBundleIdentifier')}")
        # Godot writes the minimum per architecture.
        minimum = info.get("LSMinimumSystemVersionByArchitecture") or {}
        check(minimum == {"arm64": MIN_MACOS, "x86_64": MIN_MACOS}, f"minimum macOS is {minimum}")
        check("NSLocalNetworkUsageDescription" in info, "Info.plist has no NSLocalNetworkUsageDescription")

        executable = app + "Contents/MacOS/" + info["CFBundleExecutable"]
        check((z.getinfo(executable).external_attr >> 16) & stat.S_IXUSR, "executable bit missing")
        exe = macho_slices(z.read(executable))
        check(set(exe) == {"arm64", "x86_64"}, f"executable slices: {sorted(exe)}")
        check(all(s["signed"] for s in exe.values()), "executable slice without a code signature")
        check(app + "Contents/_CodeSignature/CodeResources" in names, "app bundle isn't signed (no CodeResources)")

        framework = app + f"Contents/Frameworks/{EXTENSION}.framework/"
        ext_binary = framework + EXTENSION
        check(ext_binary in names, f"extension missing: {ext_binary}")
        if ext_binary in names:
            ext = macho_slices(z.read(ext_binary))
            check(set(ext) == {"arm64", "x86_64"}, f"extension slices: {sorted(ext)}")
            for arch, s in ext.items():
                check(s["signed"], f"extension {arch} slice isn't signed")
                foreign = [d for d in s["dylibs"] if not d.startswith(("/usr/lib/", "/System/Library/Frameworks/"))]
                check(not foreign, f"extension {arch} links non-system libraries: {foreign}")
                check(s["minos"] == MIN_MACOS, f"extension {arch} targets macOS {s['minos']}")
            check(framework + "Resources/Info.plist" in names, "extension framework has no Info.plist")

        packs = [n for n in names if n.startswith(app + "Contents/Resources/") and n.endswith(".pck")]
        check(len(packs) == 1, f"expected one .pck, found {packs}")
        if packs:
            pck = z.read(packs[0])
            for needed in (b"data/layouts/default.json", b"linguini.gdextension", b"scripts/main.gd"):
                check(needed in pck, f"{needed.decode()} not in the packed game data")
            check(b"tests/test_fish" not in pck, "tests were exported")

        for extra in ("README.txt", "LICENSE.txt", "licenses/ffmpeg/LICENSE.md", "licenses/godot.txt"):
            check(top + extra in names, f"{extra} missing from the zip")

    if problems:
        for p in problems:
            print("FAIL: " + p)
        return 1
    print(f"OK: {app.rstrip('/')} ({BUNDLE_ID}), Universal 2, signed, macOS {MIN_MACOS}+;"
          f" extension links only system libraries")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
