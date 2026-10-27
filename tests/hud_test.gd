extends SceneTree
## Run: godot --headless --path . --script tests/hud_test.gd
## Uses the real project viewport, including toolbar-reduced CSS dimensions.
const HUD = preload("res://scripts/hud.gd")
const ACTIONS := ["left", "right", "jump", "punch", "kick", "heavy", "roundhouse"]
var hud: CanvasLayer
var failures := 0
var checks := 0
var commands: Array = []
var chosen := -1
var pause_requests := 0
var mute_requests := 0
var menu_requests := 0
var rematch_requests := 0
var mesh_cache: Dictionary = {}

func _initialize() -> void:
	hud = HUD.new()
	root.add_child(hud)
	hud.command.connect(func(action: String, pressed: bool): commands.append([action, pressed]))
	hud.selected.connect(func(character: int): chosen = character)
	hud.pause_requested.connect(func(): pause_requests += 1)
	hud.mute_requested.connect(func(): mute_requests += 1)
	hud.menu_requested.connect(func(): menu_requests += 1)
	hud.rematch_requested.connect(func(): rematch_requests += 1)
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", description)
	else:
		failures += 1
		printerr("FAIL: ", description)

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func fits(rect: Rect2, outer: Rect2) -> bool:
	return outer.grow(0.6).encloses(rect)

func touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	hud._input(event)

func tap(button: Button) -> void:
	var center := button.get_global_rect().get_center()
	touch(7, center, true)
	touch(7, center, false)

func overlay_button(card: Control, text: String) -> Button:
	for button: Button in hud._buttons:
		if card.is_ancestor_of(button) and button.text == text:
			return button
	return null

func card_contents_fit(card: Control) -> bool:
	for child in card.get_children():
		if child is Control and child.is_visible_in_tree():
			if not fits(child.get_global_rect(), card.get_global_rect()) or not card_contents_fit(child):
				return false
	return true

