extends SceneTree
## P2 real-main deterministic integration. Ordinary commands use fresh input
## edges; simulation/attack clocks, event batches and HP are never advanced or
## injected. Explicit fixtures change initial position/guard, a post-commit
## cross-up for projectile misses, and initial HP for the labelled KO case.
## Run: godot --headless --path . --script tests/impact_feedback_test.gd
## Headless tests prove dispatch/state contracts, not human listening or GPU QA.
const Combat = preload("res://scripts/combat.gd")
const DT := 1.0 / 60.0
const EPS := 0.00002
const CONTACT_TYPES := ["hit", "block", "break"]
const HIT_CUES := {"punch":"hit_light", "straight":"hit_straight", "heavy":"hit_heavy", "kick":"hit_kick", "roundhouse":"hit_kick", "meow":"hit_straight", "heart":"heart_hit"}
class FixtureBrain extends RefCounted:
	var command: Dictionary = {}
	func reset() -> void: command.clear()
	func act(_sim, _delta: float) -> Dictionary: return command.duplicate()
var game
var robot := FixtureBrain.new()
var checks := 0
var failures := 0
var samples: Array = []
var failures_detail: Array[String] = []
var report_path := ""
var observed_events: Array = []
var seen_event_ids: Dictionary = {}
var duplicate_events := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
	call_deferred("run_tests")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		failures_detail.append(label)
		printerr("FAIL: ",label)

func has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.name) == property_name: return true
	return false

func configure_feedback(combat_gain: float = 1.0, voice_gain: float = 1.0, shake: bool = true) -> void:
	if game.has_method("set_feedback_preferences"):
		game.set_feedback_preferences(combat_gain,voice_gain,shake)
	else:
		game.hud.feedback_settings_changed.emit(combat_gain,voice_gain,shake)

func setup(kind: int = 0, face: int = 1, move: String = "punch", outcome: String = "hit") -> void:
	game.brain = robot
	game.hud._choose(kind)
	game.set_physics_process(false)
	robot.reset(); game.auto_demo = false
	if game.muted: game.toggle_mute()
	game.sound_enabled = true
	configure_feedback()
	game.audio_pool.unlock()
	game.audio_pool.suspend(false)
	# Wall-constrained defender keeps retreat guard in range without teleports.
	var target_x: float = Combat.RIGHT if face > 0 else Combat.LEFT
	game.sim.fighters[1].x = target_x
	game.sim.fighters[0].x = target_x - face * (2.0 if move == "special" else 0.70)
	if outcome == "miss" and move != "special": game.sim.fighters[0].x = -target_x
	game.sim.fighters[0].face = face; game.sim.fighters[1].face = -face
	if outcome in ["block","break"]: robot.command = {"move":float(face)}
	if outcome == "break":
		# Explicit initial low-guard fixture; no gameplay timing edits.
		game.sim.fighters[1].guard = 10.0
		game.sim.fighters[1].guard_delay = 10.0
	game.render_state(0.0)
	observed_events.clear(); seen_event_ids.clear(); duplicate_events = 0

func step(delta: float = DT) -> Array:
	var elapsed: float = game.sim.elapsed
	game._physics_process(delta)
	# Frozen main frames retain the prior simulation list. Never recount it.
	if is_equal_approx(elapsed,game.sim.elapsed): return []
	var events: Array = game.sim.events.duplicate(true)
	for event: Dictionary in events:
		var id: String = str(event.get("event_id","missing"))
		if seen_event_ids.has(id): duplicate_events += 1
		seen_event_ids[id] = true
		observed_events.append(event)
	return events

func press(action: String) -> void: game.on_command(action,true)
func release(action: String) -> void: game.on_command(action,false)
func pulse(action: String) -> Array:
	press(action)
	var events := step()
	release(action)
	return events
func settle(frames: int) -> void:
	for frame in range(frames): step()

