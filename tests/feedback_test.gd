extends SceneTree
## Real scene/combat/animation integration. No gameplay resources are modified.
## Run: godot --headless --path . --script tests/feedback_test.gd
## Add -- --require-strong after the revised animation assets are installed.
const Combat = preload("res://scripts/combat.gd")
const AudioAssertions = preload("res://tests/p2_audio_assertions.gd")
const DT := 1.0 / 60.0
class ScriptedAI extends RefCounted:
	var command: Dictionary = {}
	func reset() -> void:
		command.clear()
	func act(_sim, _delta: float) -> Dictionary:
		return command.duplicate()

var game
var robot := ScriptedAI.new()
var failures := 0
var checks := 0
var fallback_samples := 0
var require_strong := false

func _initialize() -> void:
	require_strong = "--require-strong" in OS.get_cmdline_user_args()
	call_deferred("run_tests")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		printerr("FAIL: ", label)

func setup(kind: int = 0, far_apart: bool = false) -> void:
	game.hud._choose(kind)
	game.brain = robot
	robot.reset()
	game.set_physics_process(false)
	game.auto_demo = false
	if game.muted: game.toggle_mute()
	game.sound_enabled = true
	AudioAssertions.reset(game)
	game.sim.fighters[0].x = Combat.LEFT if far_apart else -Combat.BODY
	game.sim.fighters[1].x = Combat.RIGHT if far_apart else Combat.BODY
	game.render_state(0.0)

func tick(first: Dictionary = {}, second: Dictionary = {}, delta: float = DT) -> void:
	game.held.clear()
	game.taps.clear()
	var movement := float(first.get("move", 0.0))
	if movement > 0.0:
		game.held.right = true
	elif movement < 0.0:
		game.held.left = true
	for action in ["jump", "punch", "kick"]:
		if first.get(action, false):
			game.taps[action] = true
	robot.command = second.duplicate()
	game._physics_process(delta)

func event_found(event_type: String, target: int) -> Dictionary:
	for event: Dictionary in game.sim.events:
		if event.type == event_type and int(event.get("fighter", -1)) == target:
			return event
	return {}

func make_contact(kind: int, attacker: int, attack: String, blocked: bool = false, lethal: bool = false) -> Dictionary:
	setup(kind)
	var target := 1 - attacker
	if blocked:
		# v4 jab reach follows extension; a freely retreating opponent can now
		# legitimately leave range before contact. Isolate blocking at the wall.
		var face := 1.0 if target == 1 else -1.0
		game.sim.fighters[target].x = Combat.RIGHT if face > 0.0 else Combat.LEFT
		game.sim.fighters[attacker].x = game.sim.fighters[target].x - face * Combat.BODY * 2.0
	if lethal:
		game.sim.fighters[target].hp = float(game.sim.attack_config(game.sim.fighters[attacker], attack).damage)
	var defender_command: Dictionary = {"move": 1.0 if target == 1 else -1.0} if blocked else {}
	for frame in range(90):
		var commands: Array = [{}, {}]
		commands[target] = defender_command
		if frame == 0:
			commands[attacker] = {attack: true}
		tick(commands[0], commands[1])
		var event := event_found("block" if blocked else "hit", target)
		if not event.is_empty():
			return event
	return {}

func expected_clip(index: int, base: String) -> String:
	var variant := base + ("_R" if game.sim.fighters[index].face > 0 else "_L")
	return variant if game.anims[index].has_animation(variant) else base

func clip_base(index: int) -> String:
	return str(game.current_clips[index]).trim_suffix("_R").trim_suffix("_L")

func stance_tests() -> void:
	for kind in range(2):
		setup(kind)
		for fighter in range(2):
			var label := "selection %d fighter %d" % [kind, fighter]
			check(game.anims[fighter] != null and game.anims[fighter].has_animation("FightIdle"), label + " provides FightIdle asset")
			check(game.current_clips[fighter] == expected_clip(fighter, "FightIdle") and game.anims[fighter].current_animation == expected_clip(fighter, "FightIdle"), label + " neutral playing uses FightIdle")
			if require_strong:
				check(game.anims[fighter].has_animation("HitReactStrong"), label + " provides final HitReactStrong asset")
		game.show_menu()
		game.render_state(0.0)
		check(game.current_clips == ["Idle", "Idle"], "selection %d menu preserves original Idle" % kind)

