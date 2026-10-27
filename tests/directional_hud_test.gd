extends SceneTree
## Run: godot --headless --path . --script tests/directional_hud_test.gd
## Pushes actual Godot InputEventScreenTouch/Drag/Mouse events through the
## viewport, not direct HUD callback calls. Browser 90-degree mapping is tested
## separately by rotated_input_test.cjs before these Godot-space coordinates.
const HUD = preload("res://scripts/hud.gd")
const ACTIONS := ["punch", "kick", "heavy", "roundhouse", "special"]
const DIRECTIONS := ["left", "right", "jump", "crouch"]
var hud: CanvasLayer
var failures := 0
var checks := 0
var commands: Array = []
var chosen := -1
var pause_requests := 0
var mute_requests := 0
var menu_requests := 0
var rematch_requests := 0

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
	if not ok:
		failures += 1
		printerr("FAIL: ", description, " commands=", commands)

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func fits(rect: Rect2, outer: Rect2) -> bool:
	return outer.grow(0.6).encloses(rect)

func card_contents_fit(card: Control) -> bool:
	for child in card.get_children():
		if child is Control and child.is_visible_in_tree():
			if not fits(child.get_global_rect(), card.get_global_rect()) or not card_contents_fit(child):
				return false
	return true

func label_fits(button: Button) -> bool:
	var text_size := button.get_theme_font("font").get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, button.get_theme_font_size("font_size"))
	var padding := button.get_theme_stylebox("disabled" if button.disabled else "normal").get_minimum_size()
	return text_size.x + padding.x <= button.size.x + 0.6 and text_size.y + padding.y <= button.size.y + 0.6

func touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	root.push_input(event, true)

func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = point
	event.global_position = point
	event.pressed = pressed
	root.push_input(event, true)

func mouse_drag(point: Vector2, held: bool = true) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)

func tap(button: Button, index: int = 90) -> void:
	var point := button.get_global_rect().get_center()
	touch(index, point, true)
	touch(index, point, false)

func pad_point(normalized: Vector2) -> Vector2:
	return hud._direction_pad.global_position + hud._direction_pad.size * normalized

func held(action: String) -> bool:
	return bool(hud._sent_actions.get(action, false))

func no_holds() -> bool:
	for action in ACTIONS + DIRECTIONS:
		if held(action):
			return false
	return hud._touch_contacts.is_empty() and not hud._mouse_direction_active

func overlay_button(card: Control, text: String) -> Button:
	for button: Button in hud._buttons:
		if card.is_ancestor_of(button) and button.text == text:
			return button
	return null

func run_tests() -> void:
	# Full orientations, browser-toolbar-reduced heights and the page-rotated
	# canvas dimensions, finishing back on desktop to detect stale compact UI.
	var fixtures := [Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(844, 390), Vector2i(568, 320), Vector2i(568, 267), Vector2i(844, 337), Vector2i(791, 337), Vector2i(667, 322), Vector2i(614, 322), Vector2i(375, 667), Vector2i(390, 844), Vector2i(375, 614), Vector2i(390, 791), Vector2i(960, 600)]
	for dims in fixtures:
		if hud._gameplay_controls_active():
			commands.clear()
			touch(40, pad_point(Vector2(0.9, 0.1)), true)
			touch(41, hud._touch_buttons["heavy"].get_global_rect().get_center(), true)
			check(held("right") and held("jump") and held("heavy"), "before real viewport resize contacts are held")
		root.size = dims
		await settle()
		check(no_holds(), "%s actual viewport size_changed clears old-orientation contacts" % str(dims))
		touch(40, Vector2(-1000000, -1000000), false)
		touch(41, Vector2(-1000000, -1000000), false, true)
		hud.show_menu()
		await settle()
		var name := "%d×%d" % [dims.x, dims.y]
		var viewport := root.get_visible_rect()
		check(viewport.size.is_equal_approx(Vector2(dims)), name + " exact real viewport")
		check(fits(hud._menu_card.get_global_rect(), viewport) and card_contents_fit(hud._menu_card), name + " selection menu contents fit")
		for choice: Button in hud._choice_buttons:
			check(choice.size.x >= 44.0 and choice.size.y >= 44.0, name + " selection targets ≥44 px")
		chosen = -1
		var choose_point: Vector2 = hud._choice_buttons[0].get_global_rect().get_center()
		touch(90, choose_point, true)
		touch(90, Vector2(-1000000, -1000000), false)
		check(chosen == -1 and hud._menu_overlay.visible, name + " outside-sentinel release never chooses")
		touch(90, choose_point, true)
		touch(90, choose_point, false, true)
		check(chosen == -1, name + " canceled menu tap never chooses")
		tap(hud._choice_buttons[0])
		await settle()
		check(chosen == 0 and not hud._menu_overlay.visible, name + " real touch event selects purple")
		layout_tests(name, dims)
		for kind in range(2):
			hud._choose(kind)
			hud.set_match({"special_kind": kind, "special_cd": 0.0})
			await settle()
			input_tests(name + " kind%d" % kind)
			signature_tests(name, kind)
		await overlay_tests(name, viewport)
		print("DIRECTIONAL HUD ", name, " pad=", hud._direction_pad.size, " action=", hud._touch_buttons["punch"].size, " cumulative_checks=", checks, " failures=", failures)
	await cooldown_tests()
	print("DIRECTIONAL HUD checks: ", checks, "; failures: ", failures)
	quit(failures)