func start_move(move: String) -> bool:
	pulse("punch" if move == "straight" else move)
	if move == "straight":
		var fighter: Dictionary = game.sim.fighters[0]
		var ready := false
		for frame in range(120):
			if fighter.attack != "punch": break
			if game.hitstop <= 0.0 and fighter.clock + DT >= fighter.duration - Combat.PUNCH_BUFFER_WINDOW + EPS:
				ready = true; break
			step()
		if not ready: return false
		pulse("punch")
		if fighter.queued != "straight": return false
		for frame in range(40):
			step()
			if fighter.attack == "straight": break
	return game.sim.fighters[0].attack == move

func played_total() -> int: return int(game.audio_pool.diagnostics().counts.played)
func new_audio(previous: int) -> Array:
	var amount: int = maxi(0,played_total()-previous)
	var records: Array = game.audio_pool.played_log
	return records.slice(maxi(0,records.size()-amount)) if amount > 0 else []
func cue_count(records: Array, cue: String) -> int:
	var amount := 0
	for record: Dictionary in records:
		if record.get("cue","") == cue: amount += 1
	return amount

func effect_at(event: Dictionary) -> Dictionary:
	if not event.has("impact_x") or not event.has("impact_y"): return {}
	var expected := Vector2(float(event.impact_x),float(event.impact_y))
	if not expected.is_finite(): return {}
	for effect: Dictionary in game.effects:
		if not is_instance_valid(effect.get("node")): continue
		var node: Node3D = effect.node
		if Vector2(node.position.x,node.position.y).distance_to(expected) <= EPS: return effect
	return {}

func effect_radius(effect: Dictionary) -> float:
	if effect.is_empty(): return 0.0
	var extent := 0.0
	for child in effect.node.get_children():
		if child is Node3D: extent = maxf(extent,child.position.length())
	return extent

func expected_contact_cue(kind: String, outcome: String) -> String:
	if outcome == "block": return "block"
	if outcome == "break": return "guard_break"
	return HIT_CUES[kind]

