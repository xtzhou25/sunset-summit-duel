extends SceneTree
## godot --headless --path . --script tests/feedback_preferences_test.gd
## Exercises the actual viewport input route, including native mouse buttons,
## touch sliders without mouse emulation, keyboard isolation and rotation.
const HUD = preload("res://scripts/hud.gd")
const ACTIONS := ["left", "right", "jump", "crouch", "punch", "kick", "heavy", "roundhouse", "special"]
var hud: CanvasLayer
var checks := 0
var failures := 0
var settings: Array = []
var commands: Array = []
var pause_requests := 0
var mute_requests := 0

func _initialize() -> void:
	hud = HUD.new()
	root.add_child(hud)
	hud.feedback_settings_changed.connect(func(combat: float, voice: float, shake: bool): settings.append([combat, voice, shake]))
	hud.command.connect(func(action: String, pressed: bool): commands.append([action, pressed]))
	hud.pause_requested.connect(func(): pause_requests += 1)
	hud.mute_requested.connect(func(): mute_requests += 1)
	call_deferred("run_tests")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", description)

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func fits(rect: Rect2, outer: Rect2) -> bool:
	return outer.grow(0.6).encloses(rect)

func contents_fit(control: Control) -> bool:
	for child in control.get_children():
		if child is Control and child.is_visible_in_tree():
			if not fits(child.get_global_rect(), control.get_global_rect()) or not contents_fit(child):
				return false
	return true

func label_fits(control: Control) -> bool:
	var text: String = control.text
	var text_size := control.get_theme_font("font").get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, control.get_theme_font_size("font_size"))
	var padding := control.get_theme_stylebox("normal").get_minimum_size() if control is Button else Vector2.ZERO
	return text_size.x + padding.x <= control.size.x + 0.6 and text_size.y + padding.y <= control.size.y + 0.6

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