func layout_tests(name: String, dims: Vector2i) -> void:
	var expected := 0.88
	if dims.y > dims.x:
		expected = 1.0 - minf(190.0, float(dims.y) * 0.28) / float(dims.y)
	elif dims.x < 960 or dims.y < 540:
		expected = 1.0 - maxf(76.0, float(dims.y) * 0.19) / float(dims.y)
	var panel: Rect2 = hud._touch_panel.get_global_rect()
	var pad: Rect2 = hud._direction_pad.get_global_rect()
	check(is_equal_approx(hud.gameplay_height_ratio(), expected) and is_equal_approx(panel.position.y, dims.y * expected) and fits(panel, root.get_visible_rect()), name + " existing stage and control height preserved exactly")
	check(fits(pad, panel) and is_equal_approx(pad.size.x, pad.size.y) and pad.size.x >= 44.0, name + " continuous square pad fits and is ≥44 px")
	check(hud._touch_buttons.size() == 5 and not hud._touch_buttons.has("jump") and not hud._touch_buttons.has("crouch"), name + " exactly five attacks, no separate jump or crouch button")
	check(hud._match_panel.size.y <= 85.0, name + " top HUD ≤85 px")
	check(hud._match_panel.get_global_rect().end.y < panel.position.y and hud._status.get_global_rect().end.y <= panel.position.y + 0.6, name + " top HUD and status never overlap controls")
	var rects: Array = [pad]
	for action in ACTIONS:
		var button: Button = hud._touch_buttons[action]
		var rect := button.get_global_rect()
		check(fits(rect, panel) and rect.size.x >= 44.0 and rect.size.y >= 44.0 and label_fits(button), name + " " + action + " target ≥44 px, label and bounds fit")
		if dims == Vector2i(568, 267):
			check(rect.size.x >= 48.0 and rect.size.y >= 48.0, name + " " + action + " ≥48 CSS px on shortest phone")
		for earlier: Rect2 in rects:
			check(not rect.intersects(earlier), name + " " + action + " target never overlaps earlier target")
		rects.append(rect)
	var desktop := dims.x >= 960 and dims.y >= 540 and dims.x >= dims.y
	check(hud._keyboard_help.visible == desktop, name + " menu keyboard help desktop only")
	check(hud._touch_labels[2].visible == (desktop and panel.size.y >= 85.0) and hud._touch_labels[3].visible == (desktop and panel.size.y >= 85.0), name + " no mobile hotkeys in either orientation")
	check("WASD" in hud._keyboard_help.text and "下蹲" in hud._keyboard_help.text and "空格" in hud._keyboard_help.text and "I 回旋踢" in hud._keyboard_help.text and "O 专属波" in hud._keyboard_help.text, name + " help includes all directional and legacy action keys")
	for label: Label in hud._touch_labels:
		if label.visible:
			check(fits(label.get_global_rect(), panel), name + " visible caption fits control strip")
			for target: Rect2 in rects:
				check(not label.get_global_rect().intersects(target), name + " captions never overlap a control target")
	if dims.y > dims.x:
		check(hud._touch_buttons["punch"].position.y < hud._touch_buttons["roundhouse"].position.y and is_equal_approx(hud._touch_buttons["roundhouse"].position.y, hud._touch_buttons["special"].position.y), name + " five attacks use readable 3+2 portrait rows")
	else:
		check(is_equal_approx(hud._touch_buttons["punch"].position.y, hud._touch_buttons["special"].position.y), name + " five attacks use one landscape row")