func contact_tests() -> void:
	for kind in range(2):
		for attacker in range(2):
			for attack in ["punch", "kick"]:
				var target := 1 - attacker
				var label := "selection %d attacker %d %s" % [kind, attacker, attack]
				var event := make_contact(kind, attacker, attack)
				check(not event.is_empty() and event.get("kind", "") == attack, label + " real contact emits typed hit event")
				if event.is_empty(): continue
				var fighter: Dictionary = game.sim.fighters[target]
				var reaction_base := "Knockdown" if attack == "kick" else ("HitReactStrong" if game.anims[target].has_animation("HitReactStrong") else "HitReact")
				var desired_clip := expected_clip(target, reaction_base)
				if reaction_base == "HitReact": fallback_samples += 1
				check(game.current_clips[target] == desired_clip and game.anims[target].current_animation == desired_clip, label + " hit visibly selects " + desired_clip)
				check(game.anims[target].current_animation_position >= 0.039, label + " reaction begins at visible recoil/loss pose without blend delay")
				var expected_stun := 0.24 if attack == "punch" else 0.32
				var expected_stop := 0.055 if attack == "punch" else 0.075
				if attack == "punch":
					check(not fighter.down and is_equal_approx(fighter.stun, expected_stun) and is_equal_approx(fighter.stun_duration, expected_stun) and fighter.hit_age == 0.0 and fighter.hit_kind == attack, label + " preserves original short stun and reaction clock")
				else:
					check(fighter.down and fighter.down_phase == "fall" and fighter.down_clock == 0.0 and fighter.stun == 0.0 and fighter.hit_age == 0.0 and fighter.hit_kind == attack, label + " replaces short kick hurt with approved down sequence")
				check(is_equal_approx(game.hitstop, expected_stop) and game.hitstop > 0.025, label + " has stronger hitstop than block")
				check(game.effects.size() == 1 and game.last_feedback == "hit:" + attack and AudioAssertions.contact_matches(game, event), label + " creates one hit effect and sound")
				var time_before: float = game.sim.time_left
				var stun_before: float = fighter.stun
				var down_clock_before: float = fighter.down_clock
				tick()
				check(game.sim.time_left == time_before and fighter.stun == stun_before and fighter.down_clock == down_clock_before and game.anims[target].speed_scale == 0.0, label + " hitstop freezes simulation/reaction clocks")
				var kept_reaction := true
				var reaction_samples := 0
				var sim_elapsed_before: float = game.sim.elapsed
				for frame in range(190 if attack == "kick" else 60):
					var commands: Array = [{}, {}]
					commands[target] = {"move": -1.0 if target == 0 else 1.0}
					tick(commands[0], commands[1])
					if fighter.down or fighter.stun > 0.0:
						reaction_samples += 1
						var phase_base := "Recover" if fighter.down and fighter.down_phase == "rise" else reaction_base
						kept_reaction = kept_reaction and game.current_clips[target] == expected_clip(target, phase_base) and fighter.attack == ""
					else: break
				check(reaction_samples >= (120 if attack == "kick" else 10) and kept_reaction, label + " movement never overrides hurt/down/rise with Run/Idle")
				var expected_duration := 2.05 if attack == "kick" else expected_stun
				check(not fighter.down and fighter.stun == 0.0 and float(game.sim.elapsed) - sim_elapsed_before <= expected_duration + DT * 1.1, label + " presentation adds no recovery beyond approved phase timing")
				check(clip_base(target) not in ["HitReact", "HitReactStrong", "Knockdown", "Recover"], label + " exits reaction immediately when simulation recovery ends")
				var blocked_event := make_contact(kind, attacker, attack, true)
				check(not blocked_event.is_empty() and blocked_event.get("kind", "") == attack and is_equal_approx(game.hitstop, 0.025), label + " frontal block keeps short 25 ms feedback")
				if not blocked_event.is_empty():
					check(game.sim.fighters[target].hp == 100.0 and game.sim.fighters[target].stun == 0.0 and not game.sim.fighters[target].down and clip_base(target) not in ["HitReact", "HitReactStrong", "Knockdown", "Recover"], label + " block does not fake damaging recoil/down")

func miss_tests() -> void:
	for kind in range(2):
		for attacker in range(2):
			for attack in ["punch", "kick"]:
				setup(kind, true)
				var saw_attack := false
				var clean := true
				for frame in range(90):
					var commands: Array = [{}, {}]
					if frame == 0:
						commands[attacker] = {attack: true}
					tick(commands[0], commands[1])
					saw_attack = saw_attack or game.sim.fighters[attacker].attack == attack
					clean = clean and game.hitstop <= 0.0 and game.effects.is_empty() and game.last_feedback == "" and AudioAssertions.no_contact_audio(game)
					if frame > 1 and game.sim.fighters[attacker].attack == "":
						break
				check(saw_attack and clean and game.sim.fighters[0].hp == 100.0 and game.sim.fighters[1].hp == 100.0, "selection %d attacker %d %s miss has no hitstop/effect/contact sound" % [kind, attacker, attack])

func effect_snapshot() -> Array:
	var result: Array = []
	for effect: Dictionary in game.effects:
		result.append([effect.life, effect.duration, effect.node.transform])
	return result

