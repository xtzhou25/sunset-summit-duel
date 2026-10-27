extends SceneTree
## v3 deterministic down/recovery, presentation mapping, and actual skinned-pose
## camera containment. No production source or asset is modified.
## godot --headless --path . --script tests/presentation_v3_test.gd
## -- --simulation-only runs the pure combat contract before assets arrive.
const Combat = preload("res://scripts/combat.gd")
const DT := 1.0 / 60.0
const EPS := 0.0001
# Filled only from the animator's final per-facing authored support contract.
const SUPPORT_SAMPLES := {
	# Final authored contract: both characters/facings support with both hands in catch.
	# .80s hold is a low kneel; its hands are intentionally not floor supports.
	"0:-1": {"hands": ["L", "R"], "times": [14.0 / 30.0, 0.50]},
	"0:1": {"hands": ["L", "R"], "times": [14.0 / 30.0, 0.50]},
	"1:-1": {"hands": ["L", "R"], "times": [14.0 / 30.0, 0.50]},
	"1:1": {"hands": ["L", "R"], "times": [14.0 / 30.0, 0.50]},
}
const REQUIRED_BASES := ["FightIdle", "Guard", "BackstepGuard", "Walk", "Run", "Punch", "FlyingKickStart", "FlyingKickLoop", "FlyingKickLand", "JumpStart", "JumpLoop", "JumpLand", "HitReactStrong", "Knockdown", "Recover"]
const ORIGINAL_BASES := ["BackstepGuard", "FightIdle", "FlyingKickLand", "FlyingKickLoop", "FlyingKickStart", "Guard", "HitReact", "HitReactStrong", "Idle", "JumpLand", "JumpLoop", "JumpStart", "Knockdown", "Punch", "Recover", "Run", "SitDown", "SitIdle", "StandUp", "Victory", "Walk"]
class ScriptedAI extends RefCounted:
	var command: Dictionary = {}
	func reset() -> void: command.clear()
	func act(_sim, _delta: float) -> Dictionary: return command.duplicate()

var checks := 0
var failures := 0
var game
var robot := ScriptedAI.new()
var mesh_cache: Dictionary = {}
var reference_models: Dictionary = {}
var minimum_camera_margin := INF
var camera_failure_details: Array[String] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		printerr("FAIL: ", label)

func fixture(kind: int, attacker: int = 0, wall: bool = false):
	var sim = Combat.new()
	sim.reset(kind)
	sim.fighters[0].x = -Combat.BODY
	sim.fighters[1].x = Combat.BODY
	if wall:
		var target := 1 - attacker
		var side := 1.0 if target == 1 else -1.0
		sim.fighters[target].x = Combat.RIGHT if side > 0.0 else Combat.LEFT
		sim.fighters[attacker].x = sim.fighters[target].x - side * Combat.BODY * 2.0
	return sim

func contact(sim, attacker: int, attack: String = "kick", air: bool = false, lethal: bool = false) -> Dictionary:
	var target := 1 - attacker
	if lethal: sim.fighters[target].hp = float(sim.attack_config(sim.fighters[attacker], attack).damage)
	for frame in range(90):
		var commands: Array = [{}, {}]
		if frame == 0: commands[attacker] = {attack: true}
		if air and frame == 10: commands[target] = {"jump": true}
		sim.step(DT, commands)
		for event: Dictionary in sim.events:
			if event.type == "hit" and int(event.fighter) == target: return event.duplicate()
	return {}

func simulation_tests() -> void:
	check(is_equal_approx(Combat.DOWN_FALL_DURATION, 0.8) and is_equal_approx(Combat.DOWN_HOLD_DURATION, 0.25) and is_equal_approx(Combat.DOWN_RISE_DURATION, 1.0) and is_equal_approx(Combat.DOWN_RECOVERY_INVULN, 0.35), "approved down/hold/rise/protection durations remain .8/.25/1/.35 seconds")
	for kind in range(2):
		for attacker in range(2):
			var target := 1 - attacker
			var label := "kind %d attacker %d" % [kind, attacker]
			var sim = fixture(kind, attacker)
			var event := contact(sim, attacker)
			var f: Dictionary = sim.fighters[target]
			check(not event.is_empty() and f.down and f.down_phase == "fall" and not f.down_ko and f.down_clock == 0.0 and f.hp == 87.0, label + " real grounded kick begins nonlethal fall exactly at impact")
			if event.is_empty(): continue
			var hp_after: float = f.hp
			var phases: Array[String] = ["fall"]
			var transitions: Dictionary = {}
			var locked := true
			var protected := true
			var recovered_count := 0
			for frame in range(190):
				var commands: Array = [{}, {}]
				commands[target] = {"move": 1.0, "punch": true, "kick": true, "jump": true}
				commands[attacker] = {"punch": true}
				sim.step(DT, commands)
				if f.down:
					locked = locked and f.attack == "" and not f.blocking and f.move == 0.0 and f.y == 0.0 and f.queued == ""
					protected = protected and f.hp == hp_after
					if f.down_phase != phases.back():
						phases.append(f.down_phase)
						transitions[f.down_phase] = float(frame + 1) * DT
				for emitted: Dictionary in sim.events:
					if emitted.type == "recovered" and int(emitted.fighter) == target: recovered_count += 1
				if not f.down:
					transitions["recovered"] = float(frame + 1) * DT
					break
			check(phases == ["fall", "hold", "rise"] and recovered_count == 1 and not f.down, label + " completes one fall→hold→rise→ready sequence")
			check(absf(float(transitions.get("hold", -10.0)) - 0.8) <= DT + EPS and absf(float(transitions.get("rise", -10.0)) - 1.05) <= DT + EPS and absf(float(transitions.get("recovered", -10.0)) - 2.05) <= DT + EPS, label + " phases honor approved timings without skipped hold/rise")
			check(locked and protected, label + " down/rise reject repeated actions, movement, guard and further damage")
			check(f.input_rearm and f.invuln >= 0.35 - EPS and f.stun == 0.0 and f.down_clock == 0.0, label + " recovery grants .35 protection and requires fresh action input")
			# Keep held attack/jump spam AFTER recovery; it must not become a buffered attack.
			var held_did_not_fire := true
			for frame in range(8):
				var commands: Array = [{}, {}]
				commands[target] = {"punch": true, "kick": true, "jump": true}
				sim.step(DT, commands)
				held_did_not_fire = held_did_not_fire and f.attack == "" and f.y == 0.0
			check(held_did_not_fire and f.input_rearm, label + " held recovery inputs do not repeat on wake-up")
			sim.step(DT, [{}, {}])
			var fresh_commands: Array = [{}, {}]
			fresh_commands[target] = {"punch": true}
			sim.step(DT, fresh_commands)
			check(not f.input_rearm and f.attack == "punch", label + " neutral sample then fresh press re-arms immediately")
			# The same kinds/directions still keep punch as the short hurt reaction.
			sim = fixture(kind, attacker)
			event = contact(sim, attacker, "punch")
			f = sim.fighters[target]
			check(not event.is_empty() and not f.down and is_equal_approx(f.stun, 0.24) and f.hp == 92.0, label + " punch preserves old short hurt/damage rules")
			# Both walls: actual kick contact followed by complete phase sequence.
			sim = fixture(kind, attacker, true)
			event = contact(sim, attacker)
			var wall_safe := not event.is_empty()
			for frame in range(140):
				sim.step(DT, [{}, {}])
				for fighter: Dictionary in sim.fighters:
					wall_safe = wall_safe and fighter.x >= Combat.LEFT - EPS and fighter.x <= Combat.RIGHT + EPS and fighter.y >= 0.0
				wall_safe = wall_safe and absf(sim.fighters[0].x - sim.fighters[1].x) >= Combat.BODY * 2.0 - EPS
			check(wall_safe and not sim.fighters[target].down, label + " wall knockdown/recovery remains clamped and separated")
			air_and_ko_tests(kind, attacker)
			timeout_test(kind, attacker)
			protection_test(kind, attacker)
			rearm_boundary_test(kind, attacker)