func input_tests(name: String) -> void:
	var left := pad_point(Vector2(0.1, 0.5))
	var right := pad_point(Vector2(0.9, 0.5))
	var up := pad_point(Vector2(0.5, 0.1))
	var down := pad_point(Vector2(0.5, 0.9))
	var upper_left := pad_point(Vector2(0.1, 0.1))
	var upper_right := pad_point(Vector2(0.9, 0.1))
	var lower_left := pad_point(Vector2(0.1, 0.9))
	var neutral := pad_point(Vector2(0.5, 0.5))
	commands.clear()
	touch(0, upper_left, true)
	check(commands == [["left", true], ["jump", true]], name + " direct diagonal emits direction before fresh up edge")
	for repeat in range(5):
		drag(0, upper_left)
	check(commands.size() == 2, name + " held upper diagonal never repeats jump")
	drag(0, upper_right)
	check(commands == [["left", true], ["jump", true], ["left", false], ["right", true]] and held("jump"), name + " dragging across top steers without a second jump")
	drag(0, right)
	check(held("right") and not held("jump") and commands.back() == ["jump", false], name + " dragging right releases up but keeps movement")
	drag(0, upper_right)
	check(commands.back() == ["jump", true], name + " new upward edge rearms jump")
	drag(0, down)
	check(held("crouch") and not held("jump") and not held("right"), name + " dragging downward switches to crouch without stale jump")
	drag(0, lower_left)
	check(held("crouch") and held("left"), name + " lower diagonal supplies crouch plus horizontal direction")
	drag(0, neutral)
	check(not held("crouch") and not held("left") and not held("jump"), name + " center is neutral")
	touch(0, neutral, false)
	check(no_holds(), name + " neutral release cleans contact")
	commands.clear()
	touch(0, upper_right, true)
	touch(1, upper_right, true)
	touch(0, upper_right, false)
	check(commands == [["right", true], ["jump", true]] and held("jump") and held("right"), name + " two fingers on same diagonal merge and first release does not cancel")
	touch(1, upper_right, false, true)
	check(commands == [["right", true], ["jump", true], ["right", false], ["jump", false]] and no_holds(), name + " last diagonal cancellation releases each action once")
	commands.clear()
	touch(0, left, true)
	touch(1, up, true)
	check(held("left") and held("jump"), name + " two independent fingers combine left plus up")
	touch(1, up, false)
	check(held("left") and not held("jump"), name + " separate up release does not cancel direction")
	touch(0, left, false)
	for action in ACTIONS:
		commands.clear()
		var center: Vector2 = hud._touch_buttons[action].get_global_rect().get_center()
		touch(0, upper_left, true)
		touch(1, center, true)
		touch(2, center, true)
		touch(1, center, false)
		check(commands == [["left", true], ["jump", true], [action, true]] and held(action), name + " diagonal plus two " + action + " fingers coexist")
		touch(0, upper_left, false)
		check(held(action) and not held("left") and not held("jump"), name + " direction release preserves " + action)
		touch(2, center, false, true)
		check(no_holds() and commands.back() == [action, false], name + " final " + action + " cancel releases once")
	commands.clear()
	var kick: Vector2 = hud._touch_buttons["kick"].get_global_rect().get_center()
	var roundhouse: Vector2 = hud._touch_buttons["roundhouse"].get_global_rect().get_center()
	touch(0, down, true)
	touch(1, kick, true)
	touch(2, roundhouse, true)
	touch(1, kick, false)
	check(held("crouch") and held("roundhouse") and not held("kick"), name + " crouch with two independent attack contacts")
	touch(2, roundhouse, false)
	touch(0, down, false)
	commands.clear()
	touch(0, upper_left, true)
	drag(0, Vector2(-1000000, -1000000))
	check(not held("left") and not held("jump") and hud._touch_contacts.has(0), name + " pad drag outside becomes neutral while retaining ownership")
	drag(0, kick)
	check(not held("kick"), name + " direction contact cannot turn into an attack")
	drag(0, upper_right)
	check(held("right") and held("jump"), name + " owned pad contact can re-enter at a new diagonal")
	touch(0, Vector2(-1000000, -1000000), false)
	check(no_holds(), name + " outside-sentinel pad release clears hold")
	commands.clear()
	touch(0, kick, true)
	drag(0, upper_left)
	drag(0, kick)
	touch(0, kick, false)
	check(commands == [["kick", true], ["kick", false]] and no_holds(), name + " action drag-cancel cannot re-enter or turn into direction")
	commands.clear()
	touch(0, upper_left, true)
	touch(0, kick, true)
	check(commands == [["left", true], ["jump", true], ["left", false], ["jump", false], ["kick", true]], name + " reused finger ID clears all old diagonal ownership")
	touch(0, kick, false)
	commands.clear()
	mouse(upper_left, true)
	touch(0, upper_left, true)
	mouse_drag(upper_right)
	check(held("left") and held("right") and held("jump") and commands == [["left", true], ["jump", true], ["right", true]], name + " mouse pad and touch merge independently")
	mouse(Vector2(-1000000, -1000000), false)
	check(held("left") and held("jump") and not held("right"), name + " outside mouse release preserves finger-held diagonal")
	touch(0, upper_left, false)
	check(no_holds(), name + " mouse plus touch clears last owner")
	commands.clear()
	mouse(down, true)
	mouse_drag(down, false)
	check(commands == [["crouch", true], ["crouch", false]] and no_holds(), name + " missing mouse-button mask cancels interrupted drag")
	commands.clear()
	mouse(kick, true)
	touch(0, kick, true)
	touch(0, kick, false)
	check(held("kick") and commands == [["kick", true]], name + " real native action mouse press coexists with touch")
	mouse(kick, false)
	check(commands == [["kick", true], ["kick", false]], name + " native action mouse up releases last owner")
	commands.clear()
	mouse(kick, true)
	mouse(Vector2(-1000000, -1000000), false)
	check(commands == [["kick", true], ["kick", false]] and no_holds(), name + " native action outside mouse release clears hold")
	commands.clear()
	touch(0, upper_left, true)
	touch(0, upper_left, true, true)
	check(commands == [["left", true], ["jump", true], ["left", false], ["jump", false]] and no_holds(), name + " canceled flag overrides pressed and releases old contact")