func key(code: int, pressed: bool = true, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	root.push_input(event, true)

func tap(button: Button, index: int = 50) -> void:
	var point := button.get_global_rect().get_center()
	touch(index, point, true)
	touch(index, point, false)

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	mouse(point, true)
	mouse(point, false)

func slider_point(slider: HSlider, percent: float) -> Vector2:
	var half := slider.get_theme_icon("grabber").get_width() * 0.5
	return slider.global_position + Vector2(half + (slider.size.x - half * 2.0) * percent / 100.0, slider.size.y * 0.5)

func no_holds() -> bool:
	for action in ACTIONS:
		if bool(hud._sent_actions.get(action, false)):
			return false
	return hud._touch_contacts.is_empty() and not hud._mouse_direction_active and not is_instance_valid(hud._mouse_settings_slider)

func run_tests() -> void:
	await settle()
	check(hud._shake_enabled, "light shake defaults on")
	hud.set_feedback_settings(0.85, 0.6, false)
	check(settings.is_empty(), "initial settings update emits no persistence signal")
	check(hud._combat_volume_slider.value == 85 and hud._voice_volume_slider.value == 60 and not hud._shake_enabled, "independent initial gains reach controls")
	check(hud._combat_volume_label.text == "战斗音效  85%" and hud._voice_volume_label.text == "角色语音  60%", "Chinese labels include current percentages")
	hud.set_feedback_settings(-2.0, 3.0, true)
	check(hud._combat_volume_slider.value == 0 and hud._voice_volume_slider.value == 100 and settings.is_empty(), "out-of-range preferences clamp without emission")
	hud.set_feedback_settings(NAN, INF, true)
	check(hud._combat_volume_slider.value == 100 and hud._voice_volume_slider.value == 100, "nonfinite configuration values recover safely")
	var fixtures := [Vector2i(1280, 800), Vector2i(375, 614), Vector2i(390, 791), Vector2i(568, 267), Vector2i(568, 320), Vector2i(844, 337), Vector2i(844, 390), Vector2i(375, 667), Vector2i(960, 600)]
	for dims in fixtures:
		root.size = dims
		await settle()
		hud.show_menu()
		await settle()
		var label := "%d×%d" % [dims.x, dims.y]
		var viewport := root.get_visible_rect()
		check(fits(hud._menu_card.get_global_rect(), viewport) and contents_fit(hud._menu_card), label + " menu remains fully in bounds")
		check(hud._menu_settings_button.size.x >= 44 and hud._menu_settings_button.size.y >= 44 and label_fits(hud._menu_settings_button), label + " menu settings target remains readable and ≥44px")
		var before_pause := pause_requests
		tap(hud._menu_settings_button)
		await settle()
		check(hud.feedback_settings_open() and hud._menu_open and not hud._paused and pause_requests == before_pause, label + " menu settings opens without pausing or starting a match")
		layout_tests(label, viewport)
		await settings_input_tests(label)
		tap(hud._settings_back_button)
		await settle()
		check(not hud.feedback_settings_open() and hud._menu_overlay.visible and no_holds(), label + " touch Back restores selection and clears contacts")
		click(hud._menu_settings_button)
		await settle()
		check(hud.feedback_settings_open(), label + " native mouse settings entry works")
		click(hud._settings_back_button)
		await settle()
		check(not hud.feedback_settings_open() and hud._menu_overlay.visible, label + " native mouse Back works")
		hud._choose(0)
		await settle()
		commands.clear()
		var pad: Vector2 = hud._direction_pad.global_position + hud._direction_pad.size * Vector2(0.1, 0.1)
		touch(1, pad, true)
		touch(2, hud._touch_buttons["heavy"].get_global_rect().get_center(), true)
		check(bool(hud._sent_actions.get("left")) and bool(hud._sent_actions.get("jump")) and bool(hud._sent_actions.get("heavy")), label + " P1 multi-finger holds work before settings")
		hud._open_feedback_settings()
		await settle()
		check(hud._paused and no_holds() and pause_requests == before_pause + 1, label + " direct in-game settings entry pauses and releases every held action")
		commands.clear()
		key(KEY_ESCAPE)
		key(KEY_ESCAPE, false)
		await settle()
		check(not hud.feedback_settings_open() and hud._paused and hud._pause_overlay.visible and commands.is_empty(), label + " Escape returns to pause, never resumes or sends gameplay")
		check(fits(hud._pause_card.get_global_rect(), viewport) and contents_fit(hud._pause_card), label + " pause card still fits with settings action")
		check(hud._pause_settings_button.size.x >= 44 and hud._pause_settings_button.size.y >= 44 and label_fits(hud._pause_settings_button), label + " pause settings action remains ≥44px and readable")
		tap(hud._pause_settings_button)
		await settle()
		check(hud.feedback_settings_open() and pause_requests == before_pause + 1, label + " pause settings entry does not toggle pause")
		hud.set_feedback_settings(0.27, 0.73, false)
		hud._close_feedback_settings()
		hud.set_paused(false)
		hud.show_result("胜负已分")
		hud._request_rematch()
		hud._choose(1)
		check(hud._combat_gain == 0.27 and hud._voice_gain == 0.73 and not hud._shake_enabled and not hud.feedback_settings_open(), label + " preferences survive result, rematch and character change")
		check(hud._touch_buttons.size() == 5 and hud._direction_pad.size.x >= 44, label + " continuous direction pad and exactly five attacks preserved")
		print("FEEDBACK PREFERENCES ", label, " checks=", checks, " failures=", failures)
	await interrupted_tests()
	identity_tests()
	print("FEEDBACK PREFERENCES checks: ", checks, "; failures: ", failures)
	quit(failures)

func layout_tests(label: String, viewport: Rect2) -> void:
	check(fits(hud._settings_card.get_global_rect(), viewport) and contents_fit(hud._settings_card), label + " settings card and all contents fit")
	var targets: Array = [hud._combat_volume_slider, hud._voice_volume_slider, hud._shake_button, hud._settings_back_button]
	for index in range(targets.size()):
		var target: Control = targets[index]
		check(target.size.x >= 44 and target.size.y >= 44, label + " each settings target is ≥44px")
		for earlier in range(index):
			check(not target.get_global_rect().intersects(targets[earlier].get_global_rect()), label + " settings targets never overlap")
	for control in [hud._settings_title, hud._settings_hint, hud._combat_volume_label, hud._voice_volume_label, hud._shake_button, hud._settings_back_button]:
		check(label_fits(control), label + " complete settings label fits: " + control.text)
	check(hud._combat_volume_slider.min_value == 0 and hud._combat_volume_slider.max_value == 100 and hud._voice_volume_slider.min_value == 0 and hud._voice_volume_slider.max_value == 100, label + " both slider ranges remain 0–100")

func settings_input_tests(label: String) -> void:
	hud.set_feedback_settings(0.85, 0.6, true)
	settings.clear()
	commands.clear()
	var combat: HSlider = hud._combat_volume_slider
	var voice: HSlider = hud._voice_volume_slider
	touch(10, slider_point(combat, 20), true)
	touch(11, slider_point(voice, 80), true)
	check(combat.value == 20 and voice.value == 80, label + " independent simultaneous touch sliders work without mouse emulation")
	drag(10, slider_point(combat, 40))
	check(combat.value == 40 and voice.value == 80, label + " combat drag does not change voice")
	touch(10, slider_point(combat, 40), false, true)
	drag(11, slider_point(voice, 15))
	touch(11, slider_point(voice, 15), false)
	check(combat.value == 40 and voice.value == 15 and no_holds(), label + " canceled slider contact releases independently")
	touch(12, slider_point(combat, 50), true)
	drag(12, slider_point(combat, -40))
	check(combat.value == 0, label + " drag below left bound clamps to zero")
	drag(12, slider_point(combat, 140))
	touch(12, slider_point(combat, 140), false)
	check(combat.value == 100 and no_holds(), label + " drag above right bound clamps to full volume")
	mouse(slider_point(voice, 35), true)
	mouse_drag(slider_point(voice, 65))
	mouse(slider_point(voice, 65), false)
	check(voice.value == 65 and combat.value == 100 and no_holds(), label + " native mouse click and drag update only voice")
	var prior_settings := settings.size()
	var shake_point: Vector2 = hud._shake_button.get_global_rect().get_center()
	touch(13, shake_point, true)
	touch(13, shake_point, false, true)
	check(hud._shake_enabled and settings.size() == prior_settings, label + " canceled toggle never changes preference")
	tap(hud._shake_button)
	check(not hud._shake_enabled and settings.back() == [1.0, 0.65, false], label + " shake toggle emits current independent gains once")
	click(hud._shake_button)
	check(hud._shake_enabled, label + " native mouse shake toggle works")
	voice.grab_focus()
	key(KEY_LEFT)
	key(KEY_LEFT, false)
	check(voice.value == 64, label + " focused slider arrows adjust one percent")
	key(KEY_HOME)
	key(KEY_END)
	check(voice.value == 100, label + " keyboard endpoints stay bounded")
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_J, KEY_K, KEY_L, KEY_I, KEY_O, KEY_SPACE]:
		key(code)
		key(code, false)
	check(commands.is_empty(), label + " slider and settings hotkeys emit no game commands")
	key(KEY_TAB)
	check(root.gui_get_focus_owner() == hud._shake_button, label + " Tab reaches shake control")
	key(KEY_SPACE)
	check(not hud._shake_enabled, label + " focused shake control supports keyboard activation")
	key(KEY_TAB, true, true)
	check(root.gui_get_focus_owner() == voice, label + " Shift-Tab returns to voice slider")
	hud.set_muted(true)
	check(hud._mute_button.text == "音效：关" and "总静音已开启" in hud._settings_hint.text, label + " master mute remains independent and visible in settings explanation")
	check(hud._combat_gain == 1.0 and hud._voice_gain == 1.0, label + " master mute does not overwrite category levels")
	hud.set_muted(false)
	check(hud._mute_button.text == "音效：开", label + " existing master mute control preserved")
	var outside := Vector2(2, 2)
	touch(15, outside, true)
	touch(15, outside, false)
	check(hud.feedback_settings_open() and commands.is_empty(), label + " backdrop tap neither dismisses nor reaches gameplay")