func run_tests() -> void:
	if "--roundhouse-bounds-only" in OS.get_cmdline_user_args():
		hud.queue_free()
		await process_frame
		await roundhouse_camera_tests()
		print("HUD checks: ", checks, "; failures: ", failures)
		quit(failures)
		return
	if "--bounds-only" in OS.get_cmdline_user_args():
		hud.queue_free()
		await process_frame
		await reduced_camera_tests()
		await roundhouse_camera_tests()
		print("HUD checks: ", checks, "; failures: ", failures)
		quit(failures)
		return
	# Return to desktop after short-landscape/portrait fixtures to catch stale
	# compact spacing, minimum sizes, visibility, or rotation state.
	var fixtures := [Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(844, 390), Vector2i(568, 320), Vector2i(568, 267), Vector2i(844, 337), Vector2i(375, 667), Vector2i(390, 844), Vector2i(375, 614), Vector2i(390, 791), Vector2i(960, 600)]
	if "--page-landscape" in OS.get_cmdline_user_args():
		fixtures = [Vector2i(844, 337), Vector2i(791, 337), Vector2i(667, 322), Vector2i(614, 322), Vector2i(568, 267), Vector2i(390, 791)]
	for fixture in fixtures:
		root.size = fixture
		await settle()
		hud.show_menu()
		await settle()
		var viewport := root.get_visible_rect()
		var name := "%d×%d" % [fixture.x, fixture.y]
		check(viewport.size.is_equal_approx(Vector2(fixture)), name + " uses exact requested viewport, no backing upscale")
		check(fits(hud._menu_card.get_global_rect(), viewport) and card_contents_fit(hud._menu_card), name + " menu and its contents fit")
		var expected := 0.88
		if fixture.y > fixture.x:
			expected = 1.0 - minf(190.0, float(fixture.y) * 0.28) / float(fixture.y)
		elif fixture.x < 960 or fixture.y < 540:
			expected = 1.0 - maxf(76.0, float(fixture.y) * 0.19) / float(fixture.y)
		check(is_equal_approx(hud.gameplay_height_ratio(), expected), name + " gameplay ratio matches reserved controls")
		for choice: Button in hud._choice_buttons:
			check(choice.size.x >= 44.0 and choice.size.y >= 44.0, name + " character choice target ≥44 px")
		chosen = -1
		touch(31, hud._choice_buttons[0].get_global_rect().get_center(), true)
		touch(31, Vector2(-1000000, -1000000), false)
		check(chosen == -1 and hud._menu_overlay.visible, name + " engine outside-sentinel cancellation cannot select a character")
		tap(hud._choice_buttons[0])
		check(chosen == 0 and not hud._menu_overlay.visible, name + " touch selection works without mouse emulation")
		await settle()
		check(hud._match_panel.size.y <= 85.0, name + " compact top HUD ≤85 px (actual %.0f)" % hud._match_panel.size.y)
		var panel: Rect2 = hud._touch_panel.get_global_rect()
		check(is_equal_approx(panel.position.y, viewport.size.y * expected) and fits(panel, viewport), name + " touch region stays below gameplay and inside viewport")
		if fixture.y > fixture.x:
			check(is_equal_approx(panel.size.y, minf(190.0, float(fixture.y) * 0.28)), name + " bounded portrait control height (actual %.2f px)" % panel.size.y)
			check(panel.size.y >= 160.0 and panel.size.y <= 190.1, name + " portrait controls stay within 160–190 px")
			check(not hud._touch_labels[2].visible and not hud._touch_labels[3].visible and not hud._keyboard_help.visible, name + " phone keyboard hints hidden")
			check(hud._touch_labels[0].visible and hud._touch_labels[1].visible, name + " movement/action headings retained")
		for action in ACTIONS:
			var rect: Rect2 = hud._touch_buttons[action].get_global_rect()
			check(fits(rect, panel), name + " " + action + " button fits reserved touch region")
			check(rect.size.x >= 44.0 and rect.size.y >= 44.0, name + " " + action + " target ≥44 px (actual %.2f×%.2f)" % [rect.size.x, rect.size.y])
			if fixture == Vector2i(568, 267):
				check(rect.size.x >= 48.0 and rect.size.y >= 48.0, name + " " + action + " retains ≥48 CSS-pixel target")
			var button: Button = hud._touch_buttons[action]
			var text_size := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size"))
			var padding := button.get_theme_stylebox("normal").get_minimum_size()
			check(text_size.x + padding.x <= rect.size.x + 0.6 and text_size.y + padding.y <= rect.size.y + 0.6, name + " " + action + " full label fits without clipping")
		var nonoverlap := true
		for a in range(ACTIONS.size()):
			for b in range(a + 1, ACTIONS.size()):
				if hud._touch_buttons[ACTIONS[a]].get_global_rect().intersects(hud._touch_buttons[ACTIONS[b]].get_global_rect()):
					nonoverlap = false
		check(nonoverlap, name + " all seven targets have distinct non-overlapping hit areas")
		var jump_rect: Rect2 = hud._touch_buttons["jump"].get_global_rect()
		var punch_rect: Rect2 = hud._touch_buttons["punch"].get_global_rect()
		var kick_rect: Rect2 = hud._touch_buttons["kick"].get_global_rect()
		var heavy_rect: Rect2 = hud._touch_buttons["heavy"].get_global_rect()
		var roundhouse_rect: Rect2 = hud._touch_buttons["roundhouse"].get_global_rect()
		check(hud._touch_buttons["roundhouse"].text == "回旋踢" and "I 回旋踢" in hud._keyboard_help.text and "I" in hud._touch_labels[3].text, name + " roundhouse has its own readable label and I keyboard help")
		if fixture.y > fixture.x:
			check(is_equal_approx(jump_rect.position.y, kick_rect.position.y) and kick_rect.position.x > jump_rect.end.x and punch_rect.position.y > jump_rect.end.y and is_equal_approx(punch_rect.position.y, heavy_rect.position.y) and is_equal_approx(heavy_rect.position.y, roundhouse_rect.position.y) and heavy_rect.position.x > punch_rect.end.x and roundhouse_rect.position.x > heavy_rect.end.x, name + " portrait actions use jump/flying-kick above punch/heavy/roundhouse")
		else:
			check(is_equal_approx(jump_rect.position.y, roundhouse_rect.position.y) and heavy_rect.position.x > kick_rect.end.x and roundhouse_rect.position.x > heavy_rect.end.x, name + " landscape preserves independent five-action row")
		print("DIMENSIONS ", name, " gameplay=", panel.position.y, " touch=", panel.size.y, " direction=", hud._touch_buttons["left"].size, " action=", jump_rect.size, " menu=", hud._menu_card.size)
		var left: Vector2 = hud._touch_buttons["left"].get_global_rect().get_center()
		for action in ["jump", "punch", "kick", "heavy", "roundhouse"]:
			var center: Vector2 = hud._touch_buttons[action].get_global_rect().get_center()
			commands.clear()
			touch(0, left, true)
			touch(1, center, true)
			check(bool(hud._sent_actions.get("left")) and bool(hud._sent_actions.get(action)) and commands == [["left", true], [action, true]], name + " simultaneous direction + " + action + " emits one edge each")
			touch(0, left, false)
			check(not bool(hud._sent_actions.get("left")) and bool(hud._sent_actions.get(action)), name + " " + action + " survives independent direction release")
			touch(1, center, false, true)
			check(not bool(hud._sent_actions.get(action)), name + " canceled " + action + " touch releases")
		commands.clear()
		touch(0, left, true)
		touch(1, kick_rect.get_center(), true)
		touch(2, roundhouse_rect.get_center(), true)
		check(commands == [["left", true], ["kick", true], ["roundhouse", true]], name + " direction/flying-kick/roundhouse are three independent simultaneous inputs")
		touch(1, kick_rect.get_center(), false)
		check(bool(hud._sent_actions.get("roundhouse")) and bool(hud._sent_actions.get("left")) and not bool(hud._sent_actions.get("kick")), name + " releasing flying-kick does not release roundhouse")
		touch(2, roundhouse_rect.get_center(), false, true)
		check(not bool(hud._sent_actions.get("roundhouse")) and bool(hud._sent_actions.get("left")), name + " canceling roundhouse preserves independent movement")
		touch(0, left, false)
		commands.clear()
		touch(2, roundhouse_rect.get_center(), true)
		touch(2, heavy_rect.get_center(), true)
		check(commands == [["roundhouse", true], ["roundhouse", false], ["heavy", true]], name + " reused finger ID releases old roundhouse before new action")
		touch(2, heavy_rect.get_center(), false)
		check(not bool(hud._sent_actions.get("heavy")) and int(hud._touch_action_counts.get("roundhouse")) == 0, name + " reused finger leaves no held action")
		commands.clear()
		touch(2, heavy_rect.get_center(), true)
		touch(3, heavy_rect.get_center(), true)
		touch(2, heavy_rect.get_center(), false)
		check(bool(hud._sent_actions.get("heavy")) and commands == [["heavy", true]], name + " two fingers on same action do not duplicate or release early")
		touch(3, heavy_rect.get_center(), false)
		check(commands == [["heavy", true], ["heavy", false]], name + " last finger releases action once")
		commands.clear()
		touch(2, roundhouse_rect.get_center(), true)
		touch(3, roundhouse_rect.get_center(), true)
		touch(2, roundhouse_rect.get_center(), false)
		check(bool(hud._sent_actions.get("roundhouse")) and commands == [["roundhouse", true]], name + " two roundhouse fingers do not duplicate or release early")
		touch(3, roundhouse_rect.get_center(), false)
		check(commands == [["roundhouse", true], ["roundhouse", false]], name + " last roundhouse finger releases once")
		commands.clear()
		hud._emit_command("roundhouse", true)
		touch(2, roundhouse_rect.get_center(), true)
		touch(2, roundhouse_rect.get_center(), false)
		check(bool(hud._sent_actions.get("roundhouse")) and commands == [["roundhouse", true]], name + " mouse and touch share roundhouse without duplicate edges")
		hud._emit_command("roundhouse", false)
		check(commands == [["roundhouse", true], ["roundhouse", false]], name + " last mouse release clears roundhouse")
		touch(4, left, true)
		var drag := InputEventScreenDrag.new()
		drag.index = 4
		drag.position = Vector2(-10, -10)
		hud._input(drag)
		check(not bool(hud._sent_actions.get("left")), name + " drag outside clears held direction")
		touch(4, left, true)
		touch(5, roundhouse_rect.get_center(), true)
		hud._resize()
		await settle()
		check(not bool(hud._sent_actions.get("left")) and not bool(hud._sent_actions.get("roundhouse")), name + " resize clears held movement and roundhouse")
		var old_mute := mute_requests
		tap(hud._mute_button)
		hud.set_muted(true)
		check(mute_requests == old_mute + 1 and hud._mute_button.text == "音效：关", name + " touch mute signal and indicator work")
		hud.set_muted(false)
		check(hud._mute_button.text == "音效：开", name + " unmute indicator restores")
		touch(2, left, true)
		touch(3, roundhouse_rect.get_center(), true)
		var old_pause := pause_requests
		tap(hud._pause_button)
		hud.set_paused(true)
		await settle()
		check(pause_requests == old_pause + 1 and not bool(hud._sent_actions.get("left")) and not bool(hud._sent_actions.get("roundhouse")), name + " touch pause emits and clears movement and roundhouse")
		check(fits(hud._pause_card.get_global_rect(), viewport) and card_contents_fit(hud._pause_card), name + " pause card and contents fit")
		touch(2, left, true)
		check(not bool(hud._sent_actions.get("left")), name + " paused overlay blocks underlying controls")
		touch(2, left, false)
		var resume := overlay_button(hud._pause_card, "回到舞台")
		check(resume.size.y >= 44.0, name + " resume target ≥44 px")
		tap(resume)
		check(pause_requests == old_pause + 2, name + " touch resume emits")
		hud.set_paused(false)
		touch(4, left, true)
		touch(5, roundhouse_rect.get_center(), true)
		hud._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(not bool(hud._sent_actions.get("left")) and not bool(hud._sent_actions.get("roundhouse")), name + " focus loss clears movement and roundhouse")
		touch(5, roundhouse_rect.get_center(), true)
		check(bool(hud._sent_actions.get("roundhouse")), name + " roundhouse accepts a fresh press after focus loss")
		touch(5, roundhouse_rect.get_center(), false)
		hud.show_result("紫白获胜")
		await settle()
		check(fits(hud._result_card.get_global_rect(), viewport) and card_contents_fit(hud._result_card), name + " result card and contents fit")
		print("OVERLAYS ", name, " pause=", hud._pause_card.size, " result=", hud._result_card.size)
		var replay := overlay_button(hud._result_card, "再战一场")
		var menu := overlay_button(hud._result_card, "重选偶像")
		check(replay.size.y >= 44.0 and menu.size.y >= 44.0, name + " both result actions ≥44 px")
		var old_rematch := rematch_requests
		touch(31, replay.get_global_rect().get_center(), true)
		touch(31, Vector2(-1000000, -1000000), false)
		check(rematch_requests == old_rematch and hud._result_overlay.visible, name + " engine outside-sentinel cancellation cannot trigger rematch")
		tap(replay)
		check(rematch_requests == old_rematch + 1 and not hud._result_overlay.visible, name + " touch rematch closes result")
		hud.show_result("黄白获胜")
		await settle()
		var old_menu := menu_requests
		tap(menu)
		check(menu_requests == old_menu + 1, name + " touch reselect emits")
		hud.show_menu()
		await settle()
		tap(hud._choice_buttons[1])
		check(chosen == 1 and not hud._menu_overlay.visible, name + " repeated selection chooses second character")
	if "--ui-only" not in OS.get_cmdline_user_args():
		hud.queue_free()
		await process_frame
		await reduced_camera_tests()
		await roundhouse_camera_tests()
	print("HUD checks: ", checks, "; failures: ", failures)
	quit(failures)

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