func matrix_tests() -> void:
	for character in range(2):
		for face in [-1,1]:
			for move in ["punch","straight","heavy","kick","roundhouse","special"]:
				for outcome in ["hit","block","miss"]:
					setup(character,face,move,outcome)
					var kind: String = ("meow" if character == 0 else "heart") if move == "special" else move
					var label := "character %d facing %d %s %s" % [character,face,kind,outcome]
					var started := start_move(move)
					check(started,label + " starts through ordinary fresh input")
					if not started: continue
					var fighter: Dictionary = game.sim.fighters[0]
					var target: Dictionary = game.sim.fighters[1]
					var attack_id: int = fighter.attack_id
					var hp_before: float = target.hp
					if outcome == "miss" and move == "special":
						# Existing signature miss fixture: defender crosses behind AFTER
						# commitment; cast timing/direction/projectile never manipulated.
						target.x = -1.8 * face
					var contacts: Array = []
					var swings := 0
					var spawns := 0
					var launch_on_time := true
					var contact_metadata := true
					var fx_at_contact := true
					var cue_exact := true
					var dedup_ok := true
					var freeze_ok := true
					var miss_clean := true
					var peak_stop := 0.0
					var peak_radius := 0.0
					var contact_duration := 0.0
					var max_cue_latency_ms := 0.0
					var max_camera_shift_ratio := 0.0
					var rest_projection: Vector2 = game.camera.unproject_position(Vector3.ZERO)
					var shake_bound := true
					var fixed_zoom: float = game.camera.size
					var hud_transform: Transform2D = game.hud._root.get_global_transform()
					var camera_stable := true
					for frame in range(185):
						var played_before := played_total()
						var events := step()
						var audio := new_audio(played_before)
						for record: Dictionary in audio: max_cue_latency_ms = maxf(max_cue_latency_ms,float(record.get("dispatch_latency_ms",INF)))
						var displacement: Vector2 = Vector2(game.camera.h_offset / game.camera.size * game.get_viewport().get_visible_rect().size.x, 0) # Only hit-shake, not authorized world-space follow.
						max_camera_shift_ratio = maxf(max_camera_shift_ratio,absf(displacement.x)/maxf(1.0,game.get_viewport().get_visible_rect().size.x))
						shake_bound = shake_bound and game.shake_remaining <= 0.10 + EPS and absf(game.shake_offset.x) <= game.camera.size * 0.003 + EPS
						camera_stable = camera_stable and game.hud._root.get_global_transform() == hud_transform
						for event: Dictionary in events:
							if event.get("kind","") != kind: continue
							if event.type == "swing":
								swings += 1
								var config: Dictionary = game.sim.attack_config(fighter,move)
								launch_on_time = launch_on_time and fighter.clock + EPS >= float(config.startup) and fighter.clock < float(config.startup) + DT + EPS
								launch_on_time = launch_on_time and int(event.get("source",event.get("fighter",-1))) == 0 and int(event.get("attack_id",-1)) == attack_id
								cue_exact = cue_exact and cue_count(audio,"swing_kick" if move in ["kick","roundhouse"] else "swing_punch") == 1
							if event.type == "projectile_spawn":
								spawns += 1
								launch_on_time = launch_on_time and absf(fighter.clock - (Combat.MEOW_EMIT if character == 0 else Combat.HEART_EMIT)) <= DT + EPS
								cue_exact = cue_exact and cue_count(audio,"meow" if character == 0 else "heart_emit") == 1
							if event.type not in CONTACT_TYPES: continue
							contacts.append(event)
							contact_metadata = contact_metadata and event.type == outcome and int(event.get("source",-1)) == 0 and int(event.get("fighter",-1)) == 1 and int(event.get("attack_id",-1)) == attack_id and event.has("event_id") and event.has("ko")
							var effect := effect_at(event)
							fx_at_contact = fx_at_contact and not effect.is_empty()
							peak_radius = maxf(peak_radius,effect_radius(effect))
							contact_duration = maxf(contact_duration,float(effect.get("duration",0.0)))
							peak_stop = maxf(peak_stop,game.hitstop)
							cue_exact = cue_exact and cue_count(audio,expected_contact_cue(kind,outcome)) == 1
							var before: Array = [game.effects.size(),played_total(),game.hitstop]
							game.dispatch_feedback(event)
							game.dispatch_feedback(event.duplicate(true))
							dedup_ok = dedup_ok and before == [game.effects.size(),played_total(),game.hitstop]
							var frozen: Array = [game.sim.elapsed,game.sim.time_left,fighter.clock,target.stun,game.anims[0].current_animation_position,game.anims[1].current_animation_position]
							step()
							freeze_ok = freeze_ok and frozen == [game.sim.elapsed,game.sim.time_left,fighter.clock,target.stun,game.anims[0].current_animation_position,game.anims[1].current_animation_position]
						if outcome == "miss": miss_clean = miss_clean and game.effects.is_empty() and game.hitstop <= 0.0
					check(swings == (0 if move == "special" else 1) and spawns == (1 if move == "special" else 0) and launch_on_time,label + " exactly one real active-entry swing or exact signature emission")
					check(contacts.size() == (0 if outcome == "miss" else 1) and contact_metadata and duplicate_events == 0,label + " exact contact count and immutable typed source/attack/event/KO metadata")
					check(fx_at_contact and cue_exact and max_cue_latency_ms < 16.7,label + " correct local XY effect and one immediate typed audio cue")
					check(dedup_ok and freeze_ok,label + " redispatch idempotent and hitstop freezes simulation plus both poses")
					check(miss_clean and (not contacts.is_empty() or target.hp == hp_before),label + " miss never creates damage, hit FX or hitstop")
					var expected_damage: float = 0.0 if outcome != "hit" else (12.0 if move == "special" else float(game.sim.attack_config(fighter,move).damage))
					check(absf(target.hp-(hp_before-expected_damage)) < EPS and fighter.attack == "",label + " exact existing damage and completed recovery")
					check(camera_stable and shake_bound and max_camera_shift_ratio <= 0.003 + EPS,label + " HUD fixed, follow independent, shake bounded to 0.3% width / 100ms")
					samples.append({"character":character,"face":face,"kind":kind,"outcome":outcome,"contacts":contacts.size(),"swings":swings,"spawns":spawns,"hitstop":peak_stop,"radius":peak_radius,"duration":contact_duration,"dispatch_latency_ms":max_cue_latency_ms,"camera_shift_ratio":max_camera_shift_ratio})

