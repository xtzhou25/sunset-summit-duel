extends SceneTree
## v5 real main-loop ground-roundhouse integration, not renderer-driven damage.
## All ordinary player actions use on_command fresh press/release edges.
## Position/health/guard fixtures are labelled; no attack clock is injected.
## godot --headless --path . --script tests/roundhouse_feedback_test.gd
## Add -- --require-new for the strict paired RoundhouseKick asset gate.
## Missing clips are reported, never counted as verified roundhouse animation.
const Combat = preload("res://scripts/combat.gd")
const AudioAssertions = preload("res://tests/p2_audio_assertions.gd")
const Brain = preload("res://scripts/ai.gd")
const DT := 1.0 / 60.0
const EPS := 0.00001
const ACTION := "roundhouse"
const BASE := "RoundhouseKick"
class ScriptedAI extends RefCounted:
	var command: Dictionary = {}
	func reset() -> void: command.clear()
	func act(_sim, _delta: float) -> Dictionary: return command.duplicate()
class PublicWorld extends RefCounted:
	# No player inputs, private buffers, or presentation state are available.
	var fighters: Array = [
		{"x":0.0, "y":0.0, "attack":""},
		{"x":0.80, "y":0.0, "face":-1, "attack":"", "attack_id":0, "duration":0.0, "clock":0.0, "guard":100.0}
	]
var game
var robot := ScriptedAI.new()
var checks := 0
var failures := 0
var require_new := false
var missing_assets: Array[String] = []
var verified_pose_samples := 0
var provisional_fallback_samples := 0
var contact_times: Array = []

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
	# Wall-constrained defense avoids a retreating target legitimately leaving
	# range before the measured foot's first contact. Miss fixture uses far walls.
	game.sim.fighters[1].x = Combat.RIGHT if face > 0 else Combat.LEFT
	game.sim.fighters[0].x = -game.sim.fighters[1].x if distant else game.sim.fighters[1].x - face * Combat.BODY * 2.0
	game.sim.fighters[0].face = face
	game.sim.fighters[1].face = -face
	game.render_state(0.0)

func step(delta: float = DT) -> Array:
	var before: float = game.sim.elapsed
	game._physics_process(delta)
	# Hitstop retains the previous event list. Count only freshly stepped events.
	return game.sim.events.duplicate(true) if game.sim.elapsed != before else []

func press(action: String = ACTION) -> void: game.on_command(action, true)
func release(action: String = ACTION) -> void: game.on_command(action, false)
func pulse(action: String = ACTION) -> Array:
	press(action)
	var events := step()
	release(action)
	return events

func settle(frames: int) -> void:
	for frame in range(frames): step()

func finish_move(limit: int = 180) -> void:
	for frame in range(limit):
		if game.sim.fighters[0].attack == "" and game.hitstop <= 0.0: return
		step()

func expected_clip(index: int, base: String) -> String:
	var clip := base + ("_R" if game.sim.fighters[index].face > 0 else "_L")
	return clip if game.anims[index].has_animation(clip) else base

func paired_clip(index: int) -> String:
	return BASE + ("_R" if game.sim.fighters[index].face > 0 else "_L")

func animation_matches(index: int) -> bool:
	var clip := paired_clip(index)
	if not game.anims[index].has_animation(clip):
		provisional_fallback_samples += 1
		# Diagnostic FightIdle fallback is intentional but is not animation proof.
		return game.current_clips[index] == expected_clip(index, "FightIdle")
	verified_pose_samples += 1
	var f: Dictionary = game.sim.fighters[index]
	var length: float = game.anims[index].get_animation(clip).length
	return game.current_clips[index] == clip and game.anims[index].current_animation == clip and absf(game.anims[index].current_animation_position - f.clock / f.duration * length) < EPS and game.anims[index].speed_scale == 0.0

