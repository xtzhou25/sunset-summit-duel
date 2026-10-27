#!/bin/sh
# Controlled native fixtures, not live AI. Each has one hit and one blocked wave.
set -eu
cd "$(dirname "$0")/.."
export XDG_DATA_HOME=/tmp/duel6-data XDG_CACHE_HOME=/tmp/duel6-cache XDG_CONFIG_HOME=/tmp/duel6-config
for kind in purple yellow; do
  for facing in right left; do
    name="signature-${1:-final}-${kind}-${facing}"
    out="$PWD/exports/qa-v6/$name"
    test ! -e "$out" || { echo "Existing capture: $out"; exit 2; }
    extra=""
    [ "$kind" != yellow ] || extra="$extra --yellow"
    [ "$facing" != left ] || extra="$extra --left"
    godot --path . --audio-driver Dummy --script tests/signature_pose_capture.gd -- --frames="$out" $extra > "exports/qa-v6/$name.log" 2>&1
  done
done