func air_and_ko_tests(kind: int, attacker: int) -> void:
	var target := 1 - attacker
	var label := "kind %d attacker %d" % [kind, attacker]
	var sim = fixture(kind, attacker)
	var event := contact(sim, attacker, "kick", true)
	var f: Dictionary = sim.fighters[target]
	check(not event.is_empty() and f.down and f.down_phase == "air" and f.y > 0.0, label + " actual jumping victim enters airborne loss instead of floor pose")
	var landed := false
	var air_samples := 0
	for frame in range(60):
		sim.step(DT, [{}, {}])
		if f.down_phase == "air": air_samples += 1
		if f.down_phase == "fall":
			landed = f.y == 0.0 and f.vy == 0.0 and is_equal_approx(f.down_clock, 0.20)
			break
	check(air_samples > 0 and landed, label + " physical landing resumes floor fall at .20 seconds")
	for attack in ["punch", "kick"]:
		sim = fixture(kind, attacker)
		event = contact(sim, attacker, attack, true, true)
		f = sim.fighters[target]
		check(not event.is_empty() and sim.round_over and f.down and f.down_ko and f.hp == 0.0, label + " lethal " + attack + " enters permanent KO path")
		var elapsed: float = sim.elapsed
		var timer: float = sim.time_left
		var standing_before: Dictionary = sim.fighters[attacker].duplicate(true)
		var no_rise := true
		for frame in range(300):
			sim.step_post_round(DT)
			no_rise = no_rise and f.down and f.down_phase != "rise" and f.hp == 0.0
		check(no_rise and f.down_phase == "hold" and f.y == 0.0, label + " KO " + attack + " settles then holds forever without recovery")
		check(sim.elapsed == elapsed and sim.time_left == timer and post_round_frozen_except_landing(standing_before, sim.fighters[attacker]), label + " post-round KO keeps combat/timer frozen and only settles existing flight")

func timeout_test(kind: int, attacker: int) -> void:
	var sim = fixture(kind, attacker)
	var target := 1 - attacker
	var event := contact(sim, attacker)
	sim.time_left = DT * 0.5
	sim.step(DT, [{"punch": true}, {"kick": true}])
	var winner: int = sim.winner
	var elapsed: float = sim.elapsed
	var hp := [sim.fighters[0].hp, sim.fighters[1].hp]
	var standing_before: Dictionary = sim.fighters[attacker].duplicate(true)
	var no_new_combat := true
	for frame in range(180):
		sim.step_post_round(DT)
		for emitted: Dictionary in sim.events:
			no_new_combat = no_new_combat and emitted.type not in ["attack", "hit", "block", "break", "round"]
	check(not event.is_empty() and sim.round_over and not sim.fighters[target].down and no_new_combat, "kind %d attacker %d timeout finishes already-started living recovery only" % [kind, attacker])
	check(sim.winner == winner and sim.elapsed == elapsed and sim.time_left == 0.0 and hp == [sim.fighters[0].hp, sim.fighters[1].hp] and post_round_frozen_except_landing(standing_before, sim.fighters[attacker]), "kind %d attacker %d timeout recovery preserves result, timer, health and frozen combat while existing flight settles" % [kind, attacker])

func post_round_frozen_except_landing(before: Dictionary, after: Dictionary) -> bool:
	var was_airborne: bool = before.y > 0.0 or before.vy > 0.0
	for key in before:
		if key in ["x", "y", "vx", "vy", "land_lock"]: continue
		if before[key] != after[key]: return false
	if was_airborne:
		return after.y == 0.0 and after.vy == 0.0 and after.vx == 0.0 and after.x >= Combat.LEFT and after.x <= Combat.RIGHT
	return before.x == after.x and before.y == after.y and before.vx == after.vx and before.vy == after.vy

