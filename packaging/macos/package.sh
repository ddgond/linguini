#!/usr/bin/env bash
# macOS release: dist/builds/linguini-macos-universal.zip
#
#   packaging/macos/package.sh
#
# 1. Builds static FFmpeg, curl, OpenSSL, Opus and expat for arm64 and x86_64
#    (packaging/macos/build-deps.sh; reused until that script changes).
# 2. Builds the extension for each architecture against them and joins the two
#    with lipo into a universal framework that links only system libraries.
# 3. Exports the Godot project with the "macOS" preset (universal, ad-hoc signed).
# 4. Packs Linguini.app, a README and the third-party licences, then checks the
#    zip with packaging/macos/validate.py.
#
# Needs: Xcode command line tools, scons, nasm, and a Godot editor with the
# matching macOS export template.
#   GODOT            Godot editor binary (default: godot)
#   GODOT_TEMPLATES  directory containing macos.zip (default: Godot's own
#                    export_templates directory for this version)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST="$ROOT/dist"
WORK="$DIST/macos"
NAME=liblinguini.macos.template_release
FRAMEWORK="$NAME.framework"
PACKAGE=linguini-macos-universal
MIN_MACOS=11.0
ARCHS=(arm64 x86_64)
GODOT="${GODOT:-godot}"
JOBS=$(sysctl -n hw.ncpu)

step() { printf '\n==> %s\n' "$*"; }

for arch in "${ARCHS[@]}"; do
    step "Static dependencies ($arch)"
    "$ROOT/packaging/macos/build-deps.sh" "$arch" "$WORK/deps-$arch"
done

step "Building the extension"
mkdir -p "$WORK/src"
# Build and export from a copy of the tracked sources (with submodules), as the
# Linux script does, so release objects and export settings stay out of the
# working tree. SCons compares content, so unchanged files aren't rebuilt.
(cd "$ROOT" && git ls-files -z --recurse-submodules) |
    tar -C "$ROOT" --null -T - -cf - |
    tar -C "$WORK/src" -xf -
slices=()
for arch in "${ARCHS[@]}"; do
    echo "    $arch"
    (cd "$WORK/src" && LINGUINI_DEPS_PREFIX="$WORK/deps-$arch" scons -j"$JOBS" -Q platform=macos arch="$arch" \
        target=template_release macos_deployment_target="$MIN_MACOS" >/dev/null)
    # Both architectures link to the same path, so keep each one as it's built.
    cp "$WORK/src/godot/bin/$FRAMEWORK/$NAME" "$WORK/$NAME.$arch"
    slices+=("$WORK/$NAME.$arch")
done
framework="$WORK/src/godot/bin/$FRAMEWORK"
rm -rf "$framework" && mkdir -p "$framework/Resources"
lipo -create "${slices[@]}" -output "$framework/$NAME"
cp "$ROOT/packaging/macos/Info.plist" "$framework/Resources/Info.plist"
codesign --force --sign - "$framework"

step "Checking the extension's runtime dependencies"
lipo -archs "$framework/$NAME" | sed 's/^/    architectures: /'
for arch in "${ARCHS[@]}"; do
    linked=$(otool -arch "$arch" -L "$framework/$NAME" | tail -n +3 | awk '{print $1}')
    echo "    $arch links:" $linked
    unexpected=$(echo "$linked" | grep -vE '^(/usr/lib/|/System/Library/Frameworks/)' || true)
    if [[ -n "$unexpected" ]]; then
        echo "Unexpected dynamic dependencies ($arch): $unexpected" >&2
        exit 1
    fi
    minos=$(otool -arch "$arch" -l "$framework/$NAME" | awk '/LC_BUILD_VERSION/ {found=1} found && $1 == "minos" {print $2; exit}')
    echo "    $arch requires macOS $minos"
    if [[ "$minos" != "$MIN_MACOS" ]]; then
        echo "The $arch extension targets macOS $minos, not $MIN_MACOS" >&2
        exit 1
    fi
done
rm -rf "$ROOT/godot/bin/$FRAMEWORK" && cp -R "$framework" "$ROOT/godot/bin/"

step "Building the extension for the editor"
# The editor that runs the export loads the debug build for this Mac.
(cd "$WORK/src" && LINGUINI_DEPS_PREFIX="$WORK/deps-$(uname -m)" scons -j"$JOBS" -Q platform=macos \
    arch="$(uname -m)" target=template_debug >/dev/null)

