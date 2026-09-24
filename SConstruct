#!/usr/bin/env python
# Builds the Linguini GDExtension (godot/bin/liblinguini.*).
#
#   scons                      # debug build for the host platform
#   scons target=template_release
#
# System dependencies (FFmpeg, Opus, OpenSSL, libcurl, expat) are found
# with pkg-config on Linux and macOS. On Windows, point LINGUINI_DEPS_PREFIX at a
# prefix containing include/ and lib/ (e.g. a vcpkg installed/x64-windows tree).
# On Linux and macOS, LINGUINI_DEPS_PREFIX links them statically instead, for
# release builds (packaging/linux, packaging/macos).
import os
import subprocess

env = SConscript("third_party/godot-cpp/SConstruct")

platform = env["platform"]
is_msvc = env.get("is_msvc", False)

if platform in ["linux", "macos"]:
    # Per-target object names, so builds for different targets and arches
    # (e.g. both halves of a macOS universal build) can share a tree.
    env["SHOBJSUFFIX"] = env["suffix"] + ".o"

ML_COMMON = "third_party/moonlight-common-c"
GAMESTREAM = "third_party/moonlight-embedded/libgamestream"

PKG_MODULES = ["libavcodec", "libavutil", "opus", "openssl", "libcurl", "expat"]


def pkg_config(env, modules):
    try:
        flags = subprocess.check_output(["pkg-config", "--cflags", "--libs"] + modules).decode()
    except (OSError, subprocess.CalledProcessError) as e:
        print("pkg-config failed for {}: {}".format(" ".join(modules), e))
        Exit(1)
    env.MergeFlags(flags)


static_deps = platform in ["linux", "macos"] and bool(os.environ.get("LINGUINI_DEPS_PREFIX"))
if static_deps:
    # Release builds: static FFmpeg, curl, OpenSSL, Opus and expat from the prefix.
    prefix = os.environ["LINGUINI_DEPS_PREFIX"]
    env.Append(CPPPATH=[os.path.join(prefix, "include"), os.path.join(prefix, "include", "opus")])
    env.Append(LIBPATH=[os.path.join(prefix, "lib")])
    env.Append(LIBS=["avcodec", "avutil", "curl", "ssl", "crypto", "expat", "opus"])
    if platform == "linux":
        # Only glibc and libva stay dynamic. Keep the static libraries' symbols
        # private, and fail at link time rather than load time if anything is missing.
        env.Append(LIBS=["va", "va-drm", "pthread", "dl", "m"])
        env.Append(LINKFLAGS=["-Wl,--exclude-libs,ALL", "-Wl,--no-undefined"])
    else:
        # Frameworks the static libraries use: curl's macOS proxy/resolver
        # support. VideoToolbox's are added below for every macOS build.
        env.Append(LINKFLAGS=["-framework", "CoreFoundation", "-framework", "CoreServices",
                              "-framework", "SystemConfiguration"])
elif platform in ["linux", "macos"]:
    pkg_config(env, PKG_MODULES)
elif platform == "windows":
    # Static libraries from packaging/windows/build-deps.ps1 (vcpkg,
    # x64-windows-static-release), so the extension links only system DLLs.
    prefix = os.environ.get("LINGUINI_DEPS_PREFIX")
    if not prefix:
        print("Set LINGUINI_DEPS_PREFIX to the prefix packaging/windows/build-deps.ps1 prints.")
        Exit(1)
    if not is_msvc:
        print("The Windows build needs MSVC (the dependencies are built with it).")
        Exit(1)
    env.Append(CPPPATH=[os.path.join(prefix, "include"), os.path.join(prefix, "include", "opus")])
    env.Append(LIBPATH=[os.path.join(prefix, "lib")])
    env.Append(CPPDEFINES=["CURL_STATICLIB", "XML_STATIC"])
    env.Append(LIBS=["avcodec", "avutil", "libcurl", "libssl", "libcrypto", "libexpatMT", "opus", "zs"])
    env.Append(LIBS=["ws2_32", "winmm", "crypt32", "bcrypt", "advapi32", "user32", "iphlpapi",
                     "ole32", "mfuuid", "strmiids"])
