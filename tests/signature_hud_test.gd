extends SceneTree
## godot --headless --path . --script tests/signature_hud_test.gd
## Self-contained real-viewport HUD checks; no fighter assets are needed.
const HUD = preload("res://scripts/hud.gd")
const ACTIONS := ["jump", "punch", "kick", "heavy", "roundhouse", "special"]
const TARGETS := ["left", "right", "jump", "punch", "kick", "heavy", "roundhouse", "special"]
var hud: CanvasLayer
var failures := 0
var checks := 0
var commands: Array = []

func _initialize() -> void:

	hud = HUD.new()
	root.add_child(hud)
	hud.command.connect(func(action: String, pressed: bool): commands.append([action, pressed]))
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

func touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	hud._input(event)

func drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	hud._input(event)

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

func run_tests() -> void:
	var fixtures := [Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(844, 390), Vector2i(568, 320), Vector2i(568, 267), Vector2i(844, 337), Vector2i(791, 337), Vector2i(667, 322), Vector2i(614, 322), Vector2i(375, 667), Vector2i(390, 844), Vector2i(375, 614), Vector2i(390, 791), Vector2i(960, 600)]
	for dims in fixtures:
		root.size = dims
		await settle()
		hud.show_menu()
		await settle()
		var name := "%d×%d" % [dims.x, dims.y]
		var viewport := root.get_visible_rect()
		check(fits(hud._menu_card.get_global_rect(), viewport) and card_contents_fit(hud._menu_card), name + " selection menu and extended O help fit")
		for kind in range(2):
			hud._choose(kind)
			hud.set_match({"special_kind": kind, "special_cd": 0.0})
			await settle()
			var badge: Button = hud._touch_buttons["special"]
			var caption := "喵波" if kind == 0 else "爱心波"
			check(hud._touch_buttons.size() == 8 and badge.text == caption and not badge.disabled, name + " kind %d has two directions and six actions with correct wave" % kind)
			check("O 专属波" in hud._keyboard_help.text and "O" in hud._touch_labels[3].text and "O" in badge.tooltip_text, name + " kind %d exposes O without replacing old keys" % kind)
			var expected := 0.88
			if dims.y > dims.x:
				expected = 1.0 - minf(190.0, float(dims.y) * 0.28) / float(dims.y)
			elif dims.x < 960 or dims.y < 540:
				expected = 1.0 - maxf(76.0, float(dims.y) * 0.19) / float(dims.y)
			var panel: Rect2 = hud._touch_panel.get_global_rect()
			check(is_equal_approx(hud.gameplay_height_ratio(), expected) and is_equal_approx(panel.position.y, dims.y * expected) and fits(panel, viewport), name + " kind %d preserves exact stage/control boundary" % kind)
			var targets_fit := true
			var labels_fit := true
			var separate := true
			for action in TARGETS:
				var button: Button = hud._touch_buttons[action]
				var rect := button.get_global_rect()
				targets_fit = targets_fit and fits(rect, panel) and rect.size.x >= 44.0 and rect.size.y >= 44.0
				labels_fit = labels_fit and label_fits(button)
				if dims == Vector2i(568, 267):
					targets_fit = targets_fit and rect.size.x >= 48.0 and rect.size.y >= 48.0
			for a in range(TARGETS.size()):
				for b in range(a + 1, TARGETS.size()):
					separate = separate and not hud._touch_buttons[TARGETS[a]].get_global_rect().intersects(hud._touch_buttons[TARGETS[b]].get_global_rect())
			check(targets_fit and separate, name + " kind %d all eight targets fit, remain ≥44 px and never overlap" % kind)
			check(labels_fit, name + " kind %d every complete action label fits" % kind)
			var jump: Rect2 = hud._touch_buttons["jump"].get_global_rect()
			var punch: Rect2 = hud._touch_buttons["punch"].get_global_rect()
			var last: Rect2 = badge.get_global_rect()
			if dims.y > dims.x:
				check(is_equal_approx(jump.position.y, last.position.y) and last.position.x > jump.end.x and punch.position.y > jump.end.y, name + " portrait six actions form a 3×2 grid")
			else:
				check(is_equal_approx(jump.position.y, last.position.y) and last.position.x > punch.end.x, name + " landscape keeps a six-action row below the stage")
			hud.set_match({"special_kind": kind, "special_cd": 4.0})
			await settle()
			check(badge.disabled and badge.text == caption + "\n4.0s" and hud._special_cooldown_overlay.visible and label_fits(badge), name + " kind %d readable 4s disabled countdown" % kind)
			check(fits(badge.get_global_rect(), panel) and fits(hud._special_cooldown_overlay.get_global_rect(), badge.get_global_rect()), name + " kind %d cooldown stays in target (button %s, overlay %s, panel %s)" % [kind, str(badge.get_global_rect()), str(hud._special_cooldown_overlay.get_global_rect()), str(panel)])
			hud.set_match({"special_kind": kind, "special_cd": 0.0})
			input_tests(name, kind)
		hud.set_paused(true)
		await settle()
		check(fits(hud._pause_card.get_global_rect(), viewport) and card_contents_fit(hud._pause_card), name + " pause controls still fit")
		hud.set_paused(false)
		hud.show_result("再战一场")
		await settle()
		check(fits(hud._result_card.get_global_rect(), viewport) and card_contents_fit(hud._result_card), name + " rematch and reselection controls still fit")
		hud._request_rematch()
	await cooldown_tests()
	print("SIGNATURE HUD checks: ", checks, "; failures: ", failures)
	quit(failures)

