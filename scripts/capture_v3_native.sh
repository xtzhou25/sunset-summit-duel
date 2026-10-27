#!/bin/sh
# Launch from the cloud desktop terminal for a real native-renderer capture.
# Native capture is not browser/iPhone or performance certification.
set -eu
cd "$(dirname "$0")/.."
export XDG_DATA_HOME=/tmp/duel-data XDG_CACHE_HOME=/tmp/duel-cache XDG_CONFIG_HOME=/tmp/duel-config
name=${1:-candidate-purple}
seconds=${2:-8}
character=${3:-purple}
case "$name" in *[!a-zA-Z0-9_-]*) echo 'Invalid capture name' >&2; exit 2;; esac
output="$PWD/exports/qa-v3/$name"
if [ -d "$output" ]; then echo 'Capture exists; use a new name' >&2; exit 2; fi
if [ "$character" = yellow ]; then extra=--yellow; else extra=; fi
godot --path . --audio-driver Dummy -s tests/gameplay_v3_capture.gd -- --seconds="$seconds" --frames="$output" $extra > "$PWD/exports/qa-v3/$name.log" 2>&1