func effect_matches(blocked: bool, target_index: int, event: Dictionary) -> bool:
	if game.effects.size() != 1: return false
	var fx: Dictionary = game.effects[0]
	var node: Node3D = fx.node
	var radius := 0.085 if blocked else 0.16
	if node.get_child_count() != (4 if blocked else 6): return false
	if not is_equal_approx(fx.duration, 0.11 if blocked else 0.16): return false
	var target: Dictionary = game.sim.fighters[target_index]
	var impact_y: float = float(event.get("impact_y", NAN))
	if not is_finite(impact_y) or event.get("kind", "") != ACTION or event.get("fighter", -1) != target_index: return false
	var source: Dictionary = game.sim.fighters[1 - target_index]
	var geometry: Dictionary = game.sim.contact_geometry(source, ACTION)
	var expected_y: float = source.y + (geometry.low + geometry.high) * 0.5
	if absf(impact_y - expected_y) > EPS: return false
	if absf(node.position.z - 0.36) > EPS or absf(absf(node.position.x - target.x) - 0.27) > EPS or absf(node.position.y - impact_y) > EPS: return false
	for ray: MeshInstance3D in node.get_children():
		if absf(ray.position.length() - radius) > EPS: return false
		if ray.material_override.albedo_color != Color("8bd6ff" if blocked else "ffe5a4"): return false
	return true

func wait_contact(kind: String = ACTION, outcome: String = "hit", limit: int = 100) -> Dictionary:
	for frame in range(limit):
		for event: Dictionary in step():
			if event.type == outcome and event.get("kind", "") == kind: return event
	return {}

func asset_tests() -> void:
	setup()
	for index in range(2):
		var model_complete := true
		for side in ["_R", "_L"]:
			var clip: String = BASE + side
			var exists: bool = game.anims[index].has_animation(clip)
			var label := "model %d paired asset %s" % [game.sim.fighters[index].kind, clip]
			if not exists:
				missing_assets.append(label)
				model_complete = false
			if require_new: check(exists, label)
			elif not exists: print("PROVISIONAL MISSING: ", label)
			if exists:
				var animation: Animation = game.anims[index].get_animation(clip)
				check(absf(animation.length - (0.90 if game.sim.fighters[index].kind == 0 else 0.96)) < EPS and animation.loop_mode == Animation.LOOP_NONE, label + " has exact authored duration and does not loop")
		if model_complete:
			check(game.anims[index].get_animation_list().size() == (67 if game.sim.fighters[index].kind == 0 else 71), "model %d preserves 59 baseline clips plus its signature casts and crouch cycle" % game.sim.fighters[index].kind)
		else: print("PROVISIONAL ASSET COUNT model=", game.sim.fighters[index].kind, " count=", game.anims[index].get_animation_list().size(), "; final 59-clip asset validation remains blocked")

