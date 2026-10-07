#!/usr/bin/env bash
# Runs the performance tour (godot -- --bench) and saves its table.
#
#   tools/bench.sh [OUT.md] [-- BENCH ARGS...]
#   tools/bench.sh bench-low.md -- --quality=low --mood=rainy
#   tools/bench.sh swim.md -- --bench=swim,split --bench-stream=on
#
# The arguments are the game's (see godot/scripts/main.gd and bench.gd):
# --bench=VIEWS, --quality, --mood, --bench-stream, --bench-size and
# --bench-off=PARTS, which leaves parts out to see what they cost.
#
# With a desktop session it opens a window there. Without one (over SSH, say)
# it starts a headless Sway on the machine's own GPU: Xvfb would only give
# software rendering. Run it from the default dev shell (nix develop).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-bench.md}
shift || true
[[ ${1:-} == -- ]] && shift

run() {
	godot --path "$root/godot" "$@" -- --bench "${bench_args[@]}" 2>&1 | grep --line-buffered -E '^(\||Linguini bench|Averages|Done|\(no stream)' | tee "$out"
}
bench_args=("$@")

if [[ -n ${WAYLAND_DISPLAY:-} || -n ${DISPLAY:-} ]]; then
	run
	exit
fi

# A short runtime dir: Sway's socket path must fit in a sockaddr.
runtime=$(mktemp -d /tmp/lb.XXXX)
trap 'kill "$sway" 2>/dev/null; rm -rf "$runtime"' EXIT
printf 'output HEADLESS-1 resolution 1920x1080\ndefault_border none\n' >"$runtime/sway.conf"
XDG_RUNTIME_DIR=$runtime WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
	sway -c "$runtime/sway.conf" >"$runtime/sway.log" 2>&1 &
sway=$!
for _ in $(seq 50); do
	display=$(ls "$runtime" | grep -E '^wayland-[0-9]+$' | head -1 || true)
	[[ -n $display ]] && break
	sleep 0.1
done
if [[ -z $display ]]; then
	echo "Sway didn't start:" >&2
	cat "$runtime/sway.log" >&2
	exit 1
fi
XDG_RUNTIME_DIR=$runtime WAYLAND_DISPLAY=$display run --display-driver wayland
