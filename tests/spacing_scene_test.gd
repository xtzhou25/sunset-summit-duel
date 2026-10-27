extends "res://tests/hud_test.gd"
## Real-main spacing/control regression. Only initial positions and deterministic
## opponent commands are fixtures. No attack clocks, HP, contacts, or poses are set.
## godot --headless --path . --script tests/spacing_scene_test.gd
## -- --baseline records RC7 metrics without enforcing new spacing/control gates.
const Combat = preload("res://scripts/combat.gd")
const NormalAI = preload("res://scripts/ai.gd")
const DT := 1.0 / 60.0
const EPS := 0.0001
class CommandRobot extends RefCounted:
	var command: Dictionary = {}
	func reset() -> void: command.clear()
	func act(_sim, _delta: float) -> Dictionary: return command.duplicate()
var game
var robot := CommandRobot.new()
var baseline := false
var results: Array = []

func _initialize() -> void:
	baseline = "--baseline" in OS.get_cmdline_user_args()
	call_deferred("run_spacing_tests")

func spacing_gate(ok: bool, description: String) -> void:
	if baseline: print("BASELINE OBSERVATION: ", description, " = ", ok)
	else: check(ok, description)

func setup_spacing(kind: int = 0, face: int = 1, gap: float = 0.70) -> void:
	game.brain = robot
	game.hud._choose(kind)
	game.set_physics_process(false)
	game.auto_demo = false
	game.muted = true
	game.sim.fighters[0].x = -face * gap * 0.5
	game.sim.fighters[1].x = face * gap * 0.5
	game.sim.fighters[0].face = face
	game.sim.fighters[1].face = -face
	game.render_state(0.0)

func spacing_step(delta: float = DT) -> Array:
	var elapsed: float = game.sim.elapsed
	game._physics_process(delta)
	# Main deliberately leaves sim.events unchanged during hitstop.
	return game.sim.events.duplicate(true) if game.sim.elapsed != elapsed else []

func spacing_pulse(action: String) -> Array:
	game.on_command(action, true)
	var events := spacing_step()
	game.on_command(action, false)
	return events

func root_gap() -> float:
	return absf(game.sim.fighters[1].x - game.sim.fighters[0].x)

func set_move(direction: float) -> void:
	game.on_command("left", direction < -0.1)
	game.on_command("right", direction > 0.1)

func rendered_roots_match() -> bool:
	for i in range(2):
		var f: Dictionary = game.sim.fighters[i]
		if game.actors[i].position.distance_to(Vector3(f.x, f.y, 0.0)) > EPS: return false
		if absf(game.actors[i].rotation.y - f.face * PI / 2.0) > EPS: return false
	return true

func skin_gap() -> Dictionary:
	# Actual weighted GLB vertices, not pushbox extents or bind-pose AABBs.
	var bounds: Array = []
	for i in range(2):
		var minimum := Vector3(INF, INF, INF)
		var maximum := Vector3(-INF, -INF, -INF)
		var screen_min := Vector2(INF, INF)
		var screen_max := Vector2(-INF, -INF)
		var vertices := posed_world_vertices(game.actors[i].get_child(0))
		for point: Vector3 in vertices:
			minimum = minimum.min(point); maximum = maximum.max(point)
			var screen: Vector2 = game.camera.unproject_position(point)
			screen_min = screen_min.min(screen); screen_max = screen_max.max(screen)
		bounds.append({"world_min_x":minimum.x, "world_max_x":maximum.x,
			"screen_min_x":screen_min.x, "screen_max_x":screen_max.x,
			"screen_min_y":screen_min.y, "screen_max_y":screen_max.y,
			"vertices":vertices.size()})
	var left: int = 0 if game.sim.fighters[0].x < game.sim.fighters[1].x else 1
	var right: int = 1 - left
	return {"world_gap":bounds[right].world_min_x - bounds[left].world_max_x,
		"screen_gap_px":bounds[right].screen_min_x - bounds[left].screen_max_x,
		"bounds":bounds}