func interrupted_tests() -> void:
	root.size = Vector2i(375, 614)
	hud._open_feedback_settings()
	await settle()
	touch(31, slider_point(hud._combat_volume_slider, 20), true)
	mouse(slider_point(hud._voice_volume_slider, 30), true)
	root.size = Vector2i(568, 267)
	await settle()
	check(hud.feedback_settings_open() and no_holds(), "rotation keeps settings open but cancels all old-orientation drags")
	var combat_before: float = hud._combat_volume_slider.value
	var voice_before: float = hud._voice_volume_slider.value
	drag(31, slider_point(hud._combat_volume_slider, 90))
	mouse_drag(slider_point(hud._voice_volume_slider, 90))
	check(hud._combat_volume_slider.value == combat_before and hud._voice_volume_slider.value == voice_before, "canceled old-coordinate drags do not edit settings after rotation")
	touch(32, slider_point(hud._combat_volume_slider, 33), true)
	hud._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(no_holds() and hud.feedback_settings_open(), "focus loss releases slider drag without unpausing")
	touch(33, slider_point(hud._combat_volume_slider, 44), true)
	hud.show_menu()
	check(no_holds() and not hud.feedback_settings_open(), "return to menu closes settings and releases slider owner")
	hud._open_feedback_settings()
	await settle()
	touch(34, slider_point(hud._voice_volume_slider, 50), true)
	hud.set_paused(false)
	check(no_holds() and not hud.feedback_settings_open(), "external resume closes settings and releases slider owner")