func protection_test(kind: int, attacker: int) -> void:
	var sim = fixture(kind, attacker)
	var target := 1 - attacker
	contact(sim, attacker)
	for frame in range(150):
		sim.step(DT, [{}, {}])
		if not sim.fighters[target].down: break
	var f: Dictionary = sim.fighters[target]
	var hp: float = f.hp
	var first_damage_time := -1.0
	var premature := false
	# Snapshot pressure probe: arrange a fresh active punch contact every frame
	# to measure the protection boundary independently of attack recovery cadence.
	for frame in range(30):
		var a: Dictionary = sim.fighters[attacker]
		a.x = -Combat.BODY if attacker == 0 else Combat.BODY
		f.x = Combat.BODY if target == 1 else -Combat.BODY
		a.attack = ""; a.stun = 0.0; a.chain = 0; a.y = 0.0; a.vy = 0.0
		sim.begin_attack(a, "punch")
		# v4 reaches pushbox-separated targets only after its hand extends.
		# A mid-active snapshot still isolates exactly the .35s protection edge.
		var cfg: Dictionary = sim.attack_config(a, "punch")
		a.clock = cfg.startup + cfg.active * 0.5 - DT + 0.00001
		var before_invuln: float = f.invuln
		sim.step(DT, [{}, {}])
		if f.hp < hp:
			first_damage_time = float(frame + 1) * DT
			premature = before_invuln > DT + EPS
			break
	check(not premature and absf(first_damage_time - 0.35) <= DT + EPS, "kind %d attacker %d active contact pressure cannot damage before .35s protection and can immediately after" % [kind, attacker])
	# A timeout may be won by the fighter who is currently down.
	sim = fixture(kind, attacker)
	contact(sim, attacker)
	sim.fighters[attacker].hp = 20.0
	sim.time_left = 0.001
	sim.step(DT, [{}, {}])
	for frame in range(170): sim.step_post_round(DT)
	check(sim.winner == target and not sim.fighters[target].down and sim.fighters[target].hp == 87.0 and sim.time_left == 0.0, "kind %d attacker %d living downed timeout winner completes recovery without altering result" % [kind, attacker])

func rearm_boundary_test(kind: int, attacker: int) -> void:
	var target := 1 - attacker
	var label := "kind %d attacker %d" % [kind, attacker]
	var sim = fixture(kind, attacker)
	contact(sim, attacker)
	for frame in range(150):
		sim.step(DT, [{}, {}]) # Release during the sequence, not an extra ready-frame release.
		if not sim.fighters[target].down: break
	var fresh: Array = [{}, {}]
	fresh[target] = {"punch": true}
	sim.step(DT, fresh)
	check(not sim.fighters[target].input_rearm and sim.fighters[target].attack == "punch", label + " release during down permits fresh input on first ready frame")
	sim = fixture(kind, attacker)
	contact(sim, attacker)
	var f: Dictionary = sim.fighters[target]
	for frame in range(150):
		if f.down_phase == "rise" and f.down_clock >= 1.0 - DT - EPS: break
		sim.step(DT, [{}, {}])
	var held: Array = [{}, {}]
	held[target] = {"kick": true}
	var fired := false
	for frame in range(10):
		sim.step(DT, held)
		fired = fired or f.attack != ""
	check(not f.down and not fired and f.input_rearm, label + " press on recovery-completing frame is consumed and cannot buffer")
	sim.step(DT, [{}, {}]); sim.step(DT, held)
	check(not f.input_rearm and f.attack == "kick", label + " consumed completion-frame press works after release and fresh press")

func expected_clip(base: String, face: int) -> String:
	return base + ("_R" if face > 0 else "_L")

func base_clip(clip: String) -> String:
	return clip.trim_suffix("_R").trim_suffix("_L")

func setup_game(kind: int = 0) -> void:
	game.hud._choose(kind)
	game.brain = robot
	robot.reset()
	game.set_physics_process(false)
	game.auto_demo = false
	game.muted = true
	game.sim.fighters[0].x = -Combat.BODY
	game.sim.fighters[1].x = Combat.BODY
	game.render_state(0.0)

func tick_game(first: Dictionary = {}, second: Dictionary = {}, delta: float = DT) -> void:
	game.held.clear(); game.taps.clear()
	var move := float(first.get("move", 0.0))
	if move > 0.0: game.held.right = true
	if move < 0.0: game.held.left = true
	for action in ["jump", "punch", "kick"]:
		if first.get(action, false): game.taps[action] = true
	robot.command = second.duplicate()
	game._physics_process(delta)

func game_contact(kind: int, attacker: int, air: bool = false, lethal: bool = false) -> bool:
	setup_game(kind)
	var target := 1 - attacker
	if lethal: game.sim.fighters[target].hp = 13.0
	for frame in range(90):
		var commands: Array = [{}, {}]
		if frame == 0: commands[attacker] = {"kick": true}
		if air and frame == 10: commands[target] = {"jump": true}
		tick_game(commands[0], commands[1])
		if game.sim.fighters[target].down: return true
	return false

func pose_contract(f: Dictionary) -> Dictionary:
	if f.down:
		if f.down_phase == "rise": return {"base": "Recover", "time": minf(1.0, float(f.down_clock))}
		var time: float = minf(0.2, maxf(0.04, float(f.down_clock))) if f.down_phase == "air" else (0.8 if f.down_phase == "hold" else minf(0.8, maxf(0.04, float(f.down_clock))))
		return {"base": "Knockdown", "time": time}
	return {"base": "FightIdle", "time": -1.0}

func verify_pose(index: int) -> bool:
	var f: Dictionary = game.sim.fighters[index]
	var contract := pose_contract(f)
	var desired := expected_clip(contract.base, int(f.face))
	if game.current_clips[index] != desired: return false
	if not game.actors[index].position.is_equal_approx(Vector3(f.x, f.y, 0.0)): return false
	if absf(game.actors[index].rotation.y - float(f.face) * PI / 2.0) > EPS: return false
	if contract.time >= 0.0 and absf(game.anims[index].current_animation_position - float(contract.time)) > 0.002: return false
	return true

