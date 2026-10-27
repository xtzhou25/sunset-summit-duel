#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export XDG_DATA_HOME=/tmp/duel-data XDG_CACHE_HOME=/tmp/duel-cache XDG_CONFIG_HOME=/tmp/duel-config
out="$PWD/exports/qa-v5/roundhouse-four-poses"
[ ! -d "$out" ] || exit 2
godot --path . --audio-driver Dummy --script tests/roundhouse_pose_capture.gd -- --frames="$out" > exports/qa-v5/roundhouse-four-poses.log 2>&1