func signature_tests(name: String, kind: int) -> void:
	var badge: Button = hud._touch_buttons["special"]
	var caption := "喵波" if kind == 0 else "爱心波"
	check(badge.text == caption and not badge.disabled and "O" in badge.tooltip_text, name + " correct ready signature and legacy O help")
	hud.set_match({"special_kind": kind, "special_cd": 4.0})
	check(badge.disabled and badge.text == caption + "\n4.0s" and hud._special_cooldown_overlay.visible and label_fits(badge), name + " full 4-second cooldown remains legible")
	check(fits(hud._special_cooldown_overlay.get_global_rect(), badge.get_global_rect()), name + " cooldown indicator inside attack target")
	commands.clear()
	tap(badge)
	check(commands.is_empty() and hud._touch_contacts.is_empty(), name + " disabled signature never emits or queues")
	hud.set_match({"special_kind": kind, "special_cd": 0.0})

func overlay_tests(name: String, viewport: Rect2) -> void:
	var left := pad_point(Vector2(0.1, 0.1))
	var attack: Vector2 = hud._touch_buttons["roundhouse"].get_global_rect().get_center()
	var old_mute := mute_requests
	tap(hud._mute_button)
	hud.set_muted(true)
	check(mute_requests == old_mute + 1 and hud._mute_button.text == "音效：关", name + " native touch mute signal and label")
	hud.set_muted(false)
	check(hud._mute_button.text == "音效：开", name + " mute label restores")
	for reset in ["pause", "result", "menu", "rematch", "choose", "resize", "focus"]:
		hud._choose(0)
		touch(0, left, true)
		touch(1, attack, true)
		mouse(pad_point(Vector2(0.5, 0.9)), true)
		check(held("left") and held("jump") and held("roundhouse") and held("crouch"), name + " " + reset + " fixture starts with four held actions")
		match reset:
			"pause": hud.set_paused(true)
			"result": hud.show_result("紫白获胜")
			"menu": hud.show_menu()
			"rematch": hud._request_rematch()
			"choose": hud._choose(1)
			"resize": hud._resize()
			"focus": hud._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(no_holds(), name + " " + reset + " releases every touch and mouse action")
		var count := commands.size()
		touch(0, left, false)
		touch(1, attack, false, true)
		mouse(Vector2(-1000000, -1000000), false)
		check(commands.size() == count, name + " stale releases after " + reset + " never duplicate edges")
		if reset in ["pause", "result", "menu"]:
			touch(0, pad_point(Vector2(0.5, 0.9)), true)
			touch(0, Vector2(-1000000, -1000000), false, true)
			check(not held("crouch") and not held("jump"), name + " " + reset + " blocks pad behind overlay")
		hud._choose(0)
		await settle()
		check(no_holds(), name + " reset resumes without synthetic input")
	var old_pause := pause_requests
	tap(hud._pause_button)
	hud.set_paused(true)
	await settle()
	check(pause_requests == old_pause + 1 and fits(hud._pause_card.get_global_rect(), viewport) and card_contents_fit(hud._pause_card), name + " pause tap and full overlay fit")
	var resume := overlay_button(hud._pause_card, "回到舞台")
	check(resume.size.y >= 44.0, name + " resume target ≥44 px")
	tap(resume)
	check(pause_requests == old_pause + 2, name + " resume tap emits signal")
	var old_menu := menu_requests
	tap(overlay_button(hud._pause_card, "返回选角"))
	check(menu_requests == old_menu + 1, name + " pause menu tap emits signal")
	hud.set_paused(false)
	hud.show_result("紫白获胜")
	await settle()
	check(fits(hud._result_card.get_global_rect(), viewport) and card_contents_fit(hud._result_card), name + " result and contents fit")
	var replay := overlay_button(hud._result_card, "再战一场")
	var menu := overlay_button(hud._result_card, "重选偶像")
	check(replay.size.y >= 44.0 and menu.size.y >= 44.0, name + " result targets ≥44 px")
	var old_rematch := rematch_requests
	touch(90, replay.get_global_rect().get_center(), true)
	drag(90, Vector2(-1000000, -1000000))
	drag(90, replay.get_global_rect().get_center())
	touch(90, replay.get_global_rect().get_center(), false)
	check(rematch_requests == old_rematch and hud._result_overlay.visible, name + " drag-canceled rematch never reactivates")
	tap(replay)
	check(rematch_requests == old_rematch + 1 and not hud._result_overlay.visible, name + " fresh rematch works")
	hud.show_result("黄白获胜")
	await settle()
	old_menu = menu_requests
	tap(menu)
	check(menu_requests == old_menu + 1, name + " result reselection signal")
	hud.show_menu()
	await settle()
	tap(hud._choice_buttons[1])
	check(chosen == 1 and not hud._menu_overlay.visible and no_holds(), name + " repeated yellow selection has no stale actions")