func render_tests() -> void:
	for kind in range(2):
		setup_game(kind)
		for index in range(2):
			var original_missing: Array[String] = []
			for base in ORIGINAL_BASES:
				if not game.anims[index].has_animation(base): original_missing.append(base)
			check(original_missing.is_empty(), "selection %d fighter %d preserves all original 21 clips" % [kind, index])
			var missing: Array[String] = []
			for base in REQUIRED_BASES:
				for face in [-1, 1]:
					if not game.anims[index].has_animation(expected_clip(base, face)): missing.append(expected_clip(base, face))
			check(missing.is_empty(), "selection %d fighter %d mandatory baked variants: %s" % [kind, index, str(missing)])
		game.show_menu(); game.render_state(0.0)
		check(game.current_clips == ["Idle", "Idle"], "selection %d preserves original unsuffixed menu Idle" % kind)
		for attacker in range(2):
			for air in [false, true]:
				var target := 1 - attacker
				var label := "selection %d attacker %d air %s" % [kind, attacker, str(air)]
				var hit := game_contact(kind, attacker, air)
				var phases: Array[String] = []
				var authored_pose := true
				var valid := hit and verify_pose(target)
				var fixed_model_rotation: Vector3 = game.actors[target].get_child(0).rotation
				for frame in range(210):
					var f: Dictionary = game.sim.fighters[target]
					if f.down and (phases.is_empty() or phases.back() != f.down_phase):
						phases.append(f.down_phase)
						if f.down_phase in ["hold", "rise"]: authored_pose = authored_pose and matches_authored_bone_pose(target)
					valid = valid and verify_pose(target) and game.actors[target].get_child(0).rotation.is_equal_approx(fixed_model_rotation)
					if not f.down: break
					tick_game()
				check(valid and not game.sim.fighters[target].down and "fall" in phases and "hold" in phases and "rise" in phases, label + " maps every down/rise clock to baked facing clip, then FightIdle, without model twist")
				check(authored_pose, label + " runtime bones exactly match baked clip, with no extra torso twist")
				if air: check("air" in phases, label + " validates airborne pose cap before actual landing")
			crossup_test(kind)
	pause_rematch_tests()
	result_settling_tests()
	fresh_main_input_test()
	locomotion_and_turnaround_tests()

func crossup_test(kind: int) -> void:
	setup_game(kind)
	var crossed := false
	var mapped := true
	for frame in range(65):
		var first := {"move": 1.0}
		if frame == 0: first.jump = true
		tick_game(first, {"move": -1.0})
		crossed = crossed or game.sim.fighters[0].x > game.sim.fighters[1].x
		for i in range(2):
			var face: int = game.sim.fighters[i].face
			var clip: String = game.current_clips[i]
			var mapped_clip := expected_clip(base_clip(clip), face)
			if not game.anims[i].has_animation(mapped_clip): mapped_clip = base_clip(clip)
			mapped = mapped and clip == mapped_clip and absf(game.actors[i].rotation.y - face * PI / 2.0) <= EPS
	check(crossed and mapped, "kind %d actual cross-up switches baked clip side while preserving root face × PI/2" % kind)