func jump_spacing_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for initial_gap in [0.70, 0.90, 1.10]:
				setup_spacing(kind, face, initial_gap)
				set_move(face)
				spacing_pulse("jump")
				var player: Dictionary = game.sim.fighters[0]
				var crossed := false
				var max_height: float = player.y
				var land_count := 0
				var roots_ok := true
				var started: float = game.sim.elapsed
				for frame in range(100):
					var events := spacing_step()
					max_height = maxf(max_height, player.y)
					crossed = crossed or (player.x - game.sim.fighters[1].x) * face > 0.0
					roots_ok = roots_ok and rendered_roots_match()
					for event: Dictionary in events:
						if event.type == "land" and event.fighter == 0: land_count += 1
					if land_count > 0: break
				set_move(0.0)
				for frame in range(12): spacing_step()
				var label := "kind %d face %d jump from %.2fm" % [kind, face, initial_gap]
				spacing_gate(crossed and (player.x - game.sim.fighters[1].x) * face >= 0.69, label + " easily crosses and lands beyond opponent")
				spacing_gate(max_height >= 1.10, label + " has useful crossover height")
				check(land_count == 1 and player.y == 0.0 and roots_ok, label + " one physical landing with exact rendered roots")
				check(player.face == (1 if game.sim.fighters[1].x > player.x else -1) and game.sim.fighters[1].face == -player.face and rendered_roots_match(), label + " naturally faces opponent after landing")
				results.append({"test":"jump", "kind":kind, "face":face, "initial_gap":initial_gap, "crossed":crossed, "peak_y":max_height, "land_gap":root_gap(), "air_and_settle_seconds":game.sim.elapsed - started})

func retreat_spacing_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			setup_spacing(kind, face, 0.80)
			var player: Dictionary = game.sim.fighters[0]
			var x: float = player.x
			var guarded := true
			var visual_guard := true
			set_move(-face)
			for frame in range(18):
				spacing_step()
				guarded = guarded and player.blocking and player.face == face and player.y == 0.0
				visual_guard = visual_guard and String(game.current_clips[0]).begins_with("BackstepGuard") and rendered_roots_match()
			var distance := absf(player.x - x)
			spacing_gate(distance >= 0.40, "kind %d face %d guarded retreat clears >= .40m in .30s (%.3fm)" % [kind, face, distance])
			check(guarded and visual_guard and player.hp == 100.0, "kind %d face %d retreat remains visibly guarded" % [kind, face])
			check(absf(player.guard - 97.3) < EPS, "retreat retains normal guard-resource cost")
			set_move(0.0); spacing_step()
			check(not player.blocking and absf(player.vx) < EPS, "release ends guard-retreat immediately")
			results.append({"test":"retreat", "kind":kind, "face":face, "seconds":0.30, "distance":distance, "guard":player.guard})

func heavy_case(kind: int, face: int, blocked: bool) -> Dictionary:
	setup_spacing(kind, face)
	var start_gap := root_gap()
	var before_visual := skin_gap()
	spacing_pulse("heavy")
	var contacts := 0
	var correct := true
	var maximum_gap := start_gap
	var hit_time := -1.0
	var max_visual := -INF
	for frame in range(100):
		# Guard begins just before the actual active frames, not against a wall.
		# Releasing immediately after contact isolates block push from retreat.
		if blocked and contacts == 0 and game.sim.fighters[0].clock >= 0.32: robot.command = {"move":float(face)}
		var events := spacing_step()
		maximum_gap = maxf(maximum_gap, root_gap())
		for event: Dictionary in events:
			if event.type in ["hit", "block", "break"]:
				contacts += 1
				hit_time = game.sim.elapsed
				correct = correct and event.type == ("block" if blocked else "hit") and event.kind == "heavy" and event.fighter == 1
				robot.command.clear()
		if contacts > 0 and frame % 12 == 0: max_visual = maxf(max_visual, float(skin_gap().world_gap))
		if contacts > 0 and game.sim.fighters[0].attack == "" and game.sim.fighters[1].stun <= 0.0: break
	var visual := skin_gap()
	var label := "kind %d face %d heavy %s" % [kind, face, "block" if blocked else "hit"]
	check(contacts == 1 and correct, label + " one input-driven contact in real main")
	check(game.sim.fighters[1].hp == (100.0 if blocked else 84.0) and not game.sim.fighters[1].down, label + " exact damage and non-knockdown recoil")
	check(rendered_roots_match(), label + " visible body follows physical displacement")
	if not blocked:
		spacing_gate(maximum_gap - start_gap >= 0.70, label + " creates >= .70m additional root separation")
		spacing_gate(float(visual.world_gap) >= 0.35, label + " settles with >= .35m true skinned silhouette gap")
	return {"test":"heavy", "kind":kind, "face":face, "blocked":blocked, "initial_root_gap":start_gap, "max_root_gap":maximum_gap, "final_root_gap":root_gap(), "initial_skin_gap":before_visual.world_gap, "final_skin_gap":visual.world_gap, "final_screen_gap_px":visual.screen_gap_px, "max_sampled_skin_gap":max_visual, "contact_time":hit_time, "contacts":contacts}

func heavy_spacing_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var hit := heavy_case(kind, face, false)
			var blocked := heavy_case(kind, face, true)
			spacing_gate(hit.final_root_gap - blocked.final_root_gap >= 0.40, "kind %d face %d heavy hit opens >= .40m more space than block" % [kind, face])
			results.append(hit); results.append(blocked)

