#!/usr/bin/env bash
# Runs the packaged Linux build in clean containers of several distributions.
#
#   packaging/linux/test-distros.sh [HOST]
#
# For each distribution: install libva, unpack the tarball, check that the
# extension loads. With HOST (a paired Sunshine/GFE address reachable from this
# machine), also stream the "Desktop" app for 10 s with the stream_check tool,
# reusing this machine's pairing keys.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARBALL="$ROOT/dist/builds/linguini-linux-x86_64.tar.gz"
HOST="${1:-}"
KEYS="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Linguini"

declare -A INSTALL=(
    [ubuntu:22.04]="apt-get update -qq && apt-get install -y -qq libva2 libva-drm2"
    [ubuntu:24.04]="apt-get update -qq && apt-get install -y -qq libva2 libva-drm2"
    [debian:12]="apt-get update -qq && apt-get install -y -qq libva2 libva-drm2"
    [fedora:41]="dnf install -y -q libva"
    [archlinux:latest]="pacman -Sy --noconfirm --quiet libva"
)

[[ -f "$TARBALL" ]] || { echo "No $TARBALL; run packaging/linux/package.sh first" >&2; exit 1; }

failed=0
for image in ubuntu:22.04 ubuntu:24.04 debian:12 fedora:41 archlinux:latest; do
    printf '%-18s ' "$image"
    docker pull -q "$image" >/dev/null
    run="{ ${INSTALL[$image]}; } >/dev/null 2>&1 && tar -xzf /pkg.tar.gz -C /opt && cd /opt/linguini-linux-x86_64"
    run+=" && timeout 60 ./Linguini.x86_64 --headless -- --tool=check_extension 2>&1 | grep -E 'extension'"
    if [[ -n "$HOST" ]]; then
        run+=" && timeout 120 ./Linguini.x86_64 --headless -- --tool=stream_check $HOST Desktop 10 2>&1 | grep -E '^  (video|audio|input):|FAILED'"
    fi
    args=(--rm -v "$TARBALL:/pkg.tar.gz:ro")
    if [[ -n "$HOST" ]]; then
        args+=(--network host -v "$KEYS/moonlight:/root/.local/share/godot/app_userdata/Linguini/moonlight")
    fi
    if out=$(docker run "${args[@]}" "$image" bash -c "$run" 2>&1); then
        echo "$out" | sed '2,$s/^/                   /'
    else
        failed=1
        echo "FAILED"
        echo "$out" | tail -15 | sed 's/^/    /'
    fi
done
exit $failed