func input_tests(name: String, kind: int) -> void:
	var left: Vector2 = hud._touch_buttons["left"].get_global_rect().get_center()
	for action in ACTIONS:
		commands.clear()
		var center: Vector2 = hud._touch_buttons[action].get_global_rect().get_center()
		touch(0, left, true)
		touch(1, center, true)
		touch(1, center, false, true)
		touch(0, left, false)
		check(commands == [["left", true], [action, true], [action, false], ["left", false]], name + " kind %d movement + %s independent touch edges" % [kind, action])
	var center: Vector2 = hud._touch_buttons["special"].get_global_rect().get_center()
	commands.clear()
	touch(3, center, true)
	touch(4, center, true)
	touch(3, center, false)
	check(commands == [["special", true]] and bool(hud._sent_actions.get("special")), name + " two fingers on wave never duplicate or release early")
	touch(4, center, false)
	check(commands == [["special", true], ["special", false]], name + " last wave finger releases exactly once")
	commands.clear()
	touch(3, center, true)
	drag(3, Vector2(-20, -20))
	drag(3, center)
	touch(3, center, false)
	check(commands == [["special", true], ["special", false]] and hud._touch_contacts.is_empty(), name + " wave drag-cancel cannot re-enter or leave a hold")
	commands.clear()
	for repeat in range(3):
		touch(3, center, true)
		touch(3, center, false)
	check(commands == [["special", true], ["special", false], ["special", true], ["special", false], ["special", true], ["special", false]], name + " same finger can make fresh repeat taps, one edge each")

func cooldown_tests() -> void:
	hud._choose(1)
	var center: Vector2 = hud._touch_buttons["special"].get_global_rect().get_center()
	var badge: Button = hud._touch_buttons["special"]
	commands.clear()
	touch(2, center, true)
	hud.set_match({"special_kind": 1, "special_cd": 4.0})
	touch(3, center, true)
	for remaining in [3.9, 2.5, 1.0, 0.0]:
		hud.set_match({"special_kind": 1, "special_cd": remaining})
		await settle()
	check(commands == [["special", true]] and not badge.disabled, "cooldown expiry while original finger is held never repeats or buffers another wave")
	touch(2, center, false)
	touch(3, center, false)
	touch(2, center, true)
	touch(2, center, false)
	check(commands == [["special", true], ["special", false], ["special", true], ["special", false]], "held wave rearms only after release and a fresh press")
	commands.clear()
	hud.set_match({"special_kind": 1, "special_cd": 2.75})
	touch(4, center, true)
	touch(4, center, false)
	check(commands.is_empty() and not hud._touch_contacts.has(4), "disabled cooldown button does not emit or queue touch input")
	hud._emit_command("special", true)
	hud.set_match({"special_kind": 1, "special_cd": 0.0})
	hud._emit_command("special", true)
	check(commands.is_empty(), "mouse held from cooldown cannot become an expiry press")
	hud._emit_command("special", false)
	hud._emit_command("special", true)
	hud._emit_command("special", true)
	hud._emit_command("special", false)
	check(commands == [["special", true], ["special", false]], "fresh mouse wave emits one edge despite repeated held callbacks")
	hud.set_match({"special_kind": 1, "special_cd": 2.75})
	var frozen_text := badge.text
	var frozen_width: float = hud._special_cooldown_overlay.size.x
	hud.set_paused(true)
	await create_timer(0.15).timeout
	check(badge.text == frozen_text and hud._special_cooldown_overlay.size.x == frozen_width and hud._special_cd == 2.75, "paused cooldown presentation does not advance with wall-clock time")
	hud.set_paused(false)
	hud.set_match({"special_kind": 1, "special_cd": 1.25})
	check(hud._special_cd == 1.25 and hud._special_cooldown_overlay.size.x < frozen_width, "next simulation snapshot alone advances cooldown")
	hud.set_match({"special_kind": 1, "special_cd": 0.0})
	check(badge.text == "爱心波" and not badge.disabled and not hud._special_cooldown_overlay.visible, "round reset snapshot removes the entire cooldown badge")
	hud.set_match({"special_kind": 1, "special_cd": 4.0})
	hud._request_rematch()
	check(hud._special_cd == 0.0 and badge.text == "爱心波" and not badge.disabled, "rematch immediately resets cooldown")
	hud.set_match({"special_kind": 1, "special_cd": 4.0})
	hud.show_menu()
	hud._choose(0)
	check(hud._special_cd == 0.0 and badge.text == "喵波" and not badge.disabled and hud._touch_contacts.is_empty(), "reselection clears cooldown/contacts and immediately changes wave kind")