func pause_rematch_tests() -> void:
	for phase in ["fall", "hold", "rise"]:
		for notification in [0, Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
			game_contact(0, 0)
			for frame in range(170):
				if game.sim.fighters[1].down_phase == phase: break
				tick_game()
			game.on_command("right", true); game.on_command("kick", true)
			if notification == 0: game.toggle_pause()
			else: game._notification(notification)
			var before: Array = game.sim.fighters.duplicate(true)
			var clock: float = game.anims[1].current_animation_position
			var timer: float = game.sim.time_left
			game._physics_process(0.5)
			check(game.paused and game.sim.fighters == before and game.sim.time_left == timer and game.anims[1].current_animation_position == clock and game.held.is_empty() and game.taps.is_empty(), "%s notification %d freezes phase/pose/timer and clears inputs" % [phase, notification])
			game.hud._request_rematch(); game.render_state(0.0)
			var clean: bool = game.playing and not game.paused and game.hitstop == 0.0 and game.round_delay == 0.0 and game.wins == [0, 0]
			for f: Dictionary in game.sim.fighters:
				clean = clean and not f.down and f.down_phase == "" and f.down_clock == 0.0 and f.down_age == 0.0 and not f.down_ko and not f.input_rearm and f.hp == 100.0
			check(clean and verify_pose(0) and verify_pose(1), "%s notification %d rematch fully resets down/presentation state" % [phase, notification])

func result_settling_tests() -> void:
	for attacker in range(2):
		var target := 1 - attacker
		game_contact(0, attacker, true, true)
		game.wins[attacker] = 2
		var presented_at := -1.0
		for frame in range(190):
			tick_game()
			if not game.playing:
				presented_at = float(frame + 1) * DT
				break
		check(presented_at >= 2.4 - EPS and presented_at <= 2.4 + DT * 1.1, "attacker %d naturally settled result preserves minimum 2.4-second round delay" % attacker)
		game_contact(0, attacker, true, true)
		game.wins[attacker] = 2
		game.round_delay = 0.01 # Isolate readiness gate from the minimum-delay countdown.
		var shown_before_settled := false
		var pose_valid := true
		for frame in range(180):
			tick_game({"kick": true}, {"punch": true})
			var f: Dictionary = game.sim.fighters[target]
			pose_valid = pose_valid and verify_pose(target)
			if not game.playing:
				shown_before_settled = f.down_phase != "hold" or f.y != 0.0
				break
		check(not game.playing and not shown_before_settled and game.sim.fighters[target].down_ko and game.sim.fighters[attacker].y == 0.0 and game.sim.fighters[attacker].land_lock == 0.0, "attacker %d airborne winning kick lands/settles before KO result" % attacker)
		check(pose_valid, "attacker %d KO uses correct baked loss/hold pose throughout result settling" % attacker)
		check(base_clip(game.current_clips[attacker]) == "Victory", "attacker %d settled round winner retains Victory" % attacker)
		for winner_down in [false, true]:
			game_contact(0, attacker)
			if winner_down: game.sim.fighters[attacker].hp = 20.0
			game.sim.time_left = 0.001
			game.hitstop = 0.0
			tick_game()
			var winner: int = game.sim.winner
			game.wins[winner] = 2
			game.round_delay = 0.01
			var premature := false
			var result_hp := [game.sim.fighters[0].hp, game.sim.fighters[1].hp]
			var result_serial: int = game.sim.attack_serial
			for frame in range(200):
				tick_game({"kick": true}, {"punch": true})
				if not game.playing:
					premature = game.sim.fighters[target].down or game.sim.fighters[attacker].y > 0.0
					break
			check(not game.playing and not premature and not game.sim.fighters[target].down and game.sim.time_left == 0.0 and game.sim.attack_serial == result_serial and result_hp == [game.sim.fighters[0].hp, game.sim.fighters[1].hp], "attacker %d down-winner %s timeout waits for recovery, ignoring repeated combat inputs" % [attacker, str(winner_down)])
			check(base_clip(game.current_clips[winner]) == "Victory", "attacker %d down-winner %s timeout winner celebrates only after recovery" % [attacker, str(winner_down)])
		game_contact(0, attacker, true, true)
		game.toggle_pause()
		var frozen: Array = game.sim.fighters.duplicate(true)
		var result_delay: float = game.round_delay
		game._physics_process(0.5)
		check(game.paused and game.sim.fighters == frozen and game.round_delay == result_delay, "attacker %d pause also freezes airborne KO result settling" % attacker)
		game.hud._request_rematch(); game.render_state(0.0)
		check(game.playing and not game.paused and not game.sim.round_over and not game.sim.fighters[target].down and game.wins == [0, 0] and game.round_delay == 0.0, "attacker %d rematch interrupts pending KO settlement cleanly" % attacker)

func fresh_main_input_test() -> void:
	for kind in range(2):
		game_contact(kind, 1) # Player at index 0 is the knocked-down fighter.
		for frame in range(180):
			tick_game()
			if not game.sim.fighters[0].down: break
		robot.command = {}
		game.on_command("punch", true)
		game._physics_process(DT)
		check(game.sim.fighters[0].attack == "punch" and base_clip(game.current_clips[0]) == "Jab", "kind %d main edge-only fresh press works on first ready frame after release during down" % kind)

func locomotion_and_turnaround_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			setup_game(kind)
			game.sim.fighters[0].x = -0.8 * face
			game.sim.fighters[1].x = 0.8 * face
			var seen: Array[String] = []
			var mapped := true
			for frame in range(65):
				var command := {"move": float(face)}
				if frame == 0: command.jump = true
				tick_game(command)
				var clip: String = game.current_clips[0]
				var base := base_clip(clip)
				if base not in seen: seen.append(base)
				mapped = mapped and clip == expected_clip(base, int(game.sim.fighters[0].face))
			check(mapped and "JumpStart" in seen and "JumpLoop" in seen and "JumpLand" in seen and "Run" in seen, "kind %d face %d actual jump/run/landing uses paired clips throughout: %s" % [kind, face, str(seen)])
			setup_game(kind)
			game.sim.fighters[0].x = -Combat.BODY * face
			game.sim.fighters[1].x = Combat.BODY * face
			tick_game({"move": -float(face)})
			var backstep: bool = game.current_clips[0] == expected_clip("BackstepGuard", face)
			game.sim.fighters[0].x = Combat.LEFT if face > 0 else Combat.RIGHT
			tick_game({"move": -float(face)})
			check(backstep and game.current_clips[0] == expected_clip("Guard", face), "kind %d face %d retreat and wall guard map their baked sides" % [kind, face])
		for base in ["FightIdle", "Run", "JumpLoop"]:
			setup_game(kind)
			var f: Dictionary = game.sim.fighters[0]
			f.face = 1; f.move = 1.0; f.vx = 2.4 if base == "Run" else 0.0
			f.y = 0.5 if base == "JumpLoop" else 0.0; f.vy = 0.0
			game.render_state(0.23)
			var continuous: bool = game.current_clips[0] == expected_clip(base, 1)
			var authored := true
			var root_position: Vector3 = game.actors[0].position
			for face in [-1, 1]:
				var before_time: float = game.anims[0].current_animation_position
				f.face = face; f.move = float(face)
				f.vx = float(face) * 2.4 if base == "Run" else 0.0
				game.render_state(0.0)
				continuous = continuous and game.current_clips[0] == expected_clip(base, face) and absf(game.anims[0].current_animation_position - before_time) <= 0.002 and game.actors[0].position == root_position
				authored = authored and matches_authored_bone_pose(0)
			check(continuous, "kind %d %s turnaround both ways preserves phase and physical root" % [kind, base])
			check(authored, "kind %d %s turnaround uses exact new-facing bones, not wrong-side interpolation" % [kind, base])

func reference_model(kind: int) -> Dictionary:
	if not reference_models.has(kind):
		var path := "res://assets/purple.glb" if kind == 0 else "res://assets/yellow.glb"
		var model = load(path).instantiate()
		root.add_child(model)
		model.visible = false
		var player = model.find_child("AnimationPlayer", true, false)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
		reference_models[kind] = {"model": model, "player": player, "skeleton": skeleton}
	return reference_models[kind]

func matches_authored_bone_pose(index: int) -> bool:
	var reference := reference_model(int(game.sim.fighters[index].kind))
	var clip: String = game.current_clips[index]
	if not reference.player.has_animation(clip): return false
	reference.player.play(clip, 0.0)
	reference.player.seek(game.anims[index].current_animation_position, true)
	reference.player.advance(0.0)
	var actual = game.actors[index].find_children("*", "Skeleton3D", true, false)[0]
	if actual.get_bone_count() != reference.skeleton.get_bone_count(): return false
	for bone in range(actual.get_bone_count()):
		if actual.get_bone_name(bone) != reference.skeleton.get_bone_name(bone): return false
		if not actual.get_bone_pose_position(bone).is_equal_approx(reference.skeleton.get_bone_pose_position(bone)): return false
		if not actual.get_bone_pose_rotation(bone).is_equal_approx(reference.skeleton.get_bone_pose_rotation(bone)): return false
		if not actual.get_bone_pose_scale(bone).is_equal_approx(reference.skeleton.get_bone_pose_scale(bone)): return false
	return true

func native_bone_transform(reference: Dictionary, bone: int, rest: bool = false) -> Transform3D:
	var pose: Transform3D = reference.skeleton.get_bone_global_rest(bone) if rest else reference.skeleton.get_bone_global_pose(bone)
	return reference.model.global_transform.affine_inverse() * reference.skeleton.global_transform * pose

func strike_endpoints(reference: Dictionary, clip: String, time: float, landmarks: Dictionary) -> Dictionary:
	reference.player.play(clip, 0.0)
	reference.player.seek(time, true)
	reference.player.advance(0.0)
	reference.skeleton.force_update_all_bone_transforms()
	var result: Dictionary = {}
	for side in ["L", "R"]:
		for part in ["wrist", "hand", "ankle", "toe", "toe_end"]:
			var bone_name: String = ("DEF-hand." if part in ["wrist", "hand"] else ("DEF-foot." if part == "ankle" else "DEF-toe.")) + side
			var bone: int = reference.skeleton.find_bone(bone_name)
			var toe_uses_foot := false
			if bone < 0 and part in ["toe", "toe_end"]:
				bone = reference.skeleton.find_bone("DEF-foot." + side)
				toe_uses_foot = true # Yellow has no separate toe bone; its foot controls the toe endpoint.
			if bone < 0: continue
			var local := Vector3.ZERO
			if part in ["hand", "toe_end"] or (part == "toe" and toe_uses_foot):
				var landmark_key: String = ("hand_end." if part == "hand" else ("toe." if part == "toe" else "toe_end.")) + side
				var landmark: Array = landmarks[landmark_key]
				# Authored landmarks are Blender Z-up/-Y-forward. GLTF is Y-up/+Z-forward.
				var native_tail := Vector3(float(landmark[0]), float(landmark[2]), -float(landmark[1]))
				local = native_bone_transform(reference, bone, true).affine_inverse() * native_tail
			result[part + "." + side] = native_bone_transform(reference, bone) * local
	var head_bone: int = reference.skeleton.find_bone("DEF-spine.006")
	if head_bone >= 0: result["head"] = native_bone_transform(reference, head_bone).origin
	return result

func load_landmarks(kind: int) -> Dictionary:
	var path := "res://tests/fixtures/Lavender-landmarks.json" if kind == 0 else "res://tests/fixtures/YellowWhite-landmarks.json"
	if not FileAccess.file_exists(path):
		check(false, "kind %d required independent native endpoint evidence missing: %s" % [kind, path])
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var valid: bool = parsed is Dictionary
	if valid:
		for side in ["L", "R"]:
			for part in ["hand_end", "toe", "toe_end"]:
				var key: String = part + "." + side
				if not parsed.has(key) or not parsed[key] is Array or parsed[key].size() != 3:
					valid = false
					continue
				for number in parsed[key]:
					if not (number is float or number is int) or not is_finite(float(number)): valid = false
	check(valid, "kind %d independent native strike endpoint landmarks available and complete" % kind)
	return parsed if valid else {}

func independent_strike_distance_tests() -> void:
	for kind in range(2):
		var reference := reference_model(kind)
		var landmarks := load_landmarks(kind)
		if landmarks.is_empty(): continue
		for base in ["Punch", "FlyingKickLoop"]:
			var baseline := strike_endpoints(reference, base, 0.20, landmarks)
			var lead_part := "hand" if base == "Punch" else "toe_end"
			if not baseline.has(lead_part + ".L") or not baseline.has(lead_part + ".R"):
				check(false, "kind %d %s strike endpoints are measurable" % [kind, base])
				continue
			var side: String = "L" if baseline[lead_part + ".L"].z >= baseline[lead_part + ".R"].z else "R"
			var endpoints: Array = ["wrist." + side, "hand." + side] if base == "Punch" else ["ankle." + side, "toe." + side, "toe_end." + side]
			for endpoint: String in endpoints:
				print("STRIKE BASELINE kind=%d %s @.20 endpoint=%s native=%s" % [kind, base, endpoint, str(baseline[endpoint])])
			var config: Dictionary = Combat.new().attack_config({"kind": kind}, "punch" if base == "Punch" else "kick")
			var length: float = reference.player.get_animation(base).length
			var duration: float = config.startup + config.active + config.recovery
			var start: float = config.startup / duration * length if base == "Punch" else config.startup - 0.23
			var end: float = (config.startup + config.active) / duration * length if base == "Punch" else config.startup + config.active - 0.23
			for face in [-1, 1]:
				var variant := expected_clip(base, face)
				var available: bool = reference.player.has_animation(variant)
				check(available, "kind %d independent reach comparison has %s" % [kind, variant])
				if not available: continue
				var points := strike_endpoints(reference, variant, 0.20, landmarks)
				var peak_forward_max := 0.0
				var peak_spatial_max := 0.0
				for endpoint: String in endpoints:
					var difference: Vector3 = points[endpoint] - baseline[endpoint]
					peak_forward_max = maxf(peak_forward_max, absf(difference.z))
					peak_spatial_max = maxf(peak_spatial_max, difference.length())
					print("STRIKE DISTANCE kind=%d %s @.20 endpoint=%s original=%s variant=%s delta=%s native_m (forward_delta=%.6f)" % [kind, variant, endpoint, str(baseline[endpoint]), str(points[endpoint]), str(difference), difference.z])
				check(peak_forward_max <= 0.030001, "kind %d %s .20s forward endpoint drift ≤ .03m native (actual %.6fm)" % [kind, variant, peak_forward_max])
				var path_forward_max := 0.0
				var path_spatial_max := 0.0
				for sample in range(9):
					var time: float = lerpf(start, end, float(sample) / 8.0)
					var original_path := strike_endpoints(reference, base, time, landmarks)
					var variant_path := strike_endpoints(reference, variant, time, landmarks)
					for endpoint: String in endpoints:
						var difference: Vector3 = variant_path[endpoint] - original_path[endpoint]
						path_forward_max = maxf(path_forward_max, absf(difference.z))
						path_spatial_max = maxf(path_spatial_max, difference.length())
				print("STRIKE PATH kind=%d %s active_window=%.6f..%.6f native_peak_3D=%.6fm max_forward=%.6fm max_3D=%.6fm" % [kind, variant, start, end, peak_spatial_max, path_forward_max, path_spatial_max])
				check(path_forward_max <= 0.030001, "kind %d %s active-path forward drift ≤ .03m native (actual %.6fm)" % [kind, variant, path_forward_max])

func settle_endpoint_tests() -> void:
	for kind in range(2):
		var reference := reference_model(kind)
		var landmarks := load_landmarks(kind)
		if landmarks.is_empty(): continue
		for face in [-1, 1]:
			var ready_clip := expected_clip("FightIdle", face)
			if not reference.player.has_animation(ready_clip): continue
			var ready := strike_endpoints(reference, ready_clip, 0.0, landmarks)
			for base in ["JumpLand", "FlyingKickLand", "Recover"]:
				var clip := expected_clip(base, face)
				if not reference.player.has_animation(clip): continue
				var length: float = reference.player.get_animation(clip).length
				var end := strike_endpoints(reference, clip, length, landmarks)
				var largest := 0.0
				var complete := true
				for endpoint in ["ankle.L", "ankle.R", "toe_end.L", "toe_end.R", "wrist.L", "wrist.R", "head"]:
					if not ready.has(endpoint) or not end.has(endpoint):
						complete = false
						continue
					var delta: Vector3 = end[endpoint] - ready[endpoint]
					largest = maxf(largest, delta.length())
					print("SETTLE ENDPOINT kind=%d %s end %.6f -> %s phase0 %s ready=%s end=%s delta=%s native_m length=%.6f" % [kind, clip, length, ready_clip, endpoint, str(ready[endpoint]), str(end[endpoint]), str(delta), delta.length()])
				check(complete and largest <= 0.001, "kind %d %s claimed exact settle endpoint matches FightIdle within 1mm numerical tolerance (actual %.6fm)" % [kind, clip, largest])

func gather_meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children(): gather_meshes(child, result)

func skin_data(model: Node) -> Array:
	var key := model.get_instance_id()
	if mesh_cache.has(key): return mesh_cache[key]
	var meshes: Array = []
	gather_meshes(model, meshes)
	var data: Array = []
	for mesh: MeshInstance3D in meshes:
		var skeleton = mesh.get_node_or_null(mesh.skeleton)
		var skin: Skin = mesh.skin
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			var binds: Array = []
			if skeleton is Skeleton3D and skin != null and bones != null and weights != null:
				for bind in range(skin.get_bind_count()):
					var bone: int = skin.get_bind_bone(bind)
					if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(bind))
					binds.append({"bone": bone, "rest": skin.get_bind_pose(bind)})
			data.append({"mesh": mesh, "skeleton": skeleton, "vertices": vertices, "bones": bones, "weights": weights, "binds": binds})
	mesh_cache[key] = data
	return data