func contact_sample(move: String, outcome: String = "hit", character: int = 0) -> Dictionary:
	setup(character,1,move,outcome)
	start_move(move)
	var kind: String = ("meow" if character == 0 else "heart") if move == "special" else move
	for frame in range(130):
		for event: Dictionary in step():
			if event.type in CONTACT_TYPES and event.get("kind","") == kind: return event
	return {}

func visual_hierarchy_tests() -> void:
	for character in range(2):
		for face in [-1,1]:
			var light: Dictionary = {}; var heavy: Dictionary = {}; var blocked: Dictionary = {}
			for sample: Dictionary in samples:
				if sample.character != character or sample.face != face: continue
				if sample.kind == "punch" and sample.outcome == "hit": light = sample
				if sample.kind == "heavy" and sample.outcome == "hit": heavy = sample
				if sample.kind == "heavy" and sample.outcome == "block": blocked = sample
			check(not light.is_empty() and not heavy.is_empty() and not blocked.is_empty() and heavy.hitstop > light.hitstop and light.hitstop > blocked.hitstop and heavy.radius > light.radius and light.radius > blocked.radius and heavy.duration > blocked.duration,"character %d facing %d heavy > light > block perceptual scale without full-screen flash" % [character,face])

func simultaneous_trade_tests() -> void:
	for character in range(2):
		for face in [-1,1]:
			setup(character,face,"roundhouse","hit")
			robot.command = {"roundhouse":true}
			pulse("roundhouse")
			var contacts: Array = []
			for frame in range(90):
				for event: Dictionary in step():
					if event.type == "hit" and event.get("kind","") == "roundhouse": contacts.append(event)
				if not contacts.is_empty(): break
			var label := "character %d facing %d simultaneous real-input trade" % [character,face]
			check(contacts.size() == 2 and game.effects.size() == 2 and game.sim.fighters[0].hp == 87.0 and game.sim.fighters[1].hp == 87.0,label + " preserves both collected contacts and existing damage")
			var sources: Dictionary = {}; var attacks: Dictionary = {}; var ids: Dictionary = {}
			var xy_preserved := true
			for event: Dictionary in contacts:
				sources[event.get("source",-1)] = true
				attacks[event.get("attack_id",-1)] = true
				ids[event.get("event_id",-1)] = true
				xy_preserved = xy_preserved and not effect_at(event).is_empty()
			check(sources.size() == 2 and attacks.size() == 2 and ids.size() == 2 and xy_preserved,label + " immutable source/attack/event IDs and XY survive attack cancellation")
			var before: Array = [game.effects.size(),played_total(),game.hitstop]
			for event: Dictionary in contacts: game.dispatch_feedback(event)
			check(before == [game.effects.size(),played_total(),game.hitstop],label + " each contact remains idempotent")
			var dispatches := 0
			for record: Dictionary in game.feedback_history:
				if record.type == "hit" and record.kind == "roundhouse": dispatches += 1
			check(dispatches == 2 and game.audio_pool.diagnostics().active_count <= 10,label + " records both typed contacts with bounded polyphony/cue cooldown")

