#!/bin/sh
set -eu
BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export XDG_DATA_HOME=/tmp/duel7-data XDG_CACHE_HOME=/tmp/duel7-cache XDG_CONFIG_HOME=/tmp/duel7-config
godot --path "$BASE" --audio-driver Dummy --script tests/spacing_capture.gd -- --frames="$BASE/exports/qa-v7/native-final" > "$BASE/exports/qa-v7/native-final.log" 2>&1
godot --path "$BASE" --audio-driver Dummy --script tests/crouch_pose_capture.gd -- --frames="$BASE/exports/qa-v7/crouch-final" > "$BASE/exports/qa-v7/crouch-final.log" 2>&1