func phase_feedback_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for outcome in ["hit", "block", "break", "miss"]:
				setup(kind, face, outcome == "miss")
				if outcome in ["block", "break"]: robot.command = {"move":float(face)}
				if outcome == "break": game.sim.fighters[1].guard = 10.0; game.sim.fighters[1].guard_delay = 10.0
				var label := "kind %d face %d roundhouse %s" % [kind, face, outcome]
				pulse()
				var f: Dictionary = game.sim.fighters[0]
				var target: Dictionary = game.sim.fighters[1]
				var cfg: Dictionary = game.sim.attack_config(f, ACTION)
				check(f.attack == ACTION and f.clock == 0.0 and game.sim.attack_serial == 1, label + " fresh real input starts immediately at simulation zero")
				if f.attack != ACTION: continue
				check(is_equal_approx(cfg.startup, 0.28) and is_equal_approx(cfg.active, 0.14) and is_equal_approx(cfg.recovery, 0.48 if kind == 0 else 0.54) and is_equal_approx(f.duration, 0.90 if kind == 0 else 0.96) and is_equal_approx(Combat.ROUNDHOUSE_PEAK, 0.35), label + " exact .28/.14/.48-or-.54 timing and .35 authored peak")
				var begun: float = game.sim.elapsed
				var root_x: float = f.x
				var pose_ok := animation_matches(0)
				var stationary := true
				var premature := false
				var contacts := 0
				var feedback_ok := true
				var freeze_ok := true
				var reaction_ok := true
				var reaction_samples := 0
				press("right" if face > 0 else "left")
				for frame in range(130):
					var events := step()
					if f.attack == ACTION:
						pose_ok = animation_matches(0) and pose_ok
						stationary = stationary and f.vx == 0.0 and f.vy == 0.0 and f.y == 0.0 and absf(f.x - root_x) < EPS and game.actors[0].position == Vector3(f.x, 0.0, 0.0)
						if f.clock < cfg.startup: premature = premature or target.hp != 100.0
					for event: Dictionary in events:
						if event.type not in ["hit", "block", "break"]: continue
						contacts += 1
						contact_times.append({"kind":kind, "face":face, "outcome":outcome, "clock":f.clock})
						# Observe the real contact, do not assume startup always reaches.
						feedback_ok = feedback_ok and event.type == outcome and event.get("kind", "") == ACTION and event.fighter == 1 and f.clock >= cfg.startup and f.clock < cfg.startup + cfg.active
						feedback_ok = feedback_ok and is_equal_approx(game.hitstop, 0.025 if outcome == "block" else 0.075) and game.last_feedback == outcome + ":" + ACTION
						feedback_ok = feedback_ok and AudioAssertions.contact_matches(game, event) and effect_matches(outcome == "block", 1, event)
						if outcome in ["hit", "break"]:
							feedback_ok = feedback_ok and not target.down and is_equal_approx(target.stun, cfg.stun + (0.17 if outcome == "break" else 0.0)) and target.hit_kind == ACTION and game.current_clips[1] == expected_clip(1, "HitReactStrong") and game.anims[1].current_animation_position >= 0.039
						else: feedback_ok = feedback_ok and target.stun == 0.0 and not target.down
						var frozen: Array = [game.sim.elapsed, game.sim.time_left, f.clock, target.stun, game.anims[0].current_animation_position, game.anims[1].current_animation_position]
						step()
						freeze_ok = freeze_ok and frozen == [game.sim.elapsed, game.sim.time_left, f.clock, target.stun, game.anims[0].current_animation_position, game.anims[1].current_animation_position]
					if target.stun > 0.0:
						reaction_samples += 1
						reaction_ok = reaction_ok and not target.down and target.attack == "" and game.current_clips[1] == expected_clip(1, "HitReactStrong") and game.anims[1].speed_scale == 0.0
					elif contacts > 0 and outcome in ["hit", "break"]:
						reaction_ok = reaction_ok and game.current_clips[1] != expected_clip(1, "HitReactStrong")
					if outcome == "miss": feedback_ok = feedback_ok and game.effects.is_empty() and game.hitstop <= 0.0 and game.last_feedback == "" and AudioAssertions.no_contact_audio(game)
					if f.attack == "": break
				release("right" if face > 0 else "left")
				check(stationary, label + " movement cannot translate or lift committed physical/presentation root")
				check(pose_ok, label + " available paired pose is clock-seeked; missing pose is diagnostic fallback only")
				check(not premature and contacts == (0 if outcome == "miss" else 1) and feedback_ok, label + " exactly one typed active contact with correct recoil/WAV cue/spark, or miss with no contact audio")
				check(reaction_ok and (reaction_samples >= (20 if outcome == "break" else 12) if outcome in ["hit", "break"] else reaction_samples == 0), label + " ordinary recoil owns presentation until stun expires, then releases immediately")
				check(freeze_ok, label + " hitstop freezes combat, timer, attack and recoil animation clocks")
				check(target.hp == (87.0 if outcome in ["hit", "break"] else 100.0) and not target.down, label + " thirteen damage only on hit/break, no ordinary knockdown")
				check(f.attack == "" and game.sim.elapsed - begun >= f.duration - EPS and game.sim.elapsed - begun <= f.duration + DT + EPS, label + " completes full authored duration without shortening recovery")