func reduced_camera_tests() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await settle()
	game.hud._choose(0)
	var samples: Array = [
		{"phase": "", "clock": 0.0},
		{"phase": "", "clock": 0.0, "height": 0.68, "pose": 0.0},
		{"phase": "", "clock": 0.0, "height": 0.68, "pose": 0.2},
		{"phase": "", "clock": 0.0, "height": 0.68, "pose": 0.4},
		{"phase": "air", "clock": 0.0, "height": 0.68},
		{"phase": "air", "clock": 0.2, "height": 0.68},
		{"phase": "fall", "clock": 0.0},
		{"phase": "fall", "clock": 0.2},
		{"phase": "fall", "clock": 0.4667},
		{"phase": "fall", "clock": 0.6},
		{"phase": "hold", "clock": 0.0},
		{"phase": "hold", "clock": 2.0, "ko": true},
		{"phase": "rise", "clock": 0.0},
		{"phase": "rise", "clock": 0.25},
		{"phase": "rise", "clock": 0.5},
		{"phase": "rise", "clock": 0.75},
		{"phase": "rise", "clock": 1.0}
	]
	for dims in [Vector2i(568, 267), Vector2i(844, 337), Vector2i(390, 791), Vector2i(375, 614), Vector2i(960, 600)]:
		root.size = dims
		await settle()
		game.layout_camera()
		var camera_initial: Transform3D = game.camera.global_transform
		var camera_size: float = game.camera.size
		var camera_offset: float = game.camera.v_offset
		var limit: float = game.hud._touch_panel.position.y
		var top: float = game.hud._match_panel.get_global_rect().end.y
		check(is_equal_approx(limit, dims.y * game.hud.gameplay_height_ratio()), "%s actual main camera/HUD share gameplay boundary" % str(dims))
		var margins := [INF, INF]
		var contained := [true, true]
		var vertices_seen := [0, 0]
		var fixed_camera := true
		for face in [-1, 1]:
			for edge in [game.sim.LEFT, game.sim.RIGHT]:
				for sample: Dictionary in samples:
					for i in range(2):
						var f: Dictionary = game.sim.fighters[i]
						f.x = edge if i == 0 else -edge
						f.face = face if i == 0 else -face
						f.y = float(sample.get("height", 0.0))
						f.vy = 0.0; f.vx = 0.0; f.move = 0.0
						f.attack = ""; f.stun = 0.0; f.blocking = false
						f.down = sample.phase != ""; f.down_phase = sample.phase
						f.down_clock = sample.clock; f.down_ko = bool(sample.get("ko", false))
						f.hp = 0.0 if f.down_ko else 100.0
						game.previous_height[i] = f.y
						game.landing_remaining[i] = 0.0
					game.sim.round_over = bool(sample.get("ko", false))
					game.render_state(0.0)
					for i in range(2):
						if sample.phase == "":
							game.anims[i].advance(0.11)
							game.anims[i].seek(float(sample.get("pose", 0.0)), true)
							game.anims[i].advance(0.0)
						var minimum := Vector2(INF, INF)
						var maximum := Vector2(-INF, -INF)
						var vertices := posed_world_vertices(game.actors[i].get_child(0))
						vertices_seen[i] += vertices.size()
						for point in vertices:
							var screen: Vector2 = game.camera.unproject_position(point)
							minimum = minimum.min(screen)
							maximum = maximum.max(screen)
						var margin := minf(minf(minimum.x, dims.x - maximum.x), minf(minimum.y - top, limit - maximum.y))
						margins[i] = minf(margins[i], margin)
						if margin < -0.5:
							contained[i] = false
							printerr("REDUCED CAMERA DETAIL: %s kind %d face %d x %.1f %s@%.3f height %.2f min %s max %s gameplay y %.2f..%.2f margin %.3f" % [str(dims), i, game.sim.fighters[i].face, game.sim.fighters[i].x, sample.phase, sample.clock, game.sim.fighters[i].y, str(minimum), str(maximum), top, limit, margin])
						var f: Dictionary = game.sim.fighters[i]
						fixed_camera = fixed_camera and game.actors[i].position.is_equal_approx(Vector3(f.x, f.y, 0.0))
					fixed_camera = fixed_camera and game.camera.global_transform == camera_initial and is_equal_approx(game.camera.size, camera_size) and is_equal_approx(game.camera.v_offset, camera_offset)
		for i in range(2):
			check(contained[i] and vertices_seen[i] > 10000, "%s kind %d actual weighted skin fits between HUD and touch strip at both walls/faces through jump/down/KO/recover (margin %.3f px)" % [str(dims), i, margins[i]])
		check(fixed_camera, "%s camera and physical roots stay fixed for all sampled silhouettes" % str(dims))
		print("REDUCED CAMERA ", dims, " gameplay=", limit, " topHUD=", top, " margins=", margins, " vertices=", vertices_seen)
	game.sound.stop()
	game.queue_free()
	await process_frame