func lifecycle_tests() -> void:
	for transition in ["pause","focus_loss","background","mute","settings","menu","rematch"]:
		var event := contact_sample("heavy")
		check(not event.is_empty() and game.effects.size() > 0 and game.hitstop > 0.0,transition + " starts from real live heavy feedback")
		var played_before := played_total()
		if transition == "pause": game.toggle_pause()
		elif transition == "focus_loss": game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		elif transition == "background": game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		elif transition == "mute": game.toggle_mute()
		elif transition == "settings": game.hud._open_feedback_settings()
		elif transition == "menu": game.show_menu()
		else: game.hud._request_rematch()
		var diag: Dictionary = game.audio_pool.diagnostics()
		check(int(diag.active_groups.combat) == 0 and int(diag.active_groups.voice) == 0 and diag.queued_count == 0,transition + " stops gameplay voices with no replay queue (fresh rematch UI confirmation allowed)")
		if transition not in ["mute","menu","rematch"]:
			check(game.paused and game.held.is_empty() and game.taps.is_empty(),transition + " pauses and clears held/edge input")
			if transition == "settings":
				check(game.hud.feedback_settings_open(),"settings is a real HUD overlay")
				game.hud._close_feedback_settings()
				check(game.paused and not game.hud.feedback_settings_open(),"settings close never auto-resumes combat")
			game.toggle_pause()
		elif transition == "mute": game.toggle_mute()
		elif transition == "menu": game.hud._choose(0)
		var resumed: int = played_total()
		game.dispatch_feedback(event)
		check(played_total() == resumed,transition + " old contact cannot play after resume/unmute/reset")
		settle(30)
		check(game.audio_pool.diagnostics().queued_count == 0,transition + " never schedules a delayed audio burst")
	# Real late combo input is cancelled, not merely hidden by paused rendering.
	for transition in ["pause","focus_loss","settings"]:
		setup(0,1,"punch","miss")
		pulse("punch")
		for frame in range(70):
			var fighter: Dictionary = game.sim.fighters[0]
			if fighter.clock + DT >= fighter.duration - Combat.PUNCH_BUFFER_WINDOW + EPS: break
			step()
		pulse("punch")
		check(game.sim.fighters[0].queued == "straight",transition + " fixture has an ordinary buffered straight")
		if transition == "pause": game.toggle_pause()
		elif transition == "focus_loss": game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		else: game.hud._open_feedback_settings()
		check(game.sim.fighters[0].queued == "" and game.held.is_empty() and game.taps.is_empty(),transition + " clears actual pending straight and upstream inputs")
		if transition == "settings": game.hud._close_feedback_settings()
		game.toggle_pause(); settle(90)
		check(game.sim.attack_serial == 1 and game.sim.fighters[0].attack == "",transition + " cannot replay cancelled combo")

func guard_break_jump_and_ko_tests() -> void:
	for character in range(2):
		var event := contact_sample("heavy","break",character)
		check(event.get("type","") == "break" and game.sim.fighters[1].guard == 0.0 and cue_count(game.audio_pool.played_log,"guard_break") > 0,"character %d guard break uses distinct cue and genuine guard depletion" % character)
		setup(character,1,"punch","miss")
		var first_played := played_total()
		pulse("jump"); settle(100)
		var jumps := 0; var lands := 0
		for observed: Dictionary in observed_events:
			if observed.type == "jump": jumps += 1
			if observed.type == "land": lands += 1
		check(jumps == 1 and lands == 1 and cue_count(new_audio(first_played),"jump") == 1 and cue_count(new_audio(first_played),"land") == 1,"character %d ordinary jump and landing emit once on physical transitions" % character)
		setup(character,1,"kick","hit")
		first_played = played_total()
		pulse("kick"); settle(200)
		var down_lands := 0
		for observed: Dictionary in observed_events:
			if observed.type == "down_land": down_lands += 1
		check(down_lands == 1 and cue_count(new_audio(first_played),"down_land") == 1,"character %d flying kick down landing has exactly one physical impact cue" % character)
		setup(character,1,"heavy","hit")
		# Labelled initial HP KO fixture; no attack/animation clock injection.
		game.sim.fighters[1].hp = 16.0
		first_played = played_total()
		pulse("heavy"); settle(90)
		var kos := 0
		for observed: Dictionary in observed_events:
			if observed.type == "hit" and observed.get("ko",false): kos += 1
		check(kos == 1 and game.sim.round_over and cue_count(new_audio(first_played),"ko") == 1,"character %d lethal contact adds exactly one KO cue" % character)

