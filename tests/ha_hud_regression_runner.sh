#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
export HOME=/tmp/ha-final-home XDG_CACHE_HOME=/tmp/ha-final-cache XDG_CONFIG_HOME=/tmp/ha-final-config XDG_DATA_HOME=/tmp/ha-final-data
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" exports/qa-v14/regression
for name in combat edge punch_variation knockdown spacing projectile roundhouse feedback_events combat_audio feedback_preferences directional_hud impact_feedback stress match integration camera feedback punch_feedback roundhouse_feedback presentation_v3 signature_bounds signature_scene signature_hud spacing_bounds spacing_scene projectile_view p3_intent ai_variation ai_projectile_height joystick_native joystick_gameplay qi_runtime_contract qi_scene qi_choice_input qi_bounds qi_pair_stress tao_runtime_contract ha_runtime; do
 timeout 120 godot --headless --path . --script "tests/${name}_test.gd" > "exports/qa-v14/regression/${name}.log" 2>&1
 result=$?
 printf '%s\t%s\t%s\n' "$name" "$result" "$(grep -E 'RESULT|passed|checks=|CHECKS|PASS ALL|PASS:|FAIL' "exports/qa-v14/regression/${name}.log" | tail -1)" | tee -a exports/qa-v14/regression/status.tsv
done
timeout 120 godot --headless --path . --script tests/ha_hud_qa.gd > exports/qa-v14/regression/ha_hud.log 2>&1
printf 'ha_hud\t%s\t%s\n' "$?" "$(tail -1 exports/qa-v14/regression/ha_hud.log)" | tee -a exports/qa-v14/regression/status.tsv
