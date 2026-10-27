extends SceneTree
## v4 real scene / input / animation / sound / effect contract.
## Runs the actual main loop. Ordinary inputs enter through on_command with
## explicit fresh press/release edges, never by assigning taps or attack clocks.
## Only documented incoming-contact edge fixtures alter a combat clock.
## godot --headless --path . --script tests/punch_feedback_test.gd
## Add -- --require-new to require all six new paired clips on both models.
const Combat = preload("res://scripts/combat.gd")
const AudioAssertions = preload("res://tests/p2_audio_assertions.gd")
const DT := 1.0 / 60.0
const EPS := 0.00001
const CLIPS := {"punch":"Jab", "straight":"Straight", "heavy":"HeavyPunch"}
const STOPS := {"punch":0.055, "straight":0.065, "heavy":0.095}
class ScriptedAI extends RefCounted:
	var command: Dictionary = {}
	func reset() -> void: command.clear()
	func act(_sim, _delta: float) -> Dictionary: return command.duplicate()
var game
var robot := ScriptedAI.new()
var checks := 0
var failures := 0
var require_new := false
var missing_assets: Array[String] = []
var fallback_samples := 0

func _initialize() -> void:
	require_new = "--require-new" in OS.get_cmdline_user_args()
	call_deferred("run_tests")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else: failures += 1; printerr("FAIL: ", label)

func setup(kind: int = 0, face: int = 1, distant: bool = false) -> void:
	game.brain = robot
	game.hud._choose(kind)
	game.set_physics_process(false)
	game.auto_demo = false
	if game.muted: game.toggle_mute()
	game.sound_enabled = true
	AudioAssertions.reset(game)
	game.sim.fighters[1].x = Combat.RIGHT if face > 0 else Combat.LEFT
	game.sim.fighters[0].x = -game.sim.fighters[1].x if distant else game.sim.fighters[1].x - face * Combat.BODY * 2.0
	game.sim.fighters[0].face = face
	game.sim.fighters[1].face = -face
	game.render_state(0.0)

func step(delta: float = DT) -> Array:
	var before: float = game.sim.elapsed
	game._physics_process(delta)
	# Hitstop intentionally retains sim.events. Do not count retained events twice.
	return game.sim.events.duplicate(true) if game.sim.elapsed != before else []

func press(action: String) -> void: game.on_command(action, true)
func release(action: String) -> void: game.on_command(action, false)
func pulse(action: String) -> Array:
	press(action)
	var events := step()
	release(action)
	return events

func expected_clip(index: int, base: String) -> String:
	var name := base + ("_R" if game.sim.fighters[index].face > 0 else "_L")
	return name if game.anims[index].has_animation(name) else base

func attack_clip(index: int, attack: String) -> String:
	var name: String = CLIPS[attack] + ("_R" if game.sim.fighters[index].face > 0 else "_L")
	return name if game.anims[index].has_animation(name) else expected_clip(index, "Punch")

func animation_matches(index: int, attack: String) -> bool:
	var f: Dictionary = game.sim.fighters[index]
	var clip := attack_clip(index, attack)
	var length: float = game.anims[index].get_animation(clip).length
	# Reusing the temporary Punch clip can stop playback at its old end while
	# manual seek still presents the assigned pose. Only legacy fallback allows
	# that state; --require-new independently rejects every missing paired clip.
	var selected: bool = game.anims[index].current_animation == clip or (clip.begins_with("Punch") and game.anims[index].current_animation == "" and game.anims[index].assigned_animation == clip)
	var ok: bool = game.current_clips[index] == clip and selected and absf(game.anims[index].current_animation_position - f.clock / f.duration * length) < EPS and game.anims[index].speed_scale == 0.0
	return ok

func reach_buffer_window() -> bool:
	var f: Dictionary = game.sim.fighters[0]
	for frame in range(100):
		if f.attack != "punch": return false
		if game.hitstop <= 0.0 and f.clock + DT >= f.duration - Combat.PUNCH_BUFFER_WINDOW + EPS: return true
		step()
	return false

func start_move(move: String) -> bool:
	pulse("heavy" if move == "heavy" else "punch")
	if move == "straight":
		if not reach_buffer_window(): return false
		pulse("punch")
		if game.sim.fighters[0].queued != "straight": return false
		for frame in range(30):
			step()
			if game.sim.fighters[0].attack == "straight": break
	return game.sim.fighters[0].attack == move

func finish_move(limit: int = 180) -> void:
	for frame in range(limit):
		if game.sim.fighters[0].attack == "" and game.hitstop <= 0.0: return
		step()