func cooldown_tests() -> void:
	hud._choose(1)
	await settle()
	var center: Vector2 = hud._touch_buttons["special"].get_global_rect().get_center()
	var badge: Button = hud._touch_buttons["special"]
	commands.clear()
	touch(0, center, true)
	hud.set_match({"special_kind": 1, "special_cd": 4.0})
	touch(1, center, true)
	for remaining in [3.9, 2.5, 1.0, 0.0]:
		hud.set_match({"special_kind": 1, "special_cd": remaining})
		await settle()
	check(commands == [["special", true]] and not badge.disabled, "cooldown expiry never repeats original hold or buffers disabled touch")
	touch(0, center, false)
	touch(1, center, false)
	tap(badge)
	check(commands == [["special", true], ["special", false], ["special", true], ["special", false]], "signature rearms after release and fresh tap")
	commands.clear()
	hud.set_match({"special_kind": 1, "special_cd": 2.75})
	hud._emit_command("special", true)
	hud.set_match({"special_kind": 1, "special_cd": 0.0})
	hud._emit_command("special", true)
	check(commands.is_empty(), "cooldown mouse callback cannot become an expiry press")
	hud._emit_command("special", false)
	hud._emit_command("special", true)
	hud._emit_command("special", true)
	hud._emit_command("special", false)
	check(commands == [["special", true], ["special", false]], "fresh signature callback emits once")
	hud.set_match({"special_kind": 1, "special_cd": 2.75})
	var frozen_text := badge.text
	var frozen_width: float = hud._special_cooldown_overlay.size.x
	hud.set_paused(true)
	await create_timer(0.15).timeout
	check(badge.text == frozen_text and hud._special_cooldown_overlay.size.x == frozen_width and hud._special_cd == 2.75, "pause freezes simulation-owned cooldown")
	hud.set_paused(false)
	hud.set_match({"special_kind": 1, "special_cd": 1.25})
	check(hud._special_cd == 1.25 and hud._special_cooldown_overlay.size.x < frozen_width, "only simulation snapshots advance badge")
	hud._request_rematch()
	check(hud._special_cd == 0.0 and badge.text == "爱心波" and not badge.disabled, "rematch resets cooldown")
	hud.set_match({"special_kind": 1, "special_cd": 4.0})
	hud.show_menu()
	hud._choose(0)
	check(hud._special_cd == 0.0 and badge.text == "喵波" and not badge.disabled and no_holds(), "reselection resets cooldown, character and contacts")