func ai_following_heavy_tests() -> void:
	for face in [-1, 1]:
		setup_spacing(0, face)
		spacing_pulse("heavy")
		var contact := false
		for frame in range(80):
			for event: Dictionary in spacing_step():
				if event.type == "hit" and event.kind == "heavy": contact = true
			if contact: break
		check(contact, "normal AI follow-up starts after a real heavy hit")
		var normal = NormalAI.new()
		normal.rng.seed = 607122
		normal.reset()
		game.brain = normal
		var max_gap := root_gap()
		var gap_after_half_second := 0.0
		var reengaged := false
		var attacked := false
		for frame in range(360):
			spacing_step()
			max_gap = maxf(max_gap, root_gap())
			if frame == 29: gap_after_half_second = root_gap()
			if frame > 36 and root_gap() < 1.10: reengaged = true
			attacked = attacked or game.sim.fighters[1].attack != ""
		spacing_gate(max_gap >= 1.40 and gap_after_half_second >= 1.30, "face %d normal AI preserves visible heavy-created breathing room" % face)
		check(reengaged and attacked, "face %d unmodified seeded normal AI subsequently approaches and attacks" % face)
		results.append({"test":"normal_ai_after_heavy", "face":face, "max_root_gap":max_gap, "gap_at_half_second":gap_after_half_second, "reengaged":reengaged, "attacked":attacked})

func expected_crouch_clip(index: int, base: String) -> String:
	return base + ("_R" if game.sim.fighters[index].face > 0 else "_L")

func crouch_visual_gate(ok: bool, description: String) -> void:
	if "--allow-missing-crouch" in OS.get_cmdline_user_args():
		if not ok: print("PROVISIONAL CROUCH ASSET: ", description)
	else: check(ok, description)

func crouch_control_tests() -> void:
	if baseline: return
	for kind in range(2):
		for face in [-1, 1]:
			setup_spacing(kind, face, 2.6)
			var p: Dictionary = game.sim.fighters[0]
			var label := "kind %d face %d crouch" % [kind, face]
			game.on_command("crouch", true); spacing_step()
			check(p.crouching and p.state == "crouch" and p.crouch_amount > 0.0 and p.crouch_amount < 1.0 and p.y == 0.0, label + " starts from held down through real input")
			crouch_visual_gate(game.current_clips[0] == expected_crouch_clip(0, "CrouchStart"), label + " paired start pose follows new state")
			var x: float = p.x
			set_move(face)
			for frame in range(20): spacing_step()
			check(p.crouching and p.crouch_amount == 1.0 and p.x == x and p.vx == 0.0 and not p.blocking, label + " holds at ground level without accidental walking/guard")
			crouch_visual_gate(game.current_clips[0] == expected_crouch_clip(0, "CrouchLoop"), label + " paired stable held pose")
			game.on_command("crouch", false); spacing_step()
			check(not p.crouching and p.crouch_amount > 0.0 and p.crouch_amount < 1.0 and p.vx * face > 2.3, label + " release begins stand-up without a movement lock")
			crouch_visual_gate(game.current_clips[0] == expected_crouch_clip(0, "CrouchEnd"), label + " paired release pose")
			for frame in range(12): spacing_step()
			check(p.crouch_amount == 0.0 and rendered_roots_match(), label + " completes release with physical roots unchanged")
			setup_spacing(kind, face, 2.6)
			p = game.sim.fighters[0]
			game.on_command("crouch", true)
			for frame in range(20): spacing_step()
			set_move(face); spacing_pulse("jump")
			check(not p.crouching and p.crouch_amount == 0.0 and p.y > 0.0 and p.vx * face > 2.3, label + " diagonal jump immediately interrupts crouch")
			for frame in range(12): spacing_step()
			check(not p.crouching and p.crouch_amount == 0.0 and p.y > 0.5, label + " held down cannot crouch in mid-air")
			setup_spacing(kind, face, 2.6)
			p = game.sim.fighters[0]
			game.on_command("crouch", true)
			for frame in range(20): spacing_step()
			spacing_pulse("heavy")
			check(not p.crouching and p.crouch_amount == 0.0 and p.attack == "heavy", label + " heavy immediately interrupts crouch")
			for incoming in ["heavy", "kick"]:
				setup_spacing(kind, face)
				p = game.sim.fighters[0]
				game.on_command("crouch", true)
				for frame in range(20): spacing_step()
				robot.command = {incoming:true}; spacing_step(); robot.command.clear()
				var contact := false
				for frame in range(80):
					for event: Dictionary in spacing_step():
						if event.type == "hit" and event.fighter == 0: contact = true
					if contact: break
				check(contact and not p.crouching and p.crouch_amount == 0.0 and (p.down if incoming == "kick" else p.stun > 0.0), label + " real incoming " + incoming + " has hurt/down priority")
				check(String(game.current_clips[0]).begins_with("Knockdown" if incoming == "kick" else "HitReactStrong"), label + " hurt/down pose overrides held down")