func freeze_and_reset_tests() -> void:
	for notification in [0, Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		var event := make_contact(0, 0, "kick")
		check(not event.is_empty(), "freeze fixture contains real kick feedback")
		game.on_command("right", true)
		game.on_command("punch", true)
		if notification != 0:
			game._notification(notification)
		else:
			game.toggle_pause()
		var label := "pause" if notification == 0 else ("background focus-loss" if notification == Node.NOTIFICATION_APPLICATION_FOCUS_OUT else "background app-suspend")
		var fighters_before: Array = game.sim.fighters.duplicate(true)
		var time_before: float = game.sim.time_left
		var stop_before: float = game.hitstop
		var fx_before := effect_snapshot()
		game._physics_process(0.5)
		check(game.paused and game.held.is_empty() and game.taps.is_empty(), label + " clears held/tapped inputs")
		check(game.sim.fighters == fighters_before and game.sim.time_left == time_before and game.hitstop == stop_before, label + " freezes combat, timer and hitstop")
		check(effect_snapshot() == fx_before and game.anims[0].speed_scale == 0.0 and game.anims[1].speed_scale == 0.0, label + " freezes effect lifetime and animations")
		game.wins = [1, 1]
		game.round_delay = 1.0
		game.hud._request_rematch()
		game.render_state(0.0)
		var fresh := true
		for fighter: Dictionary in game.sim.fighters:
			fresh = fresh and fighter.hp == 100.0 and fighter.guard == 100.0 and fighter.stun == 0.0 and fighter.attack == "" and fighter.hit_age == 0.0 and fighter.stun_duration == 0.0 and fighter.hit_kind == ""
		check(fresh and game.playing and not game.paused and game.wins == [0, 0] and game.round_delay == 0.0 and game.sim.time_left == 60.0, label + " rematch restores complete combat/score state")
		check(game.hitstop == 0.0 and game.effects.is_empty() and game.last_feedback == "" and game.held.is_empty() and game.taps.is_empty(), label + " rematch clears feedback and stale inputs")
		check(game.current_clips == [expected_clip(0, "FightIdle"), expected_clip(1, "FightIdle")], label + " rematch returns to combat-ready stance")

func ending_and_trade_tests() -> void:
	for kind in range(2):
		for attacker in range(2):
			var target := 1 - attacker
			var event := make_contact(kind, attacker, "punch", false, true)
			check(not event.is_empty() and game.sim.round_over and game.sim.winner == attacker, "selection %d attacker %d lethal hit closes round" % [kind, attacker])
			for settle_frame in range(90):
				if game.sim.fighters[attacker].y == 0.0 and game.sim.fighters[attacker].land_lock == 0.0: break
				tick()
			check(game.current_clips[attacker] == expected_clip(attacker, "Victory") and game.current_clips[target] == expected_clip(target, "Knockdown"), "selection %d attacker %d round end prioritizes Victory/Knockdown over recoil" % [kind, attacker])
	setup(0)
	var trade_events: Array = []
	for frame in range(30):
		tick({"punch": true} if frame == 0 else {}, {"punch": true} if frame == 0 else {})
		for event: Dictionary in game.sim.events:
			if event.type == "hit":
				trade_events.append(event.duplicate())
		if not trade_events.is_empty():
			break
	check(trade_events.size() == 2 and trade_events.all(func(event: Dictionary): return event.get("kind", "") == "punch"), "simultaneous trade preserves both captured attack kinds")
	check(game.sim.fighters[0].hit_kind == "punch" and game.sim.fighters[1].hit_kind == "punch" and game.effects.size() == 2, "both trade victims receive correctly typed feedback")

func mixed_trade_tests() -> void:
	for kicker in range(2):
		setup(0)
		var trade_events: Array = []
		for frame in range(50):
			var commands: Array = [{}, {}]
			if frame == 0:
				commands[kicker] = {"kick": true}
			if frame == 13:
				commands[1 - kicker] = {"punch": true}
			tick(commands[0], commands[1])
			for event: Dictionary in game.sim.events:
				if event.type == "hit":
					trade_events.append(event.duplicate())
			if not trade_events.is_empty():
				break
		var kinds: Array = trade_events.map(func(event: Dictionary): return event.get("kind", ""))
		check(trade_events.size() == 2 and "kick" in kinds and "punch" in kinds, "mixed trade kicker %d keeps both attack types" % kicker)
		check(is_equal_approx(game.hitstop, 0.075), "mixed trade kicker %d keeps stronger kick hitstop regardless of contact order" % kicker)

func run_tests() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	game.brain = robot
	stance_tests()
	contact_tests()
	miss_tests()
	freeze_and_reset_tests()
	ending_and_trade_tests()
	mixed_trade_tests()
	print("Feedback checks: ", checks, "; failures: ", failures, "; fallback hit samples: ", fallback_samples)
	game.queue_free()
	await process_frame
	quit(failures)