else:
    print("Unsupported platform: " + platform)
    Exit(1)

# --- moonlight-common-c + libgamestream (plain C, built into the same library) ---
cenv = env.Clone()
cenv.Append(
    CPPPATH=[
        ML_COMMON + "/src",
        ML_COMMON + "/enet/include",
        ML_COMMON + "/nanors",
        ML_COMMON + "/nanors/deps",
        ML_COMMON + "/nanors/deps/obl",
    ],
    CPPDEFINES=["NDEBUG", "HAS_SOCKLEN_T"],
)
if platform == "windows":
    cenv.Append(CPPDEFINES=["HAS_QOS_FLOWID", "HAS_PQOS_FLOWID"])
else:
    cenv.Append(
        CPPDEFINES=[
            "HAS_FCNTL",
            "HAS_IOCTL",
            "HAS_POLL",
            "HAS_GETADDRINFO",
            "HAS_GETNAMEINFO",
            "HAS_INET_PTON",
            "HAS_INET_NTOP",
            "HAS_MSGHDR_FLAGS",
        ]
    )
if is_msvc:
    cenv.Append(CFLAGS=["/std:c11"])
else:
    cenv.Append(CFLAGS=["-std=gnu11", "-w"])

enet_src = ["callbacks.c", "compress.c", "host.c", "list.c", "packet.c", "peer.c", "protocol.c"]
enet_src.append("win32.c" if platform == "windows" else "unix.c")
c_sources = [ML_COMMON + "/enet/" + f for f in enet_src]
c_sources += Glob(ML_COMMON + "/src/*.c")
c_sources += [
    ML_COMMON + "/nanors/rs.c",
    ML_COMMON + "/nanors/deps/obl/oblas_common.c",
    ML_COMMON + "/nanors/deps/obl/oblas_lite.c",
]

# libgamestream: pairing, server info, app list, launch. discover.c (Avahi) and
# sps.c (h264bitstream) are not needed.
genv = cenv.Clone()
# native/compat also provides <uuid/uuid.h>, so libuuid isn't needed.
genv.Prepend(CPPPATH=["native/compat"])
if platform == "windows":
    genv.Prepend(CPPPATH=["native/compat/win32"])
if is_msvc:
    genv.Append(CCFLAGS=["/FIlibgamestream_compat.h"])
else:
    genv.Append(CCFLAGS=["-include", "libgamestream_compat.h"])
g_sources = [GAMESTREAM + "/" + f for f in ["client.c", "http.c", "mkcert.c", "xml.c"]]

# Keep object files out of the submodules.
def obj(e, src):
    path = str(src)
    return e.SharedObject(target="build/{}/{}".format(env["suffix"].lstrip("."), os.path.splitext(path)[0]), source=path)


objects = [obj(cenv, s) for s in c_sources]
g_objects = [obj(genv, s) for s in g_sources]
# SCons doesn't scan force-included headers.
genv.Depends(g_objects, "native/compat/libgamestream_compat.h")
objects += g_objects

# --- the extension itself ---
env.Append(CPPPATH=["native/src", ML_COMMON + "/src", GAMESTREAM])
sources = Glob("native/src/*.cpp")

if platform == "macos":
    env.Append(LINKFLAGS=["-framework", "VideoToolbox", "-framework", "CoreMedia", "-framework", "CoreVideo"])
    library = env.SharedLibrary(
        "godot/bin/liblinguini.{0}.{1}.framework/liblinguini.{0}.{1}".format(platform, env["target"]),
        source=sources + objects,
    )
else:
    library = env.SharedLibrary(
        "godot/bin/liblinguini{}{}".format(env["suffix"], env["SHLIBSUFFIX"]),
        source=sources + objects,
    )

Default(library)