func input_and_pose_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			setup(kind, face, true)
			press(); step(); settle(130)
			check(game.sim.attack_serial == 1 and game.sim.fighters[0].attack == "" and game.sim.fighters[0].queued == "", label + " held real-scene roundhouse never repeats or queues")
			release(); pulse()
			check(game.sim.attack_serial == 2 and game.sim.fighters[0].attack == ACTION and game.sim.fighters[0].clock == 0.0, label + " release then fresh roundhouse starts a new action")
			settle(9)
			var before: Array = [game.sim.fighters[0].clock, game.anims[0].current_animation_position]
			game.render_state(0.003); game.render_state(0.041)
			check(before == [game.sim.fighters[0].clock, game.anims[0].current_animation_position] and animation_matches(0), label + " variable render delta does not advance simulation-controlled attack pose")
			setup(kind, face, true)
			pulse()
			for frame in range(100):
				if game.sim.fighters[0].clock >= game.sim.fighters[0].duration - 0.09: break
				step()
			pulse("punch")
			finish_move(); settle(35)
			check(game.sim.attack_serial == 1 and game.sim.fighters[0].queued == "" and game.sim.fighters[0].attack == "", label + " late jab during roundhouse cannot create or extend a jab chain")
			setup(kind, face, true)
			pulse("punch")
			for frame in range(60):
				if game.sim.fighters[0].clock >= game.sim.fighters[0].duration - 0.09: break
				step()
			pulse()
			finish_move(); settle(35)
			check(game.sim.attack_serial == 1 and game.sim.fighters[0].queued == "" and game.sim.fighters[0].attack == "", label + " late roundhouse during jab is consumed, never queued as a follow-up")
			setup(kind, face, true)
			pulse("jump"); press(); step()
			check(game.sim.fighters[0].y > 0.0 and game.sim.fighters[0].attack == "" and game.sim.attack_serial == 0, label + " airborne roundhouse input is rejected")
			settle(110)
			check(game.sim.fighters[0].y == 0.0 and game.sim.fighters[0].attack == "" and game.sim.attack_serial == 0, label + " rejected held airborne input cannot fire later on landing")
			release(); pulse()
			check(game.sim.fighters[0].attack == ACTION and game.sim.attack_serial == 1, label + " first fresh grounded roundhouse works after air rejection")
			setup(kind, face, true)
			var key := InputEventKey.new()
			key.physical_keycode = KEY_I; key.pressed = true
			game._input(key); step()
			check(game.sim.fighters[0].attack == ACTION and game.held.get(ACTION, false) and not game.held.get("kick", false), label + " keyboard I independently starts roundhouse, never flying kick")
			key.echo = true
			for frame in range(120): game._input(key); step()
			check(game.sim.attack_serial == 1, label + " keyboard auto-repeat does not repeat roundhouse")
			key.echo = false; key.pressed = false; game._input(key)
			key.pressed = true; game._input(key); step()
			check(game.sim.attack_serial == 2 and game.sim.fighters[0].attack == ACTION, label + " fresh I after release is immediately accepted")

