#!/usr/bin/env bash
# Builds models from art/catalog.json with Blender: .glb into godot/, renders
# into art/renders/ (for the progress tracker), hashes into art/manifest.json.
#
#   nix develop .#art -c art/build.sh              # every model not "planned"
#   nix develop .#art -c art/build.sh fish tank    # just these
#   ART_NO_RENDER=1 art/build.sh fish              # skip the (slower) renders
set -euo pipefail

ART="$(cd "$(dirname "$0")" && pwd)"
BLENDER="${BLENDER:-blender}"

if [[ $# -gt 0 ]]; then
    ids=("$@")
else
    mapfile -t ids < <(python3 -c '
import json, sys
for m in json.load(open(sys.argv[1]))["models"]:
    if m.get("status") != "planned":
        print(m["id"])' "$ART/catalog.json")
fi

extra=()
[[ -n "${ART_NO_RENDER:-}" ]] && extra+=(--no-render)

for id in "${ids[@]}"; do
    echo "==> $id"
    log=$(mktemp)
    if ! "$BLENDER" -b --factory-startup -P "$ART/run.py" -- "$id" "${extra[@]}" >"$log" 2>&1; then
        cat "$log"
        rm -f "$log"
        exit 1
    fi
    # Blender exits 0 even when the script raises; check for a traceback.
    if grep -q "^Traceback" "$log"; then
        cat "$log"
        rm -f "$log"
        exit 1
    fi
    grep -E "^(exported|rendered)" "$log" | sed 's/^/    /'
    rm -f "$log"
done