func identity_tests() -> void:
	check(hud._choice_buttons[0].text == "因\nPURPLE" and hud._choice_buttons[1].text == "鱼\nYELLOW", "selection uses the formal names 因 and 鱼 without changing character IDs")
	for kind in [0, 1, 0]:
		hud._choose(kind)
		# Random resolution now belongs to Main, not a standalone HUD selection.
		check(hud.opponent_for(kind) == -1, "standalone HUD requests random without resolving it")
		hud.set_match({"kinds": [kind, 1-kind], "special_kind": kind, "names": [HUD.CHARACTER_NAMES[kind], HUD.CHARACTER_NAMES[1-kind]]})
		for index in range(2):
			var expected_kind: int = kind if index == 0 else 1 - kind
			var expected_name: String = "因" if expected_kind == 0 else "鱼"
			var expected_color: Color = hud.PURPLE if expected_kind == 0 else hud.YELLOW
			check(hud._names[index].text == expected_name and hud._names[index].get_theme_color("font_color") == expected_color, "resolved %s snapshot sets slot %d identity name and color" % [HUD.CHARACTER_NAMES[kind], index])
			check(hud._rounds[index].get_theme_color("font_color") == expected_color and hud._health[index].get_theme_stylebox("fill").bg_color == expected_color and hud._guard[index].get_theme_stylebox("fill").bg_color == expected_color.darkened(0.28), "round dots, health and guard use fighter kind rather than HUD slot")
	hud.set_match({"kinds": [1, 0], "special_kind": 1, "hp0": 42, "hp1": 79})
	check(hud._names[0].text == "鱼" and hud._names[1].text == "因" and hud._health[0].value == 42 and hud._health[1].value == 79, "simulation kind snapshot maps names and preserves meter values")
	# Physical crossing/turning does not remap the stable fighter IDs.
	hud.set_match({"kinds": [1, 0], "special_kind": 1, "x0": 2.0, "x1": -2.0, "face0": -1, "face1": 1})
	check(hud._names[0].get_theme_color("font_color") == hud.YELLOW and hud._names[1].get_theme_color("font_color") == hud.PURPLE, "crossing world positions does not swap identity colors")
	hud.set_match({"kinds": [0, 1], "special_kind": 0})
	check(hud._names[0].text == "因" and hud._names[1].text == "鱼" and hud._health[0].get_theme_stylebox("fill").bg_color == hud.PURPLE, "subsequent character change refreshes cached styles correctly")