func posed_world_vertices(model: Node) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface: Dictionary in skin_data(model):
		var vertices: PackedVector3Array = surface.vertices
		var transforms: Array[Transform3D] = []
		var skeleton = surface.skeleton
		if skeleton is Skeleton3D and not surface.binds.is_empty():
			skeleton.force_update_all_bone_transforms()
			for bind: Dictionary in surface.binds:
				transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bind.bone) * bind.rest if bind.bone >= 0 else surface.mesh.global_transform)
		var stride: int = int(surface.bones.size() / vertices.size()) if surface.bones != null and not vertices.is_empty() else 0
		for index in range(vertices.size()):
			var point := Vector3.ZERO
			var total := 0.0
			if not transforms.is_empty():
				for influence in range(stride):
					var offset := index * stride + influence
					var weight: float = surface.weights[offset]
					var bone: int = surface.bones[offset]
					if weight > 0.0 and bone >= 0 and bone < transforms.size():
						point += (transforms[bone] * vertices[index]) * weight
						total += weight
			if total <= 0.0: point = surface.mesh.global_transform * vertices[index]
			result.append(point)
	return result

func posed_hand_skin_vertices(model: Node) -> Dictionary:
	var regions: Dictionary = {"L": PackedVector3Array(), "R": PackedVector3Array()}
	var to_native: Transform3D = model.global_transform.affine_inverse()
	for surface: Dictionary in skin_data(model):
		if surface.binds.is_empty() or not surface.skeleton is Skeleton3D: continue
		var skeleton: Skeleton3D = surface.skeleton
		skeleton.force_update_all_bone_transforms()
		var transforms: Array[Transform3D] = []
		var hand_sides: Array[String] = []
		for bind: Dictionary in surface.binds:
			transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bind.bone) * bind.rest if bind.bone >= 0 else surface.mesh.global_transform)
			var name: String = skeleton.get_bone_name(bind.bone) if bind.bone >= 0 else ""
			hand_sides.append("L" if name.begins_with("DEF-hand.L") else ("R" if name.begins_with("DEF-hand.R") else ""))
		var vertices: PackedVector3Array = surface.vertices
		var stride: int = int(surface.bones.size() / vertices.size()) if not vertices.is_empty() else 0
		for index in range(vertices.size()):
			var point := Vector3.ZERO
			var left_weight := 0.0
			var right_weight := 0.0
			for influence in range(stride):
				var offset := index * stride + influence
				var weight: float = surface.weights[offset]
				var bind_index: int = surface.bones[offset]
				if weight <= 0.0 or bind_index < 0 or bind_index >= transforms.size(): continue
				point += (transforms[bind_index] * vertices[index]) * weight
				if hand_sides[bind_index] == "L": left_weight += weight
				elif hand_sides[bind_index] == "R": right_weight += weight
			if left_weight >= 0.5: regions.L.append(to_native * point)
			if right_weight >= 0.5: regions.R.append(to_native * point)
	return regions

