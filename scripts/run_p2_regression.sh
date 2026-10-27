#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
export XDG_DATA_HOME=/tmp/duel8-final-data XDG_CACHE_HOME=/tmp/duel8-final-cache XDG_CONFIG_HOME=/tmp/duel8-final-config
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" exports/qa-p2/final
status=0
for name in combat edge punch_variation knockdown spacing projectile roundhouse feedback_events combat_audio feedback_preferences directional_hud impact_feedback stress match integration; do
 godot --headless --path . --script "tests/${name}_test.gd" > "exports/qa-p2/final/${name}-final.log" 2>&1 || status=1
 echo "$name $(grep -E 'RESULT|passed|checks=|CHECKS|PASS ALL|PASS:' "exports/qa-p2/final/${name}-final.log" | tail -1)"
done
exit "$status"