func effect_matches(move: String, blocked: bool) -> bool:
	if game.effects.size() != 1: return false
	var fx: Dictionary = game.effects[0]
	var node: Node3D = fx.node
	var strong := move == "heavy"
	var radius := 0.085 if blocked else (0.16 if strong else 0.12)
	if node.get_child_count() != (4 if blocked else 6): return false
	if not is_equal_approx(fx.duration, 0.11 if blocked else 0.16): return false
	if absf(node.position.z - 0.36) > EPS: return false
	var target: Dictionary = game.sim.fighters[1]
	if absf(absf(node.position.x - target.x) - 0.27) > EPS: return false
	if absf(node.position.y - target.y - 1.30) > EPS: return false
	for ray: MeshInstance3D in node.get_children():
		if absf(ray.position.length() - radius) > EPS: return false
		if ray.material_override.albedo_color != Color("8bd6ff" if blocked else "ffe5a4"): return false
	return true

func asset_tests() -> void:
	setup()
	for index in range(2):
		for base in CLIPS.values():
			for side in ["_R", "_L"]:
				var clip: String = base + side
				var exists: bool = game.anims[index].has_animation(clip)
				var label := "model %d paired asset %s" % [game.sim.fighters[index].kind, clip]
				if not exists: missing_assets.append(label)
				if require_new: check(exists, label)
				elif not exists: print("PROVISIONAL MISSING: ", label)

func phase_feedback_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for move in ["punch", "straight", "heavy"]:
				for outcome in (["hit", "block", "break", "miss"] if move == "heavy" else ["hit", "block", "miss"]):
					setup(kind, face, outcome == "miss")
					if outcome in ["block", "break"]: robot.command = {"move":float(face)}
					if outcome == "break": game.sim.fighters[1].guard = 10.0; game.sim.fighters[1].guard_delay = 10.0
					var label := "kind %d face %d %s %s" % [kind, face, move, outcome]
					check(start_move(move), label + " starts through fresh real-scene input")
					var f: Dictionary = game.sim.fighters[0]
					if f.attack != move: continue
					var target: Dictionary = game.sim.fighters[1]
					var cfg: Dictionary = game.sim.attack_config(f, move)
					var hp_before: float = target.hp
					var total: float = cfg.startup + cfg.active + cfg.recovery
					var begun: float = game.sim.elapsed
					var pose_ok := animation_matches(0, move)
					var stationary := true
					var premature := false
					var contacts := 0
					var feedback_ok := true
					var freeze_ok := true
					AudioAssertions.clear_observation(game)
					if attack_clip(0, move).begins_with("Punch"): fallback_samples += 1
					for frame in range(130):
						var events := step()
						if f.attack == move:
							pose_ok = animation_matches(0, move) and pose_ok
							stationary = stationary and f.vx == 0.0 and game.actors[0].position == Vector3(f.x, f.y, 0.0)
							if f.clock < cfg.startup: premature = premature or target.hp != hp_before
						for event: Dictionary in events:
							if event.type not in ["hit", "block", "break"]: continue
							contacts += 1
							feedback_ok = feedback_ok and event.type == outcome and event.get("kind", "") == move and event.fighter == 1 and f.clock >= cfg.startup and f.clock < cfg.startup + cfg.active
							feedback_ok = feedback_ok and is_equal_approx(game.hitstop, 0.025 if outcome == "block" else STOPS[move]) and game.last_feedback == outcome + ":" + move
							feedback_ok = feedback_ok and AudioAssertions.contact_matches(game, event) and effect_matches(move, outcome == "block")
							if outcome in ["hit", "break"]:
								feedback_ok = feedback_ok and not target.down and is_equal_approx(target.stun, cfg.stun + (0.17 if outcome == "break" else 0.0)) and target.hit_kind == move and game.current_clips[1] == expected_clip(1, "HitReactStrong") and game.anims[1].current_animation_position >= 0.039
							else: feedback_ok = feedback_ok and target.stun == 0.0 and not target.down
							var frozen: Array = [game.sim.elapsed, game.sim.time_left, f.clock, target.stun, game.anims[0].current_animation_position, game.anims[1].current_animation_position]
							step()
							freeze_ok = freeze_ok and frozen == [game.sim.elapsed, game.sim.time_left, f.clock, target.stun, game.anims[0].current_animation_position, game.anims[1].current_animation_position]
						if outcome == "miss": feedback_ok = feedback_ok and game.effects.is_empty() and game.hitstop <= 0.0 and game.last_feedback == "" and AudioAssertions.no_contact_audio(game)
						if f.attack == "": break
					check(pose_ok and stationary, label + " committed root and paired/fallback pose follow simulation clock")
					check(not premature and contacts == (0 if outcome == "miss" else 1) and feedback_ok, label + " exactly one active contact or miss with no contact audio, typed recoil/WAV cue/local spark")
					check(freeze_ok, label + " hitstop freezes combat and both animation clocks")
					check(target.hp == hp_before - (cfg.damage if outcome in ["hit", "break"] else 0.0) and not target.down, label + " exact damage and ordinary nonlethal recoil")
					check(f.attack == "" and game.sim.elapsed - begun >= total - EPS and game.sim.elapsed - begun <= total + DT + EPS, label + " full startup/active/recovery without shortened handoff")
					if move == "straight": check(f.land_lock >= 0.19 - EPS and f.chain == 0, label + " second hit retains extra chain recovery")