func geometry_and_protection_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			setup(kind, face, true)
			pulse()
			var f: Dictionary = game.sim.fighters[0]
			var cfg: Dictionary = game.sim.attack_config(f, ACTION)
			for frame in range(80):
				if f.clock > cfg.startup + cfg.active: break
				step()
			# Recovery-entry position fixture, no clock or HP manipulation.
			game.sim.fighters[1].x = f.x + face * Combat.BODY * 2.0
			finish_move()
			check(game.sim.fighters[1].hp == 100.0 and game.effects.is_empty() and AudioAssertions.no_contact_audio(game) and game.last_feedback == "", label + " target entering only during recovery receives no late hit/effect/audio")
			setup(kind, face, true)
			pulse()
			# Cross-up fixture after commitment keeps the opponent behind throughout.
			f = game.sim.fighters[0]
			f.x = 0.0; game.sim.fighters[1].x = -face * 0.80
			var facing_stable := true
			for frame in range(100):
				step()
				if f.attack == "": break
				facing_stable = facing_stable and f.face == face
			check(facing_stable and game.sim.fighters[1].hp == 100.0 and game.last_feedback == "" and f.face == -face, label + " committed frontal attack never becomes a 360-degree hit or retargets behind")
			setup(kind, face)
			# Deliberate full-attack invulnerability fixture isolates contact protection.
			game.sim.fighters[1].invuln = 2.0
			pulse(); finish_move()
			check(game.sim.fighters[1].hp == 100.0 and game.last_feedback == "" and game.effects.is_empty(), label + " invulnerable target cannot take roundhouse damage/feedback")
			setup(kind, face)
			pulse("kick")
			var down_event := wait_contact("kick")
			check(not down_event.is_empty() and game.sim.fighters[1].down, label + " down-protection fixture is created by a real flying-kick contact")
			if down_event.is_empty(): continue
			finish_move()
			game.clear_feedback(); AudioAssertions.clear_observation(game)
			robot.command = {ACTION:true}
			var protected := true
			var saw_rise := false
			var attempts := 0
			for frame in range(190):
				var target: Dictionary = game.sim.fighters[1]
				if not target.down: break
				# Restore contact distance while downed victim naturally drifts.
				game.sim.fighters[0].x = target.x - face * Combat.BODY * 2.0
				if game.sim.fighters[0].attack == "" and game.sim.fighters[0].land_lock <= 0.0:
					pulse(); attempts += 1
				else: step()
				protected = protected and target.hp == 87.0 and game.last_feedback == "" and target.attack == ""
				saw_rise = saw_rise or target.down_phase == "rise"
			check(protected and attempts >= 1 and saw_rise and not game.sim.fighters[1].down and game.sim.fighters[1].input_rearm and is_equal_approx(game.sim.fighters[1].invuln, 0.35), label + " actual roundhouses cannot damage/restart down/rise; held victim input stays disarmed through wakeup")
			finish_move(); settle(35)
			check(game.sim.fighters[1].attack == "", label + " held AI-command roundhouse cannot auto-fire after wakeup protection")
			robot.command = {}; step(); robot.command = {ACTION:true}; step()
			check(game.sim.fighters[1].attack == ACTION and not game.sim.fighters[1].input_rearm, label + " neutral then fresh defender roundhouse works normally after wakeup")

