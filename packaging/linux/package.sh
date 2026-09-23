#!/usr/bin/env bash
# Portable Linux release: dist/builds/linguini-linux-x86_64.tar.gz
#
#   packaging/linux/package.sh
#
# 1. Builds the extension in Docker (packaging/linux/Dockerfile) against static
#    FFmpeg, curl, OpenSSL, Opus and expat, so it needs only glibc 2.35+
#    and libva from the user's system.
# 2. Exports the Godot project with the "Linux" preset.
# 3. Packs the executable, the extension and third-party licences.
#
# Needs: docker, and a Godot editor with matching export templates.
#   GODOT            Godot editor binary (default: godot)
#   GODOT_TEMPLATES  directory containing linux_release.x86_64 (default: taken
#                    from the Nix flake's godot_4-export-templates-bin if nix is
#                    available, else Godot's own export_templates directory)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST="$ROOT/dist"
WORK="$DIST/linux"
IMAGE=linguini-linux-build
LIB=liblinguini.linux.template_release.x86_64.so
PACKAGE=linguini-linux-x86_64
GODOT="${GODOT:-godot}"

step() { printf '\n==> %s\n' "$*"; }

step "Building the build image"
docker build -q -t "$IMAGE" "$ROOT/packaging/linux" >/dev/null

step "Building the extension (static dependencies)"
mkdir -p "$WORK/src"
# Stream the tracked sources (with submodules) into a separate tree so the
# container's objects don't collide with local builds. SCons compares content,
# so unchanged files aren't rebuilt.
(cd "$ROOT" && git ls-files -z --recurse-submodules) |
    tar -C "$ROOT" --null -T - -cf - |
    tar -C "$WORK/src" -xf -
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$WORK/src:/work" "$IMAGE" \
    bash -c 'LINGUINI_DEPS_PREFIX=/deps scons -j"$(nproc)" platform=linux target=template_release use_static_cpp=yes -Q >/dev/null'

step "Checking the extension's runtime dependencies"
needed=$(docker run --rm -v "$WORK/src:/work" "$IMAGE" readelf -d "godot/bin/$LIB" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')
echo "$needed" | sed 's/^/    /'
unexpected=$(echo "$needed" | grep -vE '^(libc|libm|libdl|libpthread|librt|ld-linux-x86-64)\.so|^libva(-drm)?\.so' || true)
if [[ -n "$unexpected" ]]; then
    echo "Unexpected dynamic dependencies: $unexpected" >&2
    exit 1
fi
glibc=$(docker run --rm -v "$WORK/src:/work" "$IMAGE" bash -c "objdump -T godot/bin/$LIB | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1")
echo "    requires $glibc"
cp "$WORK/src/godot/bin/$LIB" "$ROOT/godot/bin/$LIB"

step "Exporting the Godot project"
godot_version=$("$GODOT" --version | grep -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?\.[a-z]+[0-9]*')
if [[ -z "${GODOT_TEMPLATES:-}" ]]; then
    if command -v nix >/dev/null; then
        GODOT_TEMPLATES=$(nix build --no-link --print-out-paths --inputs-from "$ROOT" nixpkgs#godot_4-export-templates-bin)
        GODOT_TEMPLATES=$(dirname "$(find -L "$GODOT_TEMPLATES" -name linux_release.x86_64 | head -1)")
    else
        GODOT_TEMPLATES="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$godot_version"
    fi
fi
if [[ ! -f "$GODOT_TEMPLATES/linux_release.x86_64" ]]; then
    echo "No linux_release.x86_64 template in $GODOT_TEMPLATES (Godot $godot_version)" >&2
    exit 1
fi
template_version=$(cat "$GODOT_TEMPLATES/version.txt" 2>/dev/null || echo "$godot_version")
if [[ "$template_version" != "$godot_version" ]]; then
    echo "Export templates are $template_version but Godot is $godot_version" >&2
    exit 1
fi
# Point Godot at the templates through a private data directory, leaving the
# user's own Godot configuration alone.
export XDG_DATA_HOME="$WORK/godot-data"
mkdir -p "$XDG_DATA_HOME/godot/export_templates"
ln -sfn "$GODOT_TEMPLATES" "$XDG_DATA_HOME/godot/export_templates/$godot_version"
rm -rf "$WORK/export" && mkdir -p "$WORK/export"
"$GODOT" --headless --path "$ROOT/godot" --import >/dev/null 2>&1
"$GODOT" --headless --path "$ROOT/godot" --export-release "Linux" "$WORK/export/Linguini.x86_64" 2>&1 |
    grep -E "ERROR|WARNING" || true
if [[ ! -x "$WORK/export/Linguini.x86_64" || ! -f "$WORK/export/$LIB" ]]; then
    echo "Export failed: expected Linguini.x86_64 and $LIB in $WORK/export" >&2
    ls -la "$WORK/export" >&2
    exit 1
fi

step "Packing"
stage="$WORK/stage/$PACKAGE"
rm -rf "$WORK/stage" && mkdir -p "$stage/licenses"
cp "$WORK/export/Linguini.x86_64" "$WORK/export/$LIB" "$stage/"
cp "$ROOT/packaging/linux/README.txt" "$stage/README.txt"
cp "$ROOT/third_party/moonlight-common-c/LICENSE.txt" "$stage/licenses/moonlight-common-c.txt"
cp "$ROOT/third_party/moonlight-embedded/LICENSE" "$stage/licenses/moonlight-embedded.txt"
cp "$ROOT/third_party/moonlight-common-c/enet/LICENSE" "$stage/licenses/enet.txt"
cp "$ROOT/third_party/moonlight-common-c/nanors/LICENSE" "$stage/licenses/nanors.txt"
cp "$ROOT/third_party/godot-cpp/LICENSE.md" "$stage/licenses/godot-cpp.md"
"$GODOT" --headless --path "$ROOT/godot" -- --tool=write_licenses "$stage/licenses/godot.txt" >/dev/null
docker run --rm -v "$stage/licenses:/out" -u "$(id -u):$(id -g)" "$IMAGE" cp -r /deps/licenses/. /out/
mkdir -p "$DIST/builds"
tar -C "$WORK/stage" --owner=0 --group=0 -czf "$DIST/builds/$PACKAGE.tar.gz" "$PACKAGE"

echo
echo "Built $DIST/builds/$PACKAGE.tar.gz ($(du -h "$DIST/builds/$PACKAGE.tar.gz" | cut -f1))"