func expired_contact_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for move in ["punch", "straight", "heavy"]:
				setup(kind, face, true)
				start_move(move)
				var f: Dictionary = game.sim.fighters[0]
				var cfg: Dictionary = game.sim.attack_config(f, move)
				for frame in range(90):
					if f.clock > cfg.startup + cfg.active: break
					step()
				# Opponent placement fixture, with no attack clock changes: entering
				# the real recovering punch's range must not produce a late contact.
				game.sim.fighters[1].x = f.x + face * Combat.BODY * 2.0
				finish_move()
				check(game.sim.fighters[1].hp == 100.0 and game.hitstop <= 0.0 and game.effects.is_empty() and AudioAssertions.no_contact_audio(game) and game.last_feedback == "", "kind %d face %d %s recovery has no lingering hitbox/feedback" % [kind, face, move])

func queued_lifecycle_tests() -> void:
	for kind in range(2):
		for destination in ["menu", "rematch", "timeout"]:
			setup(kind, 1, true)
			pulse("punch"); reach_buffer_window(); pulse("punch")
			check(game.sim.fighters[0].queued == "straight", "kind %d %s starts with a real pending straight" % [kind, destination])
			if destination == "menu": game.show_menu()
			elif destination == "rematch": game.hud._request_rematch()
			else:
				game.sim.time_left = DT * 0.5
				step()
			check(game.sim.fighters[0].queued == "" and game.sim.fighters[0].queued_attack_id == 0 and game.held.is_empty() and game.taps.is_empty(), "kind %d %s cancels live pending straight and upstream inputs" % [kind, destination])
			if destination == "timeout":
				check(game.sim.round_over and game.sim.winner == -1 and game.wins == [0, 0], "kind %d queued timeout remains a scoreless draw" % kind)
				for frame in range(160): step()
			elif destination == "menu": game.hud._choose(kind)
			for frame in range(30): step()
			check(game.sim.attack_serial == 0 and game.sim.fighters[0].attack == "", "kind %d %s cannot replay the stale straight after reset" % [kind, destination])
			pulse("heavy")
			check(game.sim.fighters[0].attack == "heavy" and game.sim.attack_serial == 1, "kind %d %s accepts first fresh heavy after reset" % [kind, destination])