func pause_and_lifecycle_tests() -> void:
	for notification in [0, Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		var label := "pause" if notification == 0 else ("focus loss" if notification == Node.NOTIFICATION_APPLICATION_FOCUS_OUT else "app suspend")
		setup(); pulse()
		var event := wait_contact()
		check(not event.is_empty() and game.effects.size() == 1 and game.hitstop > 0.0, label + " fixture contains live roundhouse feedback")
		if event.is_empty(): continue
		press("right"); press()
		if notification == 0: game.toggle_pause()
		else: game._notification(notification)
		var before: Array = [game.sim.fighters.duplicate(true), game.sim.time_left, game.hitstop, game.effects[0].life, game.effects[0].node.transform, game.anims[0].current_animation_position, game.anims[1].current_animation_position]
		step(0.5)
		check(game.paused and game.held.is_empty() and game.taps.is_empty() and not game.sim.fighters[0].roundhouse_held and game.sim.fighters[0].queued == "", label + " clears roundhouse taps/held/edge and stale queue")
		check(before == [game.sim.fighters, game.sim.time_left, game.hitstop, game.effects[0].life, game.effects[0].node.transform, game.anims[0].current_animation_position, game.anims[1].current_animation_position] and game.anims[0].speed_scale == 0.0 and game.anims[1].speed_scale == 0.0, label + " freezes combat/timer/hitstop/effect and both animation clocks")
		game.toggle_pause(); finish_move(); settle(35)
		check(game.sim.attack_serial == 1 and game.sim.fighters[0].attack == "", label + " resume cannot replay stale roundhouse")
		game.toggle_pause(); game.toggle_pause(); pulse()
		check(game.sim.attack_serial == 2 and game.sim.fighters[0].attack == ACTION and game.sim.fighters[0].clock == 0.0, label + " first fresh ready-resume roundhouse is accepted without neutral delay")
	for kind in range(2):
		for destination in ["menu", "rematch", "timeout"]:
			var label := "kind %d %s" % [kind, destination]
			setup(kind, 1, true); press(); step(); press("punch")
			if destination == "menu": game.show_menu()
			elif destination == "rematch": game.hud._request_rematch()
			else: game.sim.time_left = DT * 0.5; step()
			check(game.held.is_empty() and game.taps.is_empty() and game.sim.fighters[0].queued == "" and not game.sim.fighters[0].roundhouse_held, label + " clears stale roundhouse inputs/edges")
			if destination == "timeout":
				check(game.sim.round_over and game.sim.winner == -1 and game.wins == [0, 0], label + " remains a scoreless timeout draw")
				settle(160)
			elif destination == "menu":
				game.render_state(0.0)
				check(game.current_clips == ["Idle", "Idle"] and not game.playing, label + " restores menu idle, not a stale attack pose")
				game.hud._choose(1 - kind)
			settle(30)
			check(game.sim.attack_serial == 0 and game.sim.fighters[0].attack == "" and game.last_feedback == "" and game.effects.is_empty(), label + " reset never replays stale roundhouse")
			pulse()
			check(game.sim.attack_serial == 1 and game.sim.fighters[0].attack == ACTION, label + " first fresh post-reset roundhouse is immediate")

func mute_and_autoplay_tests() -> void:
	for kind in range(2):
		setup(kind)
		game.hud.mute_requested.emit(); pulse()
		var event := wait_contact()
		check(game.muted and not event.is_empty() and AudioAssertions.silent(game) and effect_matches(false, 1, event) and game.last_feedback == "hit:" + ACTION, "kind %d actual HUD mute suppresses roundhouse sound but preserves hit/effect" % kind)
		setup(kind)
		# An autonomous opponent contact with audio locked models no audio gesture.
		game.sound_enabled = false
		robot.command = {ACTION:true}
		event = wait_contact()
		check(not event.is_empty() and event.fighter == 0 and not game.sound_enabled and AudioAssertions.silent(game) and effect_matches(false, 0, event), "kind %d no-gesture audio lock suppresses AI roundhouse sound while mechanics/effect remain active" % kind)
		setup(kind)
		game.sound_enabled = false
		pulse(); event = wait_contact()
		check(game.sound_enabled and not event.is_empty() and AudioAssertions.contact_matches(game, event), "kind %d explicit real input unlocks typed roundhouse WAV cue" % kind)

func knockout_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d lethal roundhouse" % [kind, face]
			setup(kind, face)
			# Health/score fixture gives a legal final-round KO from normal input.
			game.sim.fighters[1].hp = 13.0; game.wins = [1, 0]
			pulse(); var event := wait_contact()
			check(not event.is_empty() and game.sim.round_over and game.sim.winner == 0 and game.wins == [2, 0] and game.sim.fighters[1].down_ko and game.held.is_empty() and game.taps.is_empty(), label + " awards one round, enters KO down, clears stale inputs")
			settle(170)
			check(not game.playing and game.sim.fighters[1].down_phase == "hold" and game.current_clips[1] == expected_clip(1, "Knockdown") and game.current_clips[0] == expected_clip(0, "Victory"), label + " holds loser down and winner victory at result")
			game.hud._request_rematch(); pulse()
			check(game.playing and not game.paused and game.wins == [0, 0] and game.sim.fighters[1].hp == 100.0 and game.sim.fighters[0].attack == ACTION and game.sim.attack_serial == 1, label + " rematch clears outcome and accepts first input")

func trade_feedback_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			setup(kind, face)
			robot.command = {ACTION:true}
			pulse()
			var contacts: Array = []
			var captured_heights: Array = []
			for frame in range(80):
				var next_heights: Array = []
				for source: Dictionary in game.sim.fighters:
					var geometry: Dictionary = game.sim.contact_geometry(source, ACTION, source.clock + DT)
					next_heights.append(source.y + (geometry.low + geometry.high) * 0.5)
				for event: Dictionary in step():
					if event.type == "hit" and event.get("kind", "") == ACTION: contacts.append(event)
				if not contacts.is_empty(): captured_heights = next_heights; break
			var label := "kind %d face %d simultaneous roundhouse" % [kind, face]
			check(contacts.size() == 2 and game.effects.size() == 2 and game.sim.fighters[0].hp == 87.0 and game.sim.fighters[1].hp == 87.0 and not game.sim.fighters[0].down and not game.sim.fighters[1].down, label + " fair real-command trade applies both typed nonlethal contacts")
			var heights_preserved: bool = contacts.size() == 2 and game.effects.size() == 2
			for index in range(mini(contacts.size(), game.effects.size())):
				var event: Dictionary = contacts[index]
				var source_index: int = 1 - int(event.fighter)
				var impact_y: float = float(event.get("impact_y", NAN))
				heights_preserved = heights_preserved and is_finite(impact_y) and absf(impact_y - captured_heights[source_index]) < EPS and absf(game.effects[index].node.position.y - impact_y) < EPS and game.sim.fighters[source_index].clock == 0.0 and game.sim.fighters[source_index].attack == ""
			check(heights_preserved and is_equal_approx(game.hitstop, 0.075), label + " FX uses each collected world foot height even after incoming trade cleared both attack clocks")

func fresh_brain(seed_value: int = 607122):
	var brain = Brain.new(); brain.rng.seed = seed_value; brain.reset()
	return brain

func ai_observation_tests() -> void:
	var brain = fresh_brain()
	var public_world := PublicWorld.new()
	var quiet := true
	for frame in range(14):
		var command: Dictionary = brain.act(public_world, DT)
		quiet = quiet and command.get("move", 0.0) == 0.0 and not command.get(ACTION, false)
	check(quiet and is_equal_approx(brain.reaction, 0.24), "actual AI cannot roundhouse before its 240ms public observation delay")
	var selected := 0
	for frame in range(1200):
		if brain.act(public_world, DT).get(ACTION, false): selected += 1
	check(selected >= 2 and brain.snapshots.size() <= 16, "actual AI independently chooses repeated roundhouses using only public world fields")
	var first = fresh_brain(19); var second = fresh_brain(19)
	var world_a := PublicWorld.new(); var world_b := PublicWorld.new()
	for frame in range(40): first.act(world_a, DT); second.act(world_b, DT)
	world_b.fighters[0].x = 3.0
	var delayed := true
	for frame in range(13): delayed = first.act(world_a, DT) == second.act(world_b, DT) and delayed
	check(delayed, "actual AI roundhouse/movement choice cannot react to new cross-up before snapshot matures")
	var diverged := false
	for frame in range(70): diverged = first.act(world_a, DT) != second.act(world_b, DT) or diverged
	check(diverged, "actual AI eventually responds to matured changed public position")
	var sim_a = Combat.new(); var sim_b = Combat.new()
	sim_a.fighters[0].x = 0.0; sim_a.fighters[1].x = 0.80
	sim_b.fighters[0].x = 0.0; sim_b.fighters[1].x = 0.80
	first = fresh_brain(53); second = fresh_brain(53)
	var independent := true
	var private_test_roundhouses := 0
	for frame in range(900):
		var opponent: Dictionary = sim_b.fighters[0]
		opponent.roundhouse_held = frame % 2 == 0
		opponent.punch_held = frame % 3 == 0
		opponent.heavy_held = frame % 4 == 0
		opponent.queued = "straight" if frame % 2 == 0 else ""
		opponent.queued_attack_id = frame; opponent.input_rearm = frame % 5 == 0
		var a: Dictionary = first.act(sim_a, DT)
		var b: Dictionary = second.act(sim_b, DT)
		independent = a == b and independent
		if a.get(ACTION, false): private_test_roundhouses += 1
	check(independent and private_test_roundhouses >= 2, "actual AI roundhouse choices ignore private roundhouse/jab/heavy edges, queue, and rearm state")

func actual_ai_main_tests() -> void:
	for kind in range(2):
		setup(kind)
		game.brain = fresh_brain(607122 + kind)
		game.toggle_mute()
		# Endurance HP/time and initial distance fixture; no player commands,
		# injected attacks, teleporting during the run, or scripted AI decisions.
		game.sim.time_left = 600.0
		game.sim.fighters[0].hp = 100000.0; game.sim.fighters[1].hp = 100000.0
		game.sim.fighters[0].x = Combat.LEFT; game.sim.fighters[1].x = Combat.LEFT + 0.79
		var seen_ids: Dictionary = {}
		var roundhouses := 0
		var actual_contacts := 0
		var no_player_input := true
		var finite := true
		var grounded := true
		var correct_pose := true
		var frames_run := 0
		for frame in range(12000):
			var events := step(); frames_run += 1
			var f: Dictionary = game.sim.fighters[1]
			no_player_input = no_player_input and game.held.is_empty() and game.taps.is_empty() and game.sim.fighters[0].attack == ""
			finite = finite and is_finite(game.brain.remaining) and game.brain.snapshots.size() <= 16
			if f.attack == ACTION:
				grounded = grounded and f.y == 0.0 and f.vy == 0.0 and f.vx == 0.0 and f.queued == ""
				correct_pose = animation_matches(1) and correct_pose
				if not seen_ids.has(f.attack_id): seen_ids[f.attack_id] = true; roundhouses += 1
			for event: Dictionary in events:
				if event.type == "hit" and event.get("kind", "") == ACTION and event.fighter == 0:
					actual_contacts += 1
					correct_pose = correct_pose and not game.sim.fighters[0].down and game.current_clips[0] == expected_clip(0, "HitReactStrong") and effect_matches(false, 0, event)
			if roundhouses >= 3 and actual_contacts >= 2: break
		check(roundhouses >= 3 and actual_contacts >= 2 and grounded and correct_pose, "selection %d real-main AI independently starts at least three grounded roundhouses and lands two typed non-knockdown contacts" % kind)
		check(no_player_input and finite and not game.sim.round_over and AudioAssertions.silent(game), "selection %d autonomous roundhouse run needs no user input and preserves finite delayed AI and mute" % kind)
		print("ROUNDHOUSE AI SAMPLE selection=", kind, " frames=", frames_run, " roundhouses=", roundhouses, " contacts=", actual_contacts)
		game.hud._request_rematch()
		check(game.brain.snapshots.is_empty() and game.sim.attack_serial == 0 and not game.sim.fighters[1].roundhouse_held, "selection %d actual rematch clears delayed AI and roundhouse edge" % kind)

func run_tests() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game); game.set_physics_process(false)
	await process_frame
	asset_tests()
	phase_feedback_tests()
	input_and_pose_tests()
	geometry_and_protection_tests()
	pause_and_lifecycle_tests()
	mute_and_autoplay_tests()
	knockout_tests()
	trade_feedback_tests()
	ai_observation_tests()
	actual_ai_main_tests()
	print("ROUNDHOUSE OBSERVED CONTACTS ", JSON.stringify(contact_times))
	print("Roundhouse feedback checks: ", checks, "; failures: ", failures, "; missing paired assets: ", missing_assets.size(), "; verified paired pose samples: ", verified_pose_samples, "; provisional fallback samples: ", provisional_fallback_samples, "; strict assets: ", require_new)
	if not missing_assets.is_empty(): print("NOT ASSET-READY: mechanics-only provisional result; four paired RoundhouseKick clips and actual-foot reach/pose validation remain required.")
	if Combat.ROUNDHOUSE_REACH_PROVISIONAL: print("CONTACT GEOMETRY PROVISIONAL: current extent is not yet certified against exported foot XYZ curves.")
	print("LIMITED QA: deterministic headless integration, not visual native/browser/mobile/audio-hardware certification.")
	game.queue_free(); await process_frame
	quit(mini(failures, 255))