step "Exporting the Godot project"
godot_version=$("$GODOT" --version | grep -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?\.[a-z]+[0-9]*')
GODOT_TEMPLATES="${GODOT_TEMPLATES:-$HOME/Library/Application Support/Godot/export_templates/$godot_version}"
if [[ ! -f "$GODOT_TEMPLATES/macos.zip" ]]; then
    echo "No macos.zip template in $GODOT_TEMPLATES (Godot $godot_version)" >&2
    exit 1
fi
template_version=$(cat "$GODOT_TEMPLATES/version.txt" 2>/dev/null || echo "$godot_version")
if [[ "$template_version" != "$godot_version" ]]; then
    echo "Export templates are $template_version but Godot is $godot_version" >&2
    exit 1
fi
# Godot on macOS has no XDG_DATA_HOME to redirect, so point the copied preset
# straight at the template instead.
presets="$WORK/src/godot/export_presets.cfg"
template="$(cd "$GODOT_TEMPLATES" && pwd)/macos.zip"
awk -v t="$template" '
    /^\[preset\.[0-9]+\]$/ { mac = 0 }
    /^name="macOS"$/ { mac = 1 }
    mac && /^custom_template\/release=/ { $0 = "custom_template/release=\"" t "\"" }
    { print }
' "$presets" > "$presets.tmp" && mv "$presets.tmp" "$presets"
grep -qF "custom_template/release=\"$template\"" "$presets" ||
    { echo "Couldn't set the macOS preset's custom template in $presets" >&2; exit 1; }
rm -rf "$WORK/export" && mkdir -p "$WORK/export"
# Register the extension up front: found mid-scan on a fresh tree, it makes
# the import crash on exit.
mkdir -p "$WORK/src/godot/.godot" && echo "res://linguini.gdextension" > "$WORK/src/godot/.godot/extension_list.cfg"
"$GODOT" --headless --path "$WORK/src/godot" --import >/dev/null 2>&1
"$GODOT" --headless --path "$WORK/src/godot" --export-release "macOS" "$WORK/export/Linguini.app" 2>&1 |
    grep -E "ERROR|WARNING" || true
app="$WORK/export/Linguini.app"
if [[ ! -x "$app/Contents/MacOS/Linguini" || ! -f "$app/Contents/Frameworks/$FRAMEWORK/$NAME" ]]; then
    echo "Export failed: expected Linguini.app with $FRAMEWORK in $WORK/export" >&2
    ls -laR "$WORK/export" >&2
    exit 1
fi
codesign --verify --deep --strict "$app"

step "Packing"
stage="$WORK/stage/$PACKAGE"
rm -rf "$WORK/stage" && mkdir -p "$stage/licenses"
ditto "$app" "$stage/Linguini.app"
cp "$ROOT/packaging/macos/README.txt" "$stage/README.txt"
cp "$ROOT/LICENSE" "$stage/LICENSE.txt"
cp "$ROOT/third_party/moonlight-common-c/LICENSE.txt" "$stage/licenses/moonlight-common-c.txt"
cp "$ROOT/third_party/moonlight-embedded/LICENSE" "$stage/licenses/moonlight-embedded.txt"
cp "$ROOT/third_party/moonlight-common-c/enet/LICENSE" "$stage/licenses/enet.txt"
cp "$ROOT/third_party/moonlight-common-c/nanors/LICENSE" "$stage/licenses/nanors.txt"
cp "$ROOT/third_party/godot-cpp/LICENSE.md" "$stage/licenses/godot-cpp.md"
"$GODOT" --headless --path "$WORK/src/godot" -- --tool=write_licenses "$stage/licenses/godot.txt" >/dev/null
cp -R "$WORK/deps-${ARCHS[0]}/licenses/." "$stage/licenses/"
mkdir -p "$DIST/builds"
rm -f "$DIST/builds/$PACKAGE.zip"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$stage" "$DIST/builds/$PACKAGE.zip"

step "Validating"
python3 "$ROOT/packaging/macos/validate.py" "$DIST/builds/$PACKAGE.zip"

echo
echo "Built $DIST/builds/$PACKAGE.zip ($(du -h "$DIST/builds/$PACKAGE.zip" | awk '{print $1}'))"