func heavy_feedback_pause_tests() -> void:
	for notification in [0, Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		setup()
		start_move("heavy")
		for frame in range(70):
			step()
			if game.last_feedback == "hit:heavy": break
		check(game.effects.size() == 1 and game.hitstop > 0.0, "heavy feedback pause fixture has live heavy spark and hitstop")
		if notification == 0: game.toggle_pause()
		else: game._notification(notification)
		var before: Array = [game.effects[0].life, game.effects[0].node.transform, game.hitstop, game.sim.time_left, game.sim.fighters.duplicate(true)]
		step(0.5)
		check(before == [game.effects[0].life, game.effects[0].node.transform, game.hitstop, game.sim.time_left, game.sim.fighters] and game.anims[0].speed_scale == 0.0 and game.anims[1].speed_scale == 0.0, "notification %d freezes heavy spark, hitstop, both poses, combat and timer" % notification)

func input_chain_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			setup(kind, face, true)
			press("punch"); step()
			check(game.sim.fighters[0].attack == "punch" and game.sim.fighters[0].clock == 0.0, label + " first press starts jab immediately")
			for frame in range(120): step()
			check(game.sim.attack_serial == 1 and game.sim.fighters[0].attack == "", label + " held scene button never repeats or queues")
			release("punch")
			setup(kind, face, true)
			pulse("punch"); step(); pulse("punch")
			for frame in range(100): step()
			check(game.sim.attack_serial == 1 and game.sim.fighters[0].queued == "", label + " early fresh second press is discarded")
			setup(kind, face, true)
			pulse("punch"); reach_buffer_window()
			var f: Dictionary = game.sim.fighters[0]
			var original_id: int = f.attack_id
			pulse("punch")
			check(f.queued == "straight" and f.queued_attack_id == original_id and f.attack == "punch", label + " fresh late scene input buffers only current jab")
			for frame in range(40):
				step()
				if f.attack == "straight": break
			check(f.attack == "straight" and f.clock == 0.0 and f.chain == 2 and f.queued == "" and animation_matches(0, "straight"), label + " distinct straight starts at zero pose only after full jab recovery")
			var snap: Array = [f.clock, game.anims[0].current_animation_position]
			game.render_state(0.003); game.render_state(0.041)
			check(snap == [f.clock, game.anims[0].current_animation_position], label + " variable render delta cannot advance attack pose")
			step(); pulse("punch")
			finish_move()
			check(game.sim.attack_serial == 2 and f.land_lock > 0.18 and f.queued == "", label + " fresh third press cannot extend the chain")
			for frame in range(30): step()
			pulse("punch")
			check(game.sim.attack_serial == 3 and f.attack == "punch" and f.chain == 1, label + " next fresh post-recovery input restarts lead jab")

func independent_heavy_and_mute_tests() -> void:
	for kind in range(2):
		setup(kind, 1, true)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_L; event.pressed = true
		game._input(event); step()
		check(game.sim.fighters[0].attack == "heavy" and game.held.get("heavy", false) and not game.held.get("punch", false) and not game.held.get("kick", false), "kind %d keyboard L independently starts heavy" % kind)
		event.echo = true
		for frame in range(100): game._input(event); step()
		check(game.sim.attack_serial == 1, "kind %d keyboard repeat/held L never repeats heavy" % kind)
		event.echo = false; event.pressed = false; game._input(event)
		event.pressed = true; game._input(event); step()
		check(game.sim.attack_serial == 2 and game.sim.fighters[0].attack == "heavy", "kind %d fresh L after release is accepted" % kind)
		setup(kind, 1, true)
		pulse("jump"); pulse("heavy")
		check(game.sim.fighters[0].y > 0.0 and game.sim.fighters[0].attack == "" and game.sim.attack_serial == 0, "kind %d scene heavy is ground-only" % kind)
		for frame in range(100): step()
		check(game.sim.attack_serial == 0, "kind %d rejected air heavy is not delayed until landing" % kind)
		for move in ["punch", "straight", "heavy"]:
			setup(kind)
			game.hud.mute_requested.emit()
			check(game.muted, "kind %d %s HUD mute toggles actual audio state" % [kind, move])
			start_move(move)
			var contact := false
			for frame in range(80):
				for e: Dictionary in step():
					if e.type == "hit" and e.get("kind", "") == move: contact = true
				if contact: break
			check(contact and AudioAssertions.silent(game) and game.effects.size() == 1 and game.last_feedback == "hit:" + move, "kind %d muted %s retains visual feedback without audio" % [kind, move])

func pause_and_reset_tests() -> void:
	for notification in [0, Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		var label := "pause" if notification == 0 else ("focus loss" if notification == Node.NOTIFICATION_APPLICATION_FOCUS_OUT else "app suspend")
		setup(0, 1, true)
		pulse("punch"); reach_buffer_window(); pulse("punch")
		check(game.sim.fighters[0].queued == "straight", label + " starts with actual queued follow-up")
		press("right"); press("heavy")
		if notification == 0: game.toggle_pause()
		else: game._notification(notification)
		var snapshot: Array = [game.sim.fighters.duplicate(true), game.sim.time_left, game.hitstop, game.anims[0].current_animation_position]
		step(0.5)
		check(game.paused and game.held.is_empty() and game.taps.is_empty() and game.sim.fighters[0].queued == "" and not game.sim.fighters[0].punch_held and not game.sim.fighters[0].heavy_held, label + " clears upstream input and simulation queue/edges")
		check(snapshot == [game.sim.fighters, game.sim.time_left, game.hitstop, game.anims[0].current_animation_position], label + " freezes combat/timer/animation")
		game.toggle_pause(); finish_move()
		for frame in range(45): step()
		check(game.sim.attack_serial == 1 and game.sim.fighters[0].attack == "", label + " resume never launches stale follow-up")
		# Ready-state first resume frame has no hidden neutral rearm requirement.
		game.toggle_pause(); game.toggle_pause(); pulse("heavy")
		check(game.sim.fighters[0].attack == "heavy" and game.sim.attack_serial == 2, label + " first fresh resume heavy works on the very first frame")
		game.hud._request_rematch(); game.render_state(0.0)
		var clean: bool = game.playing and not game.paused and game.wins == [0, 0] and game.round_delay == 0.0 and game.hitstop == 0.0 and game.effects.is_empty() and game.last_feedback == "" and game.held.is_empty() and game.taps.is_empty()
		for f: Dictionary in game.sim.fighters: clean = clean and f.hp == 100.0 and f.attack == "" and f.queued == "" and f.queued_attack_id == 0 and not f.punch_held and not f.heavy_held and not f.input_rearm
		check(clean, label + " rematch clears every new state and feedback")
		pulse("punch")
		check(game.sim.fighters[0].attack == "punch", label + " rematch first-frame jab is not lost")
		game.show_menu(); game.render_state(0.0)
		check(not game.playing and game.current_clips == ["Idle", "Idle"] and game.sim.attack_serial == 0 and game.held.is_empty() and game.taps.is_empty(), label + " menu resets queued attack and restores original idle")
		game.hud._choose(1); pulse("heavy")
		check(game.selected == 1 and game.sim.fighters[0].attack == "heavy" and game.sim.attack_serial == 1, label + " switched character accepts first fresh heavy")

func interrupted_queue_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for incoming in ["punch", "kick"]:
				setup(kind, face, true)
				pulse("punch"); reach_buffer_window(); pulse("punch")
				var f: Dictionary = game.sim.fighters[0]
				var opponent: Dictionary = game.sim.fighters[1]
				# Explicit incoming-contact edge fixture: the player's pending queue
				# was made with real input; only the opposing contact is phase-aligned.
				opponent.x = f.x + face * Combat.BODY * 2.0
				game.sim.begin_attack(opponent, incoming)
				var incoming_config: Dictionary = game.sim.attack_config(opponent, incoming)
				opponent.clock = incoming_config.startup + (incoming_config.active * 0.5 if incoming == "punch" else 0.0) - DT + EPS
				step()
				var label := "kind %d face %d incoming %s" % [kind, face, incoming]
				check(f.queued == "" and f.queued_attack_id == 0 and f.attack == "" and f.down == (incoming == "kick"), label + " real main loop cancels queue on hurt/down")
				for frame in range(210): step()
				check(game.sim.attack_serial == 2 and f.attack == "" and not f.down, label + " complete recovery never fires stale straight")

func knockout_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for move in ["straight", "heavy"]:
				setup(kind, face)
				# Health/score fixture makes a legal, input-driven final-round KO.
				game.sim.fighters[1].hp = 18.0 if move == "straight" else 16.0
				game.wins = [1, 0]
				start_move(move)
				for frame in range(90):
					step()
					if game.sim.round_over: break
				var label := "kind %d face %d lethal %s" % [kind, face, move]
				check(game.sim.round_over and game.sim.winner == 0 and game.wins == [2, 0] and game.sim.fighters[1].down_ko and game.sim.fighters[0].queued == "" and game.held.is_empty() and game.taps.is_empty(), label + " awards exactly one final round and cancels input")
				for frame in range(160): step()
				check(not game.playing and game.sim.fighters[1].down_phase == "hold" and game.current_clips[1] == expected_clip(1, "Knockdown") and game.current_clips[0] == expected_clip(0, "Victory"), label + " result keeps loser down and winner victory")
				game.hud._request_rematch(); pulse("heavy")
				check(game.playing and game.wins == [0, 0] and game.sim.fighters[1].hp == 100.0 and game.sim.fighters[0].attack == "heavy" and game.sim.attack_serial == 1, label + " result rematch is clean and first input immediate")

func run_tests() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game); game.set_physics_process(false)
	await process_frame
	asset_tests()
	phase_feedback_tests()
	expired_contact_tests()
	input_chain_tests()
	independent_heavy_and_mute_tests()
	pause_and_reset_tests()
	queued_lifecycle_tests()
	heavy_feedback_pause_tests()
	interrupted_queue_tests()
	knockout_tests()
	print("Punch feedback checks: ", checks, "; failures: ", failures, "; missing paired assets: ", missing_assets.size(), "; provisional fallback attack samples: ", fallback_samples, "; strict assets: ", require_new)
	game.queue_free(); await process_frame
	quit(mini(failures, 255))
