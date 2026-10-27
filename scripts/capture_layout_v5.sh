#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export XDG_DATA_HOME=/tmp/duel-data XDG_CACHE_HOME=/tmp/duel-cache XDG_CONFIG_HOME=/tmp/duel-config
godot --path . --audio-driver Dummy -s tests/layout_v5_capture.gd > exports/qa-v5/layout-native.log 2>&1