func shake_tests() -> void:
	var event := contact_sample("heavy")
	check(not event.is_empty() and game.shake_remaining > 0.0 and game.shake_remaining <= 0.10 + EPS,"real heavy contact starts a shake lasting at most 100 ms")
	settle(7)
	check(game.shake_remaining <= 0.0 and game.shake_offset == Vector2.ZERO,"shake stops within seven 60 Hz frames even during hitstop")
	setup(0,1,"heavy","hit")
	configure_feedback(1.0,1.0,false)
	var fixed_transform: Transform3D = game.camera.transform
	var fixed_h: float = game.camera.h_offset
	var fixed_v: float = game.camera.v_offset
	pulse("heavy")
	var contact := false
	var still := true
	for frame in range(80):
		for impact: Dictionary in step():
			if impact.type == "hit": contact = not effect_at(impact).is_empty() and game.hitstop > 0.0
		still = still and game.shake_remaining <= 0.0 and game.shake_offset == Vector2.ZERO and is_equal_approx(game.camera.h_offset,fixed_h)
	check(contact and still,"shake-off preserves local FX/hitstop with no camera shake (world follow allowed)")

func preference_tests() -> void:
	setup()
	configure_feedback(0.35,0.60,false)
	var diag: Dictionary = game.audio_pool.diagnostics()
	check(absf(float(diag.group_gains.combat)-0.35) < EPS and absf(float(diag.group_gains.voice)-0.60) < EPS,"combat and voice gain controls are independent")
	game.hud._request_rematch()
	diag = game.audio_pool.diagnostics()
	check(absf(float(diag.group_gains.combat)-0.35) < EPS and absf(float(diag.group_gains.voice)-0.60) < EPS,"rematch preserves chosen feedback settings")
	setup(0,1,"heavy","hit")
	game.toggle_mute()
	var played_before := played_total()
	pulse("heavy")
	var muted_contact := false
	for frame in range(80):
		for event: Dictionary in step():
			if event.type == "hit": muted_contact = not effect_at(event).is_empty() and game.hitstop > 0.0
	check(muted_contact and played_total() == played_before and game.audio_pool.diagnostics().active_count == 0,"master mute keeps real visual contact and hitstop with no audio")
	game.toggle_mute()
	check(played_total() == played_before,"unmute never replays dropped cues")

func run_tests() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game); game.set_physics_process(false)
	await process_frame
	var contract: bool = game.has_method("dispatch_feedback") and has_property(game,"audio_pool")
	check(contract,"unified dispatch_feedback and bounded audio_pool API present")
	if not contract:
		game.queue_free(); await process_frame; quit(1); return
	check(game.audio_pool.diagnostics().assets_ready,"all authored P2 cues and original meow imported")
	matrix_tests()
	visual_hierarchy_tests()
	simultaneous_trade_tests()
	lifecycle_tests()
	guard_break_jump_and_ko_tests()
	shake_tests()
	preference_tests()
	var diag: Dictionary = game.audio_pool.diagnostics()
	check(diag.player_count == 10 and diag.active_count <= 10 and diag.seen_event_count <= 256 and game.audio_pool.played_log.size() <= 64 and game.audio_pool.rejected_log.size() <= 64,"long real-main run leaves voices, event memory and telemetry bounded")
	var report := {"checks":checks,"failures":failures,"cases":samples.size(),"samples":samples,"failure_details":failures_detail,"audio":diag,"scope":"deterministic real-main integration; native audio/video evidence is a separate MovieWriter run"}
	if not report_path.is_empty():
		DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
		var output := FileAccess.open(report_path,FileAccess.WRITE)
		if output: output.store_string(JSON.stringify(report,"\t")); output.close()
	print("IMPACT FEEDBACK RESULT checks=",checks," failures=",failures," cases=",samples.size())
	print("LIMITED QA: headless real-main contract tests, not human listening, browser WebGL or mobile hardware certification.")
	game.sim.emitter_provider = Callable()
	game.queue_free(); await process_frame
	quit(mini(failures,255))