func air_control_tests() -> void:
	if baseline: return
	for face in [-1, 1]:
		setup_spacing(0, face, 2.6)
		var p: Dictionary = game.sim.fighters[0]
		set_move(face); game.on_command("jump", true); spacing_step()
		check(p.y > 0.0 and absf(p.vx - face * 2.4) < EPS, "face %d up+direction launches diagonally" % face)
		for frame in range(7): spacing_step()
		var original_vx: float = p.vx
		set_move(-face); spacing_step()
		check(p.y > 0.0 and p.vx * face > 0.0 and absf(p.vx - original_vx) > 0.0 and absf(p.vx - original_vx) < 0.3, "face %d airborne reverse accelerates, never snaps velocity" % face)
		for frame in range(23): spacing_step()
		check(p.y > 0.0 and p.vx * face < -2.3, "face %d held opposite input reverses airborne travel" % face)
		set_move(0.0)
		var land_count := 0
		for frame in range(130):
			for event: Dictionary in spacing_step():
				if event.type == "land" and event.fighter == 0: land_count += 1
		check(land_count == 1 and p.y == 0.0, "face %d held up produces only one jump through landing" % face)
		game.on_command("jump", false); spacing_step(); spacing_pulse("jump")
		check(p.y > 0.0, "face %d released then fresh up immediately jumps again" % face)

func send_key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.pressed = pressed; event.echo = echo
	game._input(event)

func keyboard_source_tests() -> void:
	if baseline: return
	setup_spacing(0, 1, 2.6)
	send_key(KEY_A, true); send_key(KEY_LEFT, true); send_key(KEY_A, false)
	check(game.player_command().move == -1.0, "releasing A preserves still-held left-arrow source")
	send_key(KEY_LEFT, false)
	check(game.player_command().move == 0.0, "releasing last left source clears movement")
	send_key(KEY_D, true); game.on_command("right", true); send_key(KEY_D, false)
	check(game.player_command().move == 1.0, "keyboard release preserves independently held touch direction")
	game.on_command("right", false)
	check(game.player_command().move == 0.0, "last touch release clears merged direction")
	send_key(KEY_DOWN, true); spacing_step()
	check(game.sim.fighters[0].crouching, "physical down arrow maps to crouch")
	send_key(KEY_DOWN, false); send_key(KEY_S, true); spacing_step()
	check(game.sim.fighters[0].crouching, "physical S maps to crouch")
	send_key(KEY_S, false)
	for frame in range(15): spacing_step()
	send_key(KEY_UP, true); spacing_step(); send_key(KEY_W, true); spacing_step()
	var lands := 0
	for frame in range(110):
		send_key(KEY_UP, true, true)
		for event: Dictionary in spacing_step():
			if event.type == "land" and event.fighter == 0: lands += 1
	check(lands == 1 and game.sim.fighters[0].y == 0.0, "up/W overlapping sources and OS repeat do not create another jump")
	send_key(KEY_UP, false)
	check(game.held.get("jump", false), "releasing up preserves still-held W source")
	send_key(KEY_W, false); send_key(KEY_SPACE, true); spacing_step()
	check(game.sim.fighters[0].y > 0.0, "space remains a fresh jump shortcut")
	for notification in [0, Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
		setup_spacing()
		send_key(KEY_LEFT, true); send_key(KEY_DOWN, true); game.on_command("jump", true)
		if notification == 0: game.toggle_pause()
		else: game._notification(notification)
		check(game.paused and game.held.is_empty() and game.taps.is_empty() and game.keyboard_sources.is_empty() and game.touch_sources.is_empty(), "pause/focus loss clears every input source and old tap")
		game.toggle_pause(); spacing_step()
		check(game.sim.fighters[0].y == 0.0 and game.sim.fighters[0].vx == 0.0 and not game.sim.fighters[0].crouching, "resume never replays old direction/crouch/jump")
		game.on_command("jump", true); spacing_step()
		check(game.sim.fighters[0].y > 0.0, "first fresh jump after pause is accepted")

func run_spacing_tests() -> void:
	root.size = Vector2i(960, 600)
	game = load("res://main.tscn").instantiate()
	root.add_child(game); game.set_physics_process(false)
	await process_frame
	jump_spacing_tests()
	retreat_spacing_tests()
	heavy_spacing_tests()
	ai_following_heavy_tests()
	crouch_control_tests()
	air_control_tests()
	keyboard_source_tests()
	print("SPACING_METRICS ", JSON.stringify(results))
	print("Spacing scene checks: ", checks, "; failures: ", failures, "; baseline: ", baseline)
	game.queue_free(); await process_frame
	quit(mini(failures, 255))