func settled_support_measurements() -> void:
	for kind in range(2):
		var reference := reference_model(kind)
		for face in [0, -1, 1]:
			var clip := "Knockdown" if face == 0 else expected_clip("Knockdown", face)
			if not reference.player.has_animation(clip): continue
			var support: Dictionary = SUPPORT_SAMPLES.get("%d:%d" % [kind, face], {})
			if face != 0: check(not support.is_empty(), "kind %d %s has explicit final authored support-hand/time contract" % [kind, clip])
			var times: Array[float] = [0.46, 0.80]
			for authored_time in support.get("times", []):
				if float(authored_time) not in times: times.append(float(authored_time))
			for time in times:
				reference.player.play(clip, 0.0)
				reference.player.seek(time, true)
				reference.player.advance(0.0)
				var regions := posed_hand_skin_vertices(reference.model)
				for side in ["L", "R"]:
					var vertices: PackedVector3Array = regions[side]
					var heights: Array[float] = []
					var close_vertices := 0
					for point in vertices:
						heights.append(point.y)
						if point.y >= -0.002 and point.y <= 0.025: close_vertices += 1
					heights.sort()
					var lowest: float = heights[0] if not heights.is_empty() else INF
					var lower_tenth: float = heights[int(floor(heights.size() * 0.1))] if not heights.is_empty() else INF
					print("HAND SUPPORT kind=%d %s time=%.3f hand=%s weighted_vertices=%d skin_min_y=%.6fm skin_p10_y=%.6fm vertices_within_floor_25mm=%d (native asset meters, >=50%% DEF-hand weight)" % [kind, clip, time, side, heights.size(), lowest, lower_tenth, close_vertices])
					check(heights.size() >= 12, "kind %d %s @%.3f hand %s uses actual weighted skin, not a bone center" % [kind, clip, time, side])
					if face != 0 and side in support.get("hands", []) and time in support.get("times", []):
						check(lowest >= -0.002 and lowest <= 0.025, "kind %d %s @%.3f intended support hand %s has visible floor contact (min %.6fm, patch vertices %d)" % [kind, clip, time, side, lowest, close_vertices])
				var bounds_min := Vector3(INF, INF, INF)
				var bounds_max := Vector3(-INF, -INF, -INF)
				var to_native: Transform3D = reference.model.global_transform.affine_inverse()
				for world_point in posed_world_vertices(reference.model):
					var point: Vector3 = to_native * world_point
					bounds_min = bounds_min.min(point); bounds_max = bounds_max.max(point)
				print("DOWN FOOTPRINT kind=%d %s time=%.3f native_min=%s native_max=%s lateral_width=%.6fm forward_back_length=%.6fm backward_extent=%.6fm overall_skin_floor=%.6fm" % [kind, clip, time, str(bounds_min), str(bounds_max), bounds_max.x - bounds_min.x, bounds_max.z - bounds_min.z, maxf(0.0, -bounds_min.z), bounds_min.y])
				if face != 0 and is_equal_approx(time, 0.8):
					check(bounds_min.y >= -0.002 and bounds_min.y <= 0.025, "kind %d %s settled low kneel has body/floor support independently of non-supporting hands" % [kind, clip])