func roundhouse_camera_tests() -> void:
	# Authored pose fixtures, not a played match. Use actual weighted skin,
	# the production camera, and the production simulation-clock pose mapping.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await settle()
	game.hud._choose(0)
	game.paused = false
	game.hitstop = 0.0
	game.sim.round_over = false
	var available := [true, true]
	var durations: Array[float] = []
	var times: Array = []
	for i in range(2):
		var config: Dictionary = game.sim.attack_config(game.sim.fighters[i], "roundhouse")
		var duration: float = config.startup + config.active + config.recovery
		durations.append(duration)
		var sample_times: Array[float] = []
		for step in range(floori(duration / 0.05) + 1):
			sample_times.append(float(step) * 0.05)
		for endpoint in [0.28, 0.35, 0.42, duration]:
			var seen := false
			for sample_time: float in sample_times:
				seen = seen or is_equal_approx(endpoint, sample_time)
			if not seen: sample_times.append(endpoint)
		sample_times.sort()
		times.append(sample_times)
		check(game.anims[i].get_animation_list().size() == (61 if i==0 else 65), "roundhouse bounds kind %d preserves baseline59 within new signature runtime" % i)
		for side in ["_R", "_L"]:
			var clip: String = "RoundhouseKick" + side
			var exists: bool = game.anims[i].has_animation(clip)
			check(exists, "roundhouse bounds kind %d has authored %s, never fallback" % [i, clip])
			available[i] = available[i] and exists
			if exists:
				var animation: Animation = game.anims[i].get_animation(clip)
				check(is_equal_approx(animation.length, duration) and animation.loop_mode == Animation.LOOP_NONE, "roundhouse bounds kind %d %s duration %.2f s and no loop" % [i, clip, duration])
		print("ROUNDHOUSE SAMPLES kind=", i, " seconds=", sample_times)
	for dims in [Vector2i(568, 267), Vector2i(844, 337), Vector2i(390, 791), Vector2i(375, 614), Vector2i(960, 600)]:
		root.size = dims
		await settle()
		game.layout_camera()
		var camera_initial: Transform3D = game.camera.global_transform
		var camera_size: float = game.camera.size
		var camera_offset: float = game.camera.v_offset
		var limit: float = game.hud._touch_panel.position.y
		var top: float = game.hud._match_panel.get_global_rect().end.y
		check(is_equal_approx(limit, dims.y * game.hud.gameplay_height_ratio()), "%s roundhouse camera uses unchanged HUD/control boundary" % str(dims))
		for i in range(2):
			if not available[i]: continue
			var margins := Vector4(INF, INF, INF, INF)
			var vertices_seen := 0
			var samples_seen := 0
			var fixed_roots := true
			var fixed_camera := true
			var correct_clips := true
			for face in [-1, 1]:
				var clip := "RoundhouseKick_R" if face > 0 else "RoundhouseKick_L"
				var clip_length: float = game.anims[i].get_animation(clip).length
				for edge in [game.sim.LEFT, game.sim.RIGHT]:
					var f: Dictionary = game.sim.fighters[i]
					f.x = edge; f.y = 0.0; f.face = face
					f.vy = 0.0; f.vx = 0.0; f.move = 0.0
					f.attack = "roundhouse"; f.duration = durations[i]; f.clock = 0.0; f.attack_id += 1
					f.stun = 0.0; f.blocking = false; f.down = false
					f.down_phase = ""; f.down_ko = false; f.hp = 100.0
					game.previous_height[i] = 0.0; game.landing_remaining[i] = 0.0
					game.render_state(0.0)
					# Resolve only the initial crossfade, then resample authored
					# times through normal render_state rather than moving bones.
					game.anims[i].speed_scale = 1.0
					game.anims[i].advance(0.11)
					game.render_state(0.0)
					var physical_root: Transform3D = game.actors[i].global_transform
					for sample_time: float in times[i]:
						f.clock = sample_time
						game.render_state(0.0)
						# AnimationPlayer clears current_animation when a non-looping
						# clip reaches its final frame, but retains assigned_animation.
						var at_final := is_equal_approx(sample_time, durations[i])
						var exact_clip: bool = game.anims[i].current_animation == clip or (at_final and game.anims[i].current_animation == "")
						correct_clips = correct_clips and exact_clip and game.current_clips[i] == clip and game.anims[i].assigned_animation == clip and is_equal_approx(game.anims[i].current_animation_position, sample_time / durations[i] * clip_length)
						fixed_roots = fixed_roots and game.actors[i].position.is_equal_approx(Vector3(edge, 0.0, 0.0)) and game.actors[i].global_transform.is_equal_approx(physical_root) and is_equal_approx(f.x, edge) and is_zero_approx(f.y)
						fixed_camera = fixed_camera and game.camera.global_transform == camera_initial and is_equal_approx(game.camera.size, camera_size) and is_equal_approx(game.camera.v_offset, camera_offset)
						var minimum := Vector2(INF, INF)
						var maximum := Vector2(-INF, -INF)
						var vertices := posed_world_vertices(game.actors[i].get_child(0))
						vertices_seen += vertices.size()
						samples_seen += 1
						for point in vertices:
							var screen: Vector2 = game.camera.unproject_position(point)
							minimum = minimum.min(screen)
							maximum = maximum.max(screen)
						var clearance := Vector4(minimum.x, dims.x - maximum.x, minimum.y - top, limit - maximum.y)
						margins = Vector4(minf(margins.x, clearance.x), minf(margins.y, clearance.y), minf(margins.z, clearance.z), minf(margins.w, clearance.w))
						if minf(minf(clearance.x, clearance.y), minf(clearance.z, clearance.w)) < -0.5:
							printerr("ROUNDHOUSE CAMERA DETAIL: %s kind %d clip %s x %.1f time %.3f min %s max %s gameplay y %.2f..%.2f clearance L/R/T/B %s" % [str(dims), i, clip, edge, sample_time, str(minimum), str(maximum), top, limit, str(clearance)])
			var contained := minf(minf(margins.x, margins.y), minf(margins.z, margins.w)) >= -0.5
			check(contained and vertices_seen > 10000 and samples_seen == times[i].size() * 4, "%s kind %d full RoundhouseKick weighted skin fits both walls/faces; clearance L/R/T/B %s" % [str(dims), i, str(margins)])
			check(correct_clips, "%s kind %d uses actual RoundhouseKick_R/L at every requested clock sample" % [str(dims), i])
			check(fixed_roots, "%s kind %d roundhouse never shifts physical arena root" % [str(dims), i])
			check(fixed_camera, "%s kind %d roundhouse never shifts camera or gameplay ratio" % [str(dims), i])
			print("ROUNDHOUSE CAMERA ", dims, " kind=", i, " camera_size=", camera_size, " gameplay=", limit, " topHUD=", top, " clearance_LRTB=", margins, " samples=", samples_seen, " vertices=", vertices_seen)
	game.sound.stop()
	game.queue_free()
	await process_frame