func camera_tests() -> void:
	var fixtures := [Vector2i(1280, 800), Vector2i(844, 390), Vector2i(390, 844), Vector2i(375, 667)]
	var samples: Array = [{"phase": "air", "clock": 0.0, "height": 0.68}, {"phase": "air", "clock": 0.2, "height": 0.68}, {"phase": "air", "clock": 0.4, "height": 0.68}, {"phase": "", "clock": 0.0}, {"phase": "fall", "clock": 0.0}, {"phase": "fall", "clock": 0.2}, {"phase": "fall", "clock": 0.4}, {"phase": "fall", "clock": 0.6}, {"phase": "hold", "clock": 0.0}, {"phase": "hold", "clock": 2.0, "ko": true}, {"phase": "rise", "clock": 0.0}, {"phase": "rise", "clock": 0.25}, {"phase": "rise", "clock": 0.5}, {"phase": "rise", "clock": 0.75}, {"phase": "rise", "clock": 1.0}]
	for dims in fixtures:
		root.size = dims
		await process_frame
		await process_frame
		game.layout_camera()
		var camera_initial: Transform3D = game.camera.global_transform
		var camera_size_initial: float = game.camera.size
		var camera_offset_initial: float = game.camera.v_offset
		var limit: float = dims.y * game.hud.gameplay_height_ratio()
		var top: float = game.hud._match_panel.position.y + game.hud._match_panel.size.y
		for kind in range(2):
			setup_game(kind)
			var sample_count := 0
			var vertices_seen := 0
			var contained := true
			var fixed_camera := true
			for face in [-1, 1]:
				for edge in [Combat.LEFT, Combat.RIGHT]:
					for sample: Dictionary in samples:
						var f: Dictionary = game.sim.fighters[0]
						f.x = edge; f.y = float(sample.get("height", 0.0)); f.vy = 0.0; f.vx = 0.0; f.face = face
						f.attack = ""; f.stun = 0.0; f.blocking = false
						f.down = sample.phase != ""; f.down_phase = sample.phase; f.down_clock = sample.clock; f.down_ko = bool(sample.get("ko", false))
						f.hp = 0.0 if f.down_ko else 100.0
						game.sim.round_over = f.down_ko
						game.render_state(0.0)
						if sample.phase == "":
							game.anims[0].advance(0.11) # Finish the standard ready-stance crossfade.
						var vertices := posed_world_vertices(game.actors[0].get_child(0))
						vertices_seen += vertices.size()
						var minimum := Vector2(INF, INF)
						var maximum := Vector2(-INF, -INF)
						for point in vertices:
							var screen: Vector2 = game.camera.unproject_position(point)
							minimum = minimum.min(screen); maximum = maximum.max(screen)
						var safe: bool = minimum.x >= -0.5 and maximum.x <= dims.x + 0.5 and minimum.y >= top - 0.5 and maximum.y <= limit + 0.5
						var margin := minf(minf(minimum.x, dims.x - maximum.x), minf(minimum.y - top, limit - maximum.y))
						minimum_camera_margin = minf(minimum_camera_margin, margin)
						if not safe and camera_failure_details.size() < 24:
							camera_failure_details.append("%s kind %d face %d x %.1f %s@%.2f min %s max %s gameplay y %.1f..%.1f" % [str(dims), kind, face, edge, sample.phase, sample.clock, str(minimum), str(maximum), top, limit])
						contained = contained and safe
						fixed_camera = fixed_camera and game.actors[0].position.is_equal_approx(Vector3(f.x, f.y, 0.0)) and game.camera.global_transform == camera_initial and is_equal_approx(game.camera.size, camera_size_initial) and is_equal_approx(game.camera.v_offset, camera_offset_initial)
						sample_count += 1
			check(sample_count == samples.size() * 4 and vertices_seen > 10000 and contained, "%s kind %d actual skinned vertices fit gameplay bounds across both faces/walls and all down/rise poses" % [str(dims), kind])
			check(fixed_camera, "%s kind %d camera and physical-root mapping stay fixed through all pose phases" % [str(dims), kind])
	for detail in camera_failure_details: printerr("CAMERA DETAIL: ", detail)
	print("Minimum actual-pose camera margin: ", minimum_camera_margin, " px")

func run_tests() -> void:
	simulation_tests()
	if "--simulation-only" not in OS.get_cmdline_user_args():
		game = load("res://main.tscn").instantiate()
		root.add_child(game); game.set_physics_process(false)
		await process_frame
		game.brain = robot
		render_tests()
		independent_strike_distance_tests()
		settle_endpoint_tests()
		settled_support_measurements()
		if "--skip-camera" not in OS.get_cmdline_user_args(): await camera_tests()
		game.queue_free()
		for reference: Dictionary in reference_models.values(): reference.model.queue_free()
		await process_frame
	print("Presentation v3 checks: ", checks, "; failures: ", failures)
	quit(failures)
