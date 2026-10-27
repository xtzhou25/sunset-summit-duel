extends CanvasLayer
const Characters=preload("res://scripts/characters.gd")
## Responsive, self-contained interface for the Livehouse duel.
## Health and guard values are expressed on a 0–100 scale.

signal selected(character: int)
signal command(action: String, pressed: bool)
signal pause_requested
signal rematch_requested
signal menu_requested
signal mute_requested
signal feedback_settings_changed(combat_gain: float, voice_gain: float, shake_enabled: bool)

const INK := Color("0b0913")
const PANEL := Color("171322")
const PURPLE := Color("c77dff")
const YELLOW := Color("ffe273")
const WHITE := Color("f7efff")
const DIM := Color("b8abc9")
const CHARACTER_NAMES := ["因", "鱼", "七", "桃", "哈"]
var opponent_choice:=-1
var _opponent_button:Button
var _menu_tagline:Label
var _menu_tip:Label

var _root: Control
var _match_panel: PanelContainer
var _touch_panel: PanelContainer
var _touch_inner: Control
var _touch_x_offset := 0.0
var _menu_overlay: ColorRect
var _result_overlay: ColorRect
var _pause_overlay: ColorRect
var _menu_stack: VBoxContainer
var _menu_padding: MarginContainer
var _keyboard_help: Label
var _desktop_help: Label

func desktop_controls() -> bool:
	return not OS.has_feature("web") and not OS.has_feature("mobile")

var _choice_buttons: Array[Button] = []
var _choices_grid: GridContainer
var _menu_card: PanelContainer
var _result_card: PanelContainer
var _pause_card: PanelContainer
var _menu_footer: HBoxContainer
var _pause_actions: HBoxContainer
var _menu_settings_button: Button
var _pause_settings_button: Button
var _settings_overlay: ColorRect
var _settings_card: PanelContainer
var _settings_inner: Control
var _settings_title: Label
var _settings_hint: Label
var _combat_volume_label: Label
var _voice_volume_label: Label
var _combat_volume_slider: HSlider
var _voice_volume_slider: HSlider
var _shake_button: Button
var _settings_back_button: Button
var _settings_open := false
var _combat_gain := 1.0
var _voice_gain := 1.0
var _shake_enabled := true
var _mouse_settings_slider: HSlider
var _title: Label
var _timer: Label
var _status: Label
var _result_title: Label
var _mute_button: Button
var _pause_button: Button
var _names: Array[Label] = []
var _rounds: Array[Label] = []
var _health: Array[ProgressBar] = []
var _guard: Array[ProgressBar] = []
var _fighter_kinds: Array[int] = [0, 1]
var _meter_style_kinds: Array[int] = [-1, -1]
# Fixed-base joystick: one owner, discrete commands, visible clamped nub.
# Attack contacts remain independent; no gameplay timing or keyboard changes.
var _direction_pad: Panel
var _direction_glyphs: Dictionary = {}
var _joystick_nub: Panel
var _joystick_touch_id: int = -1
var _joystick_vector := Vector2.ZERO
var _joystick_actions: Array = []
const JOYSTICK_DEAD_ENTER := 0.26
const JOYSTICK_DEAD_EXIT := 0.18
const JOYSTICK_AXIS_ENTER := 0.38
const JOYSTICK_AXIS_EXIT := 0.26
var _mouse_direction_active := false
var _mouse_direction_actions: Array = []
const DIRECTION_ACTIONS := ["left", "right", "crouch", "jump"]
const ATTACK_ACTIONS := ["punch", "kick", "heavy", "roundhouse", "special"]
var _touch_buttons: Dictionary = {}
var _touch_labels: Array[Label] = []
var _font_controls: Array[Control] = []
var _buttons: Array[Button] = []
var _touch_contacts: Dictionary = {}
var _touch_action_counts: Dictionary = {}
var _mouse_held: Dictionary = {}
var _sent_actions: Dictionary = {}
var _portrait := false
var _scale := 1.0
var _menu_open := true
var _result_open := false
var _paused := false
var _ui_font: Font
var _special_kind := 0
var _special_cd := 0.0
var _special_input_blocked := false
var _special_cooldown_overlay: ColorRect
const SPECIAL_COOLDOWN := 4.0

func _ready() -> void:
	layer = 10
	if ResourceLoader.exists("res://assets/ui_font.otf"):
		_ui_font = load("res://assets/ui_font.otf") as Font
	_root = Control.new()
	_root.name = "DuelInterface"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	if _ui_font:
		var ui_theme := Theme.new()
		ui_theme.default_font = _ui_font
		_root.theme = ui_theme
	_build_match_panel()
	_build_touch_panel()
	_desktop_help = _center_label("", 14, WHITE)
	_desktop_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_desktop_help)
	_build_menu()
	_build_result()
	_build_pause()
	_build_feedback_settings()
	get_viewport().size_changed.connect(_resize)
	_resize()
	show_menu()
	_queue_overlay_layout()

func gameplay_height_ratio() -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	if desktop_controls():
		return 1.0 - 52.0 / maxf(1.0, viewport_size.y)
	if viewport_size.y > viewport_size.x:
		return 1.0 - minf(190.0, viewport_size.y * 0.28) / maxf(1.0, viewport_size.y)
	if viewport_size.x >= 960.0 and viewport_size.y >= 540.0:
		return 0.88
	# Use real viewport pixels, including browser-toolbar-reduced heights.
	# 76 px leaves a heading and a 48 px target row without covering the stage.
	return 1.0 - maxf(76.0, viewport_size.y * 0.19) / maxf(1.0, viewport_size.y)

func set_match(data: Dictionary) -> void:
	if not is_instance_valid(_root):
		return
	var selected_kind := Characters.valid_kind(int(data.get("special_kind", _special_kind)))
	var fighter_kinds: Array = data.get("kinds", [selected_kind, Characters.default_opponent(selected_kind)])
	for i in range(2):
		_set_fighter_identity(i, int(fighter_kinds[i]) if i < fighter_kinds.size() else i)
	var fighter_names: Array = data.get("names", [Characters.get_character(_fighter_kinds[0]).name, Characters.get_character(_fighter_kinds[1]).name])
	for i in range(2):
		_health[i].value = clampf(float(data.get("hp%d" % i, 100.0)), 0.0, 100.0)
		_guard[i].value = clampf(float(data.get("guard%d" % i, 100.0)), 0.0, 100.0)
		if i < fighter_names.size():
			_names[i].text = str(fighter_names[i])
		var wins := int(data.get("wins%d" % i, 0))
		_rounds[i].text = ("●" if wins >= 1 else "○") + "  " + ("●" if wins >= 2 else "○")
	_timer.text = "%02d" % maxi(0, int(ceil(float(data.get("time", 60)))))
	_status.text = str(data.get("status", "先取两局 · 每局 60 秒"))
	_status.visible = not _menu_open and not _paused and not _result_open
	# Only simulation snapshots advance this badge. Pausing or a suspended web
	# tab must not run a second, wall-clock cooldown in the interface.
	_set_special_status(int(data.get("special_kind", _special_kind)), float(data.get("special_cd", 0.0)))

func show_menu() -> void:
	_clear_touches()
	_hide_feedback_settings()
	_set_special_status(_special_kind, 0.0)
	_menu_open = true
	_result_open = false
	_paused = false
	_menu_overlay.show()
	_result_overlay.hide()
	_pause_overlay.hide()
	_update_visibility()
	_queue_overlay_layout()

func show_result(text: String) -> void:
	_clear_touches()
	_hide_feedback_settings()
	_menu_open = false
	_result_open = true
	_paused = false
	_result_title.text = text
	_menu_overlay.hide()
	_pause_overlay.hide()
	_result_overlay.show()
	_update_visibility()
	_queue_overlay_layout()

func set_paused(value: bool) -> void:
	_clear_touches()
	if not value:
		_hide_feedback_settings()
	_paused = value
	_pause_overlay.visible = value and not _menu_open and not _result_open
	_pause_button.text = "继续" if value else "暂停"
	_update_visibility()
	if value:
		_queue_overlay_layout()

func set_muted(value: bool) -> void:
	_mute_button.text = "音效：关" if value else "音效：开"
	_mute_button.tooltip_text = "开启音效" if value else "关闭音效"
	if is_instance_valid(_settings_hint):
		_settings_hint.text = "总静音已开启 · 音量设置仍会保留" if value else "独立调节音量 · 不影响战斗规则"

func set_feedback_settings(combat_gain: float, voice_gain: float, shake_enabled: bool) -> void:
	# Loading preferences is silent: the caller owns persistence and audio buses.
	_combat_gain = clampf(combat_gain, 0.0, 1.0) if is_finite(combat_gain) else 1.0
	_voice_gain = clampf(voice_gain, 0.0, 1.0) if is_finite(voice_gain) else 1.0
	_shake_enabled = shake_enabled
	if is_instance_valid(_combat_volume_slider):
		_combat_volume_slider.set_value_no_signal(roundf(_combat_gain * 100.0))
		_voice_volume_slider.set_value_no_signal(roundf(_voice_gain * 100.0))
		_update_feedback_labels()

func feedback_settings_open() -> bool:
	return _settings_open

func _update_feedback_labels() -> void:
	_combat_volume_label.text = "战斗音效  %d%%" % int(roundf(_combat_gain * 100.0))
	_voice_volume_label.text = "角色语音  %d%%" % int(roundf(_voice_gain * 100.0))
	_shake_button.text = "动态效果：开" if _shake_enabled else "动态效果：关"
	_shake_button.tooltip_text = "关闭命中震动、灯光与观众挥动" if _shake_enabled else "开启轻微命中震动、灯光与观众挥动"

func _feedback_volume_changed(value: float, voice: bool) -> void:
	if voice:
		_voice_gain = clampf(value / 100.0, 0.0, 1.0)
	else:
		_combat_gain = clampf(value / 100.0, 0.0, 1.0)
	_update_feedback_labels()
	feedback_settings_changed.emit(_combat_gain, _voice_gain, _shake_enabled)

func _toggle_feedback_shake() -> void:
	_shake_enabled = not _shake_enabled
	_update_feedback_labels()
	feedback_settings_changed.emit(_combat_gain, _voice_gain, _shake_enabled)

func _open_feedback_settings() -> void:
	_clear_touches()
	# Normal entry is from selection or pause; this also safely supports a
	# programmatic entry during a match without leaving the simulation running.
	if not _menu_open and not _result_open and not _paused:
		pause_requested.emit()
		set_paused(true)
	_settings_open = true
	_menu_overlay.hide()
	_pause_overlay.hide()
	_settings_overlay.show()
	_update_visibility()
	_queue_overlay_layout()

func _close_feedback_settings() -> void:
	_clear_touches()
	_hide_feedback_settings()
	_menu_overlay.visible = _menu_open
	_pause_overlay.visible = _paused and not _menu_open and not _result_open
	_update_visibility()
	_queue_overlay_layout()

func _hide_feedback_settings() -> void:
	_settings_open = false
	if is_instance_valid(_settings_overlay):
		_settings_overlay.hide()
		var focus := get_viewport().gui_get_focus_owner()
		if focus and _settings_overlay.is_ancestor_of(focus):
			focus.release_focus()

func _build_match_panel() -> void:
	_match_panel = PanelContainer.new()
	_match_panel.add_theme_stylebox_override("panel", _without_padding(_style(Color("15101fe8"), Color("463451"), 10, 1)))
	_match_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_match_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_match_panel.add_child(_margin(box, 10, 4))
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 7)
	box.add_child(heading)
	_title = _label("决战日不落之巅", 12, DIM)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	_pause_button = _button("暂停", DIM, 12)
	_pause_button.custom_minimum_size.y = 26
	_pause_button.pressed.connect(func(): pause_requested.emit())
	heading.add_child(_pause_button)
	_mute_button = _button("音效：开", DIM, 12)
	_mute_button.custom_minimum_size.y = 26
	_mute_button.pressed.connect(func(): mute_requested.emit())
	heading.add_child(_mute_button)
	var fighters := HBoxContainer.new()
	fighters.add_theme_constant_override("separation", 12)
	box.add_child(fighters)
	fighters.add_child(_fighter_meter(0, PURPLE, false))
	var clock_box := VBoxContainer.new()
	clock_box.custom_minimum_size.x = 42
	clock_box.alignment = BoxContainer.ALIGNMENT_CENTER
	clock_box.add_theme_constant_override("separation", 0)
	fighters.add_child(clock_box)
	_timer = _label("60", 28, WHITE)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_box.add_child(_timer)
	fighters.add_child(_fighter_meter(1, YELLOW, true))
	_status = _label("先取两局 · 每局 60 秒", 12, DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_root.add_child(_status)
	_status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_status.hide()

func _fighter_meter(index: int, color: Color, right: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	column.add_child(row)
	var name_label := _label(CHARACTER_NAMES[index], 16, color)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	var round_label := _label("○  ○", 14, color)
	if right:
		row.add_child(round_label)
		row.add_child(name_label)
	else:
		row.add_child(name_label)
		row.add_child(round_label)
	_names.append(name_label)
	_rounds.append(round_label)
	var hp := _meter(color, 9)
	if right:
		hp.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	column.add_child(hp)
	_health.append(hp)
	var guard := _meter(color.darkened(0.28), 3)
	if right:
		guard.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	column.add_child(guard)
	_guard.append(guard)
	return column

func _set_fighter_identity(index: int, kind: int) -> void:
	kind = Characters.valid_kind(kind)
	_fighter_kinds[index] = kind
	if _meter_style_kinds[index] == kind:
		return
	_meter_style_kinds[index] = kind
	var color:Color = Characters.get_character(kind).color
	_names[index].text = CHARACTER_NAMES[kind]
	_names[index].add_theme_color_override("font_color", color)
	_rounds[index].add_theme_color_override("font_color", color)
	_health[index].add_theme_stylebox_override("fill", _without_padding(_style(color, Color.TRANSPARENT, 4, 0)))
	_guard[index].add_theme_stylebox_override("fill", _without_padding(_style(color.darkened(0.28), Color.TRANSPARENT, 4, 0)))

func _meter(color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.custom_minimum_size.y = height
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _without_padding(_style(Color("30273c"), Color.TRANSPARENT, 4, 0)))
	bar.add_theme_stylebox_override("fill", _without_padding(_style(color, Color.TRANSPARENT, 4, 0)))
	return bar

func _build_touch_panel() -> void:
	_touch_panel = PanelContainer.new()
	_touch_panel.name = "ReservedTouchRegion"
	var touch_style := _style(Color("100d19"), Color("4a365d"), 0, 1)
	touch_style.content_margin_left = 0
	touch_style.content_margin_right = 0
	touch_style.content_margin_top = 0
	touch_style.content_margin_bottom = 0
	_touch_panel.add_theme_stylebox_override("panel", touch_style)
	_root.add_child(_touch_panel)
	_touch_inner = Control.new()
	_touch_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_panel.add_child(_touch_inner)
	_direction_pad = Panel.new()
	_direction_pad.name = "FixedJoystickBase"
	_direction_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_direction_pad.add_theme_stylebox_override("panel", _style(Color("241b30"), PURPLE.darkened(0.15), 100, 2))
	_direction_pad.tooltip_text = "上：跳跃 · 下：下蹲 · 左右：移动 · 斜上：斜跳"
	_touch_inner.add_child(_direction_pad)
	for entry in [["left", "◀"], ["right", "▶"], ["jump", "▲"], ["crouch", "▼"], ["center", "·"]]:
		var glyph := _label(str(entry[1]), 20, DIM if entry[0] == "center" else PURPLE)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_direction_pad.add_child(glyph)
		_direction_glyphs[str(entry[0])] = glyph
	_direction_glyphs["center"].hide()
	_joystick_nub = Panel.new()
	_joystick_nub.name = "JoystickNub"
	_joystick_nub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_nub.add_theme_stylebox_override("panel", _style(Color("dfbcff"), WHITE, 100, 2))
	_direction_pad.add_child(_joystick_nub)
	for entry in [["punch", "拳击", PURPLE], ["kick", "飞踢", YELLOW], ["heavy", "重拳", Color("ffad7a")], ["roundhouse", "回旋踢", Color("83e4d1")], ["special", "喵波", PURPLE]]:
		var action := str(entry[0])
		var button := _button(str(entry[1]), entry[2], 22)
		button.name = action.capitalize() + "TouchButton"
		# Three-character move names must remain readable on 568 CSS-pixel
		# landscape displays without inflating their reserved control strip.
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := button.get_theme_stylebox(state) as StyleBoxFlat
			style.content_margin_left = 6
			style.content_margin_right = 6
		button.set_meta("duel_action", action)
		button.focus_mode = Control.FOCUS_NONE
		button.button_down.connect(_emit_command.bind(action, true))
		button.button_up.connect(_emit_command.bind(action, false))
		_touch_inner.add_child(button)
		_touch_buttons[action] = button
	_special_cooldown_overlay = ColorRect.new()
	_special_cooldown_overlay.name = "SignatureCooldownOverlay"
	_special_cooldown_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_buttons["special"].add_child(_special_cooldown_overlay)
	_touch_buttons["special"].resized.connect(_layout_special_cooldown)
	for caption in ["上跳 · 下蹲 · 斜跳", "拳击 / 腿法 / 专属波", "方向键 / WASD · 空格", "J       K       L       I       O"]:
		var label := _label(caption, 12, DIM)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_touch_inner.add_child(label)
		_touch_labels.append(label)
	_set_special_status(0, 0.0)

func _set_special_status(kind: int, remaining: float) -> void:
	_special_kind = Characters.valid_kind(kind)
	_special_cd = clampf(remaining, 0.0, SPECIAL_COOLDOWN)
	if not _touch_buttons.has("special"):
		return
	var button: Button = _touch_buttons["special"]
	var caption:String = Characters.get_character(_special_kind).special_label
	var color:Color = Characters.get_character(_special_kind).color
	if is_instance_valid(_desktop_help):
		_desktop_help.text = "A/D 移动　W/空格 跳跃　S 下蹲　方向键 / WASD　J 连拳　K 飞踢　L 重拳　I 回旋踢\nO %s%s　Esc 暂停　F11 / Alt+Enter Fullscreen" % [caption, " · %.1fs" % (ceilf(_special_cd * 10.0) / 10.0) if _special_cd > 0.0 else " · Ready"]
	button.text = caption + ("\n%.1fs" % (ceilf(_special_cd * 10.0) / 10.0) if _special_cd > 0.0 else "")
	button.tooltip_text = "%s · O · 冷却 4 秒" % caption
	button.disabled = _special_cd > 0.0
	var ready_font_size := 16 if not _portrait and gameplay_height_ratio() > 0.85 else maxi(14, int(20.0 * _scale))
	button.add_theme_font_size_override("font_size", 13 if button.disabled else ready_font_size)
	# A snapshot arrives every rendered frame; build theme resources only when
	# the selected character actually changes, not on every cooldown tick.
	if int(button.get_meta("signature_style_kind", -1)) != _special_kind:
		button.set_meta("signature_style_kind", _special_kind)
		button.set_meta("normal_font_color", color)
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_disabled_color", color.lerp(DIM, 0.55))
		var normal := _style(Color("241b30"), color.darkened(0.45), 10, 1)
		var hover := _style(Color("35243f"), color, 10, 2)
		var pressed := _style(color, WHITE, 10, 2)
		var disabled := _style(Color("181420"), color.darkened(0.65), 10, 1)
		for style in [normal, hover, pressed, disabled]:
			style.content_margin_left = 6
			style.content_margin_right = 6
		button.set_meta("normal_style", normal)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("disabled", disabled)
	if bool(_sent_actions.get("special", false)) and not button.disabled:
		_touch_highlight(button, true)
	_special_cooldown_overlay.color = Color(color, 0.65)
	_special_cooldown_overlay.visible = button.disabled
	_layout_special_cooldown()

func _layout_special_cooldown() -> void:
	if not is_instance_valid(_special_cooldown_overlay):
		return
	var button: Button = _touch_buttons["special"]
	_special_cooldown_overlay.position = Vector2(6.0, button.size.y - 5.0)
	_special_cooldown_overlay.size = Vector2(maxf(0.0, button.size.x - 12.0) * _special_cd / SPECIAL_COOLDOWN, 2.0)

func _build_menu() -> void:
	_menu_overlay = _overlay()
	_menu_card = _card(_menu_overlay, PURPLE)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	_menu_stack = stack
	_menu_padding = _margin(stack, 24, 22)
	_menu_card.add_child(_menu_padding)
	var eyebrow := _label("TONIGHT / UNDERGROUND STAGE", 12, YELLOW)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(eyebrow)
	var title := _label("决战日不落之巅", 30, WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	_menu_tagline=_center_label("灯光就位。选一位偶像，守住你的舞台。", 15, DIM)
	stack.add_child(_menu_tagline)
	var choices := GridContainer.new()
	_choices_grid = choices
	choices.columns = Characters.COUNT
	choices.add_theme_constant_override("h_separation", 10)
	choices.add_theme_constant_override("v_separation", 10)
	stack.add_child(choices)
	for kind in range(Characters.COUNT):
		var character:Dictionary=Characters.get_character(kind)
		var choice:=_button(str(character.name)+"\n"+str(character.english),character.color,21)
		choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		choice.custom_minimum_size.y=100
		choice.pressed.connect(_choose.bind(kind));choices.add_child(choice);_choice_buttons.append(choice)
	_opponent_button=_button("对手：随机 · 点击切换",DIM,14)
	_opponent_button.custom_minimum_size.y=44
	_opponent_button.pressed.connect(_cycle_opponent)
	stack.add_child(_opponent_button)
	_keyboard_help = _center_label("键盘：方向键 / WASD 移动、跳跃、下蹲　空格跳跃\nJ 连拳　K 飞踢　L 重拳　I 回旋踢　O 专属波", 14, WHITE)
	if desktop_controls():
		_keyboard_help.text += "\nEsc 暂停　F11 / Alt+Enter Fullscreen"
	stack.add_child(_keyboard_help)
	_menu_tip=_center_label("拳击收招时再按，可接第二拳；重拳前摇更长", 14, DIM)
	stack.add_child(_menu_tip)
	_menu_footer = HBoxContainer.new()
	_menu_footer.add_theme_constant_override("separation", 10)
	stack.add_child(_menu_footer)
	var footer_help := _center_label("左侧上跳、下蹲，斜上斜跳；空中可左右调整\n地面后退防守 · 先赢 2 局 · 每局 60 秒", 14, DIM)
	footer_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_menu_footer.add_child(footer_help)

func _build_result() -> void:
	_result_overlay = _overlay()
	_result_card = _card(_result_overlay, YELLOW)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	_result_card.add_child(_margin(stack, 26, 24))
	stack.add_child(_center_label("LIVEHOUSE / ENCORE", 13, YELLOW))
	_result_title = _center_label("胜负已分", 32, WHITE)
	stack.add_child(_result_title)
	stack.add_child(_center_label("属于今晚的舞台，已经留下你的名字。", 14, DIM))
	var replay := _button("再战一场", YELLOW, 20)
	replay.custom_minimum_size.y = 56
	replay.pressed.connect(_request_rematch)
	stack.add_child(replay)
	var menu := _button("重选偶像", PURPLE, 17)
	menu.custom_minimum_size.y = 48
	menu.pressed.connect(func(): menu_requested.emit())
	stack.add_child(menu)
	_result_overlay.hide()

func _build_pause() -> void:
	_pause_overlay = _overlay()
	_pause_card = _card(_pause_overlay, PURPLE)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 15)
	_pause_card.add_child(_margin(stack, 28, 25))
	stack.add_child(_center_label("稍息，灯光还在。", 27, WHITE))
	stack.add_child(_center_label("比赛已暂停", 14, DIM))
	var resume := _button("回到舞台", PURPLE, 20)
	resume.custom_minimum_size.y = 54
	resume.pressed.connect(func(): pause_requested.emit())
	stack.add_child(resume)
	var menu := _button("返回选角", DIM, 17)
	menu.custom_minimum_size.y = 44
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func(): menu_requested.emit())
	_pause_actions = HBoxContainer.new()
	_pause_actions.add_theme_constant_override("separation", 8)
	stack.add_child(_pause_actions)
	_pause_actions.add_child(menu)
	_pause_overlay.hide()

func _build_feedback_settings() -> void:
	# Append these after all legacy buttons to preserve their stable ordering.
	_menu_settings_button = _button("反馈设置", DIM, 16)
	_menu_settings_button.custom_minimum_size = Vector2(96, 44)
	_menu_settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_menu_settings_button.pressed.connect(_open_feedback_settings)
	_menu_footer.add_child(_menu_settings_button)
	_pause_settings_button = _button("反馈设置", PURPLE, 17)
	_pause_settings_button.custom_minimum_size.y = 44
	_pause_settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_settings_button.pressed.connect(_open_feedback_settings)
	_pause_actions.add_child(_pause_settings_button)
	_settings_overlay = _overlay()
	_settings_overlay.name = "FeedbackSettingsOverlay"
	_settings_card = _card(_settings_overlay, PURPLE)
	_settings_card.name = "FeedbackSettingsCard"
	_settings_inner = Control.new()
	_settings_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_card.add_child(_settings_inner)
	_settings_title = _center_label("反馈设置", 24, WHITE)
	_settings_inner.add_child(_settings_title)
	_settings_hint = _center_label("独立调节音量 · 不影响战斗规则", 14, DIM)
	_settings_inner.add_child(_settings_hint)
	_combat_volume_label = _label("", 16, PURPLE)
	_settings_inner.add_child(_combat_volume_label)
	_combat_volume_slider = _feedback_slider("CombatVolumeSlider", PURPLE)
	_combat_volume_slider.value_changed.connect(_feedback_volume_changed.bind(false))
	_voice_volume_label = _label("", 16, YELLOW)
	_settings_inner.add_child(_voice_volume_label)
	_voice_volume_slider = _feedback_slider("VoiceVolumeSlider", YELLOW)
	_voice_volume_slider.value_changed.connect(_feedback_volume_changed.bind(true))
	_shake_button = _button("", PURPLE, 16)
	_shake_button.name = "CameraShakeToggle"
	_shake_button.focus_mode = Control.FOCUS_ALL
	_shake_button.pressed.connect(_toggle_feedback_shake)
	_settings_inner.add_child(_shake_button)
	_settings_back_button = _button("返回", WHITE, 16)
	_settings_back_button.name = "FeedbackSettingsBack"
	_settings_back_button.focus_mode = Control.FOCUS_ALL
	_settings_back_button.pressed.connect(_close_feedback_settings)
	_settings_inner.add_child(_settings_back_button)
	set_feedback_settings(_combat_gain, _voice_gain, _shake_enabled)
	_settings_overlay.hide()

func _feedback_slider(node_name: String, color: Color) -> HSlider:
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.custom_minimum_size = Vector2(44, 44)
	slider.focus_mode = Control.FOCUS_ALL
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.scrollable = false
	slider.tooltip_text = "0–100% · 拖动调节，方向键微调"
	slider.add_theme_stylebox_override("slider", _style(Color("463451"), Color.TRANSPARENT, 4, 0))
	slider.add_theme_stylebox_override("grabber_area", _style(color.darkened(0.25), Color.TRANSPARENT, 4, 0))
	slider.add_theme_stylebox_override("grabber_area_highlight", _style(color, Color.TRANSPARENT, 4, 0))
	# Native focus remains keyboard-accessible, while actual pointer ownership
	# is handled with the same explicit mouse/touch model as the direction pad.
	_settings_inner.add_child(slider)
	return slider

func _layout_feedback_settings(viewport_size: Vector2) -> void:
	var wide := viewport_size.y < 360.0 and viewport_size.x > viewport_size.y
	var card_width := minf(viewport_size.x - 24.0, 544.0 if wide else 460.0)
	var card_height := 206.0 if wide else 350.0
	_settings_inner.custom_minimum_size = Vector2(0.0, card_height - 6.0)
	_settings_card.size = Vector2(card_width, card_height)
	_settings_card.position = (viewport_size - _settings_card.size) / 2.0
	var inset := 12.0
	var width := card_width - 18.0 - inset * 2.0
	_place_settings(_settings_title, Rect2(inset, 8, width, 30))
	_place_settings(_settings_hint, Rect2(inset, 40, width, 22))
	if wide:
		var column := (width - 20.0) / 2.0
		_place_settings(_combat_volume_label, Rect2(inset, 68, column, 24))
		_place_settings(_combat_volume_slider, Rect2(inset, 92, column, 44))
		_place_settings(_voice_volume_label, Rect2(inset + column + 20, 68, column, 24))
		_place_settings(_voice_volume_slider, Rect2(inset + column + 20, 92, column, 44))
		_place_settings(_shake_button, Rect2(inset, 148, width - 112, 44))
		_place_settings(_settings_back_button, Rect2(inset + width - 100, 148, 100, 44))
	else:
		_place_settings(_combat_volume_label, Rect2(inset, 72, width, 24))
		_place_settings(_combat_volume_slider, Rect2(inset, 96, width, 44))
		_place_settings(_voice_volume_label, Rect2(inset, 152, width, 24))
		_place_settings(_voice_volume_slider, Rect2(inset, 176, width, 44))
		_place_settings(_shake_button, Rect2(inset, 236, width, 44))
		_place_settings(_settings_back_button, Rect2(inset, 292, width, 44))
	for control in [_menu_settings_button, _pause_settings_button, _settings_hint, _combat_volume_label, _voice_volume_label, _shake_button, _settings_back_button]:
		control.add_theme_font_size_override("font_size", 14 if wide else 16)
	_settings_title.add_theme_font_size_override("font_size", 22)

func _place_settings(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size

func _resize() -> void:
	if not is_instance_valid(_root):
		return
	var size := get_viewport().get_visible_rect().size
	_portrait = size.y > size.x
	_keyboard_help.visible = desktop_controls() or (not _portrait and size.x >= 960.0 and size.y >= 540.0)
	_scale = clampf(size.x / 700.0, 0.72, 1.25) if _portrait else clampf(size.y / 650.0, 0.72, 1.18)
	for control in _font_controls:
		var font_scale := (0.90 if _portrait else 1.0) if _match_panel.is_ancestor_of(control) else _scale
		control.add_theme_font_size_override("font_size", maxi(10, int(float(control.get_meta("base_font_size")) * font_scale)))
	for button: Button in _touch_buttons.values():
		var font_size := 16 if not _portrait and gameplay_height_ratio() > 0.85 else maxi(14, int(20.0 * _scale))
		button.add_theme_font_size_override("font_size", 13 if button.get_meta("duel_action") == "special" and _special_cd > 0.0 else font_size)
	_clear_touches()
	var compact := not _portrait and size.y < 520.0
	var short_landscape := not _portrait and size.y < 360.0
	_menu_tagline.visible=not short_landscape
	_menu_tip.visible=not short_landscape
	_menu_stack.add_theme_constant_override("separation", 5 if short_landscape else (7 if compact else int(14 * _scale)))
	_menu_padding.add_theme_constant_override("margin_top", 8 if short_landscape else (10 if compact else int(22 * _scale)))
	_menu_padding.add_theme_constant_override("margin_bottom", 8 if short_landscape else (10 if compact else int(22 * _scale)))
	_choices_grid.columns = 2 if _portrait else Characters.COUNT
	_choices_grid.add_theme_constant_override("h_separation", 8 if short_landscape else 10)
	_choices_grid.add_theme_constant_override("v_separation", 8 if _portrait else 10)
	for choice in _choice_buttons:
		# Five roles share one row on short landscape; keep every touch target
		# while fitting the longest English subtitle within the compact card.
		if short_landscape: choice.add_theme_font_size_override("font_size", 14)
		choice.custom_minimum_size.y = 52.0 if short_landscape else (58.0 if compact else 100.0 * _scale)
	_compact_overlay(_result_card, short_landscape, 18, 24, [56.0, 48.0])
	_compact_overlay(_pause_card, short_landscape, 15, 25, [54.0, 46.0])
	var edge := 9.0 * _scale
	_match_panel.position = Vector2(edge, edge)
	_match_panel.size = Vector2(size.x - 2.0 * edge, 0)
	_match_panel.reset_size()
	_match_panel.size.x = size.x - 2.0 * edge
	var ratio := gameplay_height_ratio()
	var status_height := maxf(24.0 if _portrait else 20.0, _status.get_combined_minimum_size().y)
	_status.position = Vector2(12.0, size.y * ratio - status_height - 3.0)
	_status.size = Vector2(size.x - 24.0, status_height)
	_touch_panel.position = Vector2(0, size.y * ratio)
	_touch_panel.size = Vector2(size.x, size.y * (1.0 - ratio))
	_layout_touch(size.x, size.y * (1.0 - ratio))
	_desktop_help.position = Vector2(8.0, size.y - 50.0)
	_desktop_help.size = Vector2(size.x - 16.0, 48.0)
	_desktop_help.add_theme_font_size_override("font_size", 14 if size.x >= 1100.0 else 12)
	_fit_card(_menu_card, size, 750.0 * _scale)
	_fit_card(_result_card, size, 540.0 * _scale)
	_fit_card(_pause_card, size, 450.0 * _scale)
	_layout_feedback_settings(size)
	call_deferred("_center_cards")

func _queue_overlay_layout() -> void:
	if not get_tree().process_frame.is_connected(_resize):
		get_tree().process_frame.connect(_resize, CONNECT_ONE_SHOT)

func _center_cards() -> void:
	var size := get_viewport().get_visible_rect().size
	for card in [_menu_card, _result_card, _pause_card, _settings_card]:
		card.position = (size - card.size) / 2.0

func _layout_touch(width: float, height: float) -> void:
	var desktop := not _portrait and gameplay_height_ratio() > 0.85
	var available_width := width
	var horizontal_offset := 0.0
	if desktop:
		width = minf(width, 840.0)
		horizontal_offset = (available_width - width) / 2.0
	# Mobile landscape is still a touch layout, never a reason to show hotkeys.
	var show_keys := desktop and height >= 85.0
	_touch_labels[2].visible = show_keys
	_touch_labels[3].visible = show_keys
	_touch_x_offset = horizontal_offset
	var pad := 12.0 * _scale
	var gap := 8.0 * _scale
	var action_left := width * (0.43 if _portrait else 0.36)
	var action_area_width := width - action_left - pad
	var heading_y := 5.0 if _portrait else 3.0
	var top := 24.0 if _portrait else 22.0
	for label: Label in _touch_labels:
		label.add_theme_font_size_override("font_size", 11 if desktop else 10)
	var bottom := 19.0 if show_keys else 4.0
	var row_height := maxf(48.0, minf(72.0, (height - top - bottom - gap - 6.0) / 2.0)) if _portrait else maxf(48.0, minf(58.0, height - top - bottom))
	var grid_height := row_height * 2.0 + gap if _portrait else row_height
	var grid_y := top + maxf(0.0, (height - top - bottom - grid_height) * 0.5)
	if _portrait:
		var action_width := (action_area_width - gap * 2.0) / 3.0
		for n in range(3):
			_place_touch(ATTACK_ACTIONS[n], Rect2(action_left + (action_width + gap) * n, grid_y, action_width, row_height))
		var lower_width := (action_area_width - gap) / 2.0
		for n in range(2):
			_place_touch(ATTACK_ACTIONS[n + 3], Rect2(action_left + (lower_width + gap) * n, grid_y + row_height + gap, lower_width, row_height))
	else:
		var action_width := (action_area_width - gap * 4.0) / 5.0
		for n in range(5):
			_place_touch(ATTACK_ACTIONS[n], Rect2(action_left + (action_width + gap) * n, grid_y, action_width, row_height))
	# A 68 px continuous pad also fits 568×267 without stealing any stage
	# height. Portrait has room for a 128 px pad. The whole square is a hit
	# target; the arrows are visual guides, not sub-44 px clickable buttons.
	var direction_width := action_left - pad - gap
	var side := minf(128.0, minf(direction_width, height - top - bottom - 4.0)) if _portrait else minf(76.0, height - (24.0 if show_keys else 8.0))
	var direction_x := pad + (direction_width - side) * 0.5 if _portrait else pad
	var direction_y := grid_y + (grid_height - side) * 0.5 if _portrait else (height - bottom - side) * 0.5
	_direction_pad.position = Vector2(direction_x + horizontal_offset, direction_y)
	_direction_pad.size = Vector2.ONE * side
	_update_joystick_visual()
	var cells := {"jump": Vector2(1, 0), "left": Vector2(0, 1), "center": Vector2(1, 1), "right": Vector2(2, 1), "crouch": Vector2(1, 2)}
	for action in cells:
		var glyph: Label = _direction_glyphs[action]
		glyph.position = cells[action] * (side / 3.0)
		glyph.size = Vector2.ONE * (side / 3.0)
		glyph.add_theme_font_size_override("font_size", 21 if side >= 100.0 else 15)
	_touch_labels[0].text = "上跳 · 下蹲 · 斜跳" if _portrait else "上跳 · 下蹲\n斜上可斜跳"
	_touch_labels[0].position = Vector2(pad + horizontal_offset, heading_y) if _portrait else Vector2(direction_x + side + 6.0 + horizontal_offset, maxf(3.0, (height - bottom - 38.0) * 0.5))
	_touch_labels[0].size = Vector2(direction_width, 18.0) if _portrait else Vector2(maxf(0.0, action_left - direction_x - side - 12.0), 38.0)
	_touch_labels[1].position = Vector2(action_left + horizontal_offset, heading_y)
	_touch_labels[1].size = Vector2(action_area_width, 16.0)
	_touch_labels[2].position = Vector2(pad + horizontal_offset, height - 19.0)
	_touch_labels[2].size = Vector2(direction_width, 17.0)
	_touch_labels[3].position = Vector2(action_left + horizontal_offset, height - 19.0)
	_touch_labels[3].size = Vector2(action_area_width, 17.0)

func _place_touch(action: String, rect: Rect2) -> void:
	var button: Button = _touch_buttons[action]
	button.position = rect.position + Vector2(_touch_x_offset, 0)
	button.size = rect.size
	if action == "special":
		_layout_special_cooldown()

func _compact_overlay(card: PanelContainer, compact: bool, separation: int, vertical_padding: int, button_heights: Array) -> void:
	# Only shrink spacing/targets on very short landscape displays; retain every
	# result and pause action, and restore the regular layout after rotation.
	var padding := card.get_child(0) as MarginContainer
	var stack := padding.get_child(0) as VBoxContainer
	padding.add_theme_constant_override("margin_top", 10 if compact else vertical_padding)
	padding.add_theme_constant_override("margin_bottom", 10 if compact else vertical_padding)
	stack.add_theme_constant_override("separation", 8 if compact else separation)
	var index := 0
	for child in stack.get_children():
		if child is Button:
			child.custom_minimum_size.y = 44.0 if compact else float(button_heights[index])
			index += 1

func _fit_card(card: PanelContainer, viewport_size: Vector2, wanted_width: float) -> void:
	card.size = Vector2(minf(viewport_size.x - 24.0, wanted_width), 0)
	card.reset_size()
	card.size.x = minf(viewport_size.x - 24.0, wanted_width)
	card.position = (viewport_size - card.size) / 2.0

func opponent_for(character:int) -> int:
	return -1 if opponent_choice<0 or opponent_choice>=Characters.COUNT or opponent_choice==character else opponent_choice

func _cycle_opponent() -> void:
	set_opponent_choice(opponent_choice+1 if opponent_choice+1<Characters.COUNT else -1)

func set_opponent_choice(choice:int) -> void:
	opponent_choice=choice if choice>=0 and choice<Characters.COUNT else -1
	_opponent_button.text="对手："+("随机" if opponent_choice<0 else str(Characters.get_character(opponent_choice).name))+" · 点击切换"
	_queue_overlay_layout()

func _choose(character: int) -> void:
	_clear_touches()
	_hide_feedback_settings()
	_set_fighter_identity(0, character)
	set_opponent_choice(opponent_for(character))
	# Main resolves random once after selected.emit; never draw during UI rendering.
	_set_special_status(character, 0.0)
	_menu_open = false
	_result_open = false
	_paused = false
	_menu_overlay.hide()
	_result_overlay.hide()
	_pause_overlay.hide()
	_update_visibility()
	selected.emit(character)

func _request_rematch() -> void:
	_clear_touches()
	_hide_feedback_settings()
	_set_special_status(_special_kind, 0.0)
	_result_open = false
	_result_overlay.hide()
	_update_visibility()
	rematch_requested.emit()

func _gameplay_controls_active() -> bool:
	return not desktop_controls() and not _menu_open and not _paused and not _result_open and not _settings_open

func _emit_command(action: String, pressed: bool) -> void:
	if pressed and not _gameplay_controls_active():
		return
	_mouse_held[action] = pressed
	_sync_action(action)

func _sync_action(action: String) -> void:
	var held := bool(_mouse_held.get(action, false)) or int(_touch_action_counts.get(action, 0)) > 0
	if action == "special":
		if not held:
			_special_input_blocked = false
		elif _special_cd > 0.0 and not bool(_sent_actions.get(action, false)):
			_special_input_blocked = true
		# Cooldown expiry never converts an old hold into a fresh input edge.
		if _special_input_blocked:
			held = false
	if held != bool(_sent_actions.get(action, false)):
		_sent_actions[action] = held
		command.emit(action, held)
	if _touch_buttons.has(action):
		var button: Button = _touch_buttons[action]
		_touch_highlight(button, held and not button.disabled)
	if _direction_glyphs.has(action):
		var glyph: Label = _direction_glyphs[action]
		glyph.add_theme_color_override("font_color", WHITE if held else PURPLE)

func _update_joystick_visual() -> void:
	if not is_instance_valid(_joystick_nub): return
	var side: float = minf(_direction_pad.size.x, _direction_pad.size.y)
	_joystick_nub.size = Vector2.ONE * side * 0.36
	_joystick_nub.position = (_direction_pad.size - _joystick_nub.size) * 0.5 + _joystick_vector * side * 0.32
	_joystick_nub.modulate = WHITE if _joystick_touch_id >= 0 or _mouse_direction_active else Color("c7b6d6")

func _reset_joystick() -> void:
	_joystick_vector = Vector2.ZERO
	_joystick_actions.clear()
	_update_joystick_visual()

func _direction_actions_at(position: Vector2) -> Array:
	var result: Array = []
	if not _gameplay_controls_active():
		_reset_joystick()
		return result
	var radius: float = maxf(1.0, minf(_direction_pad.size.x, _direction_pad.size.y) * 0.5)
	var displacement: Vector2 = (position - _direction_pad.get_global_rect().get_center()) / radius
	# Captured owner may drag beyond the fixed base: clamp the nub, do not
	# transfer its contact into an attack. Release/cancel always recenters.
	_joystick_vector = displacement.limit_length(1.0)
	var dead: float = JOYSTICK_DEAD_EXIT if not _joystick_actions.is_empty() else JOYSTICK_DEAD_ENTER
	if displacement.length() >= dead:
		var x: float = _joystick_vector.x
		var y: float = _joystick_vector.y
		if x < -(JOYSTICK_AXIS_EXIT if "left" in _joystick_actions else JOYSTICK_AXIS_ENTER): result.append("left")
		elif x > (JOYSTICK_AXIS_EXIT if "right" in _joystick_actions else JOYSTICK_AXIS_ENTER): result.append("right")
		if y > (JOYSTICK_AXIS_EXIT if "crouch" in _joystick_actions else JOYSTICK_AXIS_ENTER): result.append("crouch")
		elif y < -(JOYSTICK_AXIS_EXIT if "jump" in _joystick_actions else JOYSTICK_AXIS_ENTER): result.append("jump")
	_joystick_actions = result.duplicate()
	_update_joystick_visual()
	return result

func _set_touch_directions(index: int, actions: Array) -> void:
	var contact: Dictionary = _touch_contacts[index]
	var previous: Array = contact.get("actions", [])
	contact["actions"] = actions
	for action in DIRECTION_ACTIONS:
		var change := int(action in actions) - int(action in previous)
		if change != 0:
			_touch_action_counts[action] = maxi(0, int(_touch_action_counts.get(action, 0)) + change)
	# Commit all counts before emitting any signal, so one callback cannot
	# observe a half-written diagonal and held up never generates repeats.
	for action in DIRECTION_ACTIONS:
		_sync_action(action)

func _set_mouse_directions(actions: Array) -> void:
	_mouse_direction_actions = actions
	for action in DIRECTION_ACTIONS:
		_mouse_held[action] = action in actions
	for action in DIRECTION_ACTIONS:
		_sync_action(action)

func _input(event: InputEvent) -> void:
	# Fullscreen remains available even while settings owns keyboard focus.
	if desktop_controls() and event is InputEventKey and (event.physical_keycode == KEY_F11 or (event.alt_pressed and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER])):
		return
	if _settings_open and event is InputEventKey:
		# Do not leak slider arrows, space or action hotkeys into the match.
		# Explicit handling also keeps Escape as Back, never accidental resume.
		if event.pressed:
			var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			var focus := get_viewport().gui_get_focus_owner()
			if key == KEY_ESCAPE:
				_close_feedback_settings()
			elif focus is HSlider:
				if key in [KEY_LEFT, KEY_DOWN]:
					focus.value -= 1.0
				elif key in [KEY_RIGHT, KEY_UP]:
					focus.value += 1.0
				elif key == KEY_HOME:
					focus.value = 0.0
				elif key == KEY_END:
					focus.value = 100.0
			elif focus is Button and key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and not event.echo:
				focus.pressed.emit()
			if key == KEY_TAB:
				var controls: Array[Control] = [_combat_volume_slider, _voice_volume_slider, _shake_button, _settings_back_button]
				var next := posmod(controls.find(focus) + (-1 if event.shift_pressed else 1), controls.size())
				controls[next].grab_focus()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and not touch.canceled:
			if _touch_contacts.has(touch.index):
				_end_touch(touch.index, touch.position, false)
			var slider := _settings_slider_at(touch.position)
			if slider:
				_touch_contacts[touch.index] = {"kind": "slider", "slider": slider}
				_set_slider_position(slider, touch.position)
				get_viewport().set_input_as_handled()
				return
			if _gameplay_controls_active() and _direction_pad.get_global_rect().has_point(touch.position):
				# A second pad finger cannot steal or merge opposite directions.
				if _joystick_touch_id >= 0 or _mouse_direction_active:
					get_viewport().set_input_as_handled()
					return
				_joystick_touch_id = touch.index
				_touch_contacts[touch.index] = {"kind": "direction", "actions": []}
				_set_touch_directions(touch.index, _direction_actions_at(touch.position))
				get_viewport().set_input_as_handled()
				return
			var button := _touch_button_at(touch.position)
			if button != null:
				var action := str(button.get_meta("duel_action", ""))
				_touch_contacts[touch.index] = {"kind": "button", "button": button, "action": action}
				if not action.is_empty():
					_touch_action_counts[action] = int(_touch_action_counts.get(action, 0)) + 1
					_sync_action(action)
				else:
					_touch_highlight(button, true)
				get_viewport().set_input_as_handled()
		elif _touch_contacts.has(touch.index):
			_end_touch(touch.index, touch.position, not touch.canceled)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touch_contacts.has(drag.index):
			var contact: Dictionary = _touch_contacts[drag.index]
			if contact["kind"] == "direction":
				# Captured joystick contact stays directional outside its base.
				_set_touch_directions(drag.index, _direction_actions_at(drag.position))
			elif contact["kind"] == "slider":
				_set_slider_position(contact["slider"], drag.position)
			else:
				var button: Button = contact["button"]
				if not button.get_global_rect().has_point(drag.position):
					_end_touch(drag.index, drag.position, false)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := event as InputEventMouseButton
		var slider := _settings_slider_at(mouse.position)
		if mouse.pressed and slider:
			_mouse_settings_slider = slider
			_set_slider_position(slider, mouse.position)
			get_viewport().set_input_as_handled()
		elif not mouse.pressed and is_instance_valid(_mouse_settings_slider):
			_mouse_settings_slider = null
			get_viewport().set_input_as_handled()
		elif mouse.pressed and _gameplay_controls_active() and _direction_pad.get_global_rect().has_point(mouse.position):
			if _joystick_touch_id >= 0:
				get_viewport().set_input_as_handled()
				return
			_mouse_direction_active = true
			_set_mouse_directions(_direction_actions_at(mouse.position))
			get_viewport().set_input_as_handled()
		elif not mouse.pressed and _mouse_direction_active:
			_mouse_direction_active = false
			_set_mouse_directions([])
			_reset_joystick()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and is_instance_valid(_mouse_settings_slider):
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_set_slider_position(_mouse_settings_slider, event.position)
		else:
			_mouse_settings_slider = null
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _mouse_direction_active:
		var mouse := event as InputEventMouseMotion
		if mouse.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_set_mouse_directions(_direction_actions_at(mouse.position))
		else:
			_mouse_direction_active = false
			_set_mouse_directions([])
			_reset_joystick()
		get_viewport().set_input_as_handled()

func _settings_slider_at(position: Vector2) -> HSlider:
	if _settings_open:
		for slider: HSlider in [_combat_volume_slider, _voice_volume_slider]:
			if slider.get_global_rect().has_point(position):
				return slider
	return null

func _set_slider_position(slider: HSlider, position: Vector2) -> void:
	var thumb_half := slider.get_theme_icon("grabber").get_width() * 0.5
	var travel := maxf(1.0, slider.size.x - thumb_half * 2.0)
	slider.value = clampf((position.x - slider.global_position.x - thumb_half) / travel, 0.0, 1.0) * 100.0
	slider.grab_focus()

func _touch_button_at(position: Vector2) -> Button:
	var active_root: Control = _root
	if _settings_open:
		active_root = _settings_overlay
	elif _menu_open:
		active_root = _menu_overlay
	elif _result_open:
		active_root = _result_overlay
	elif _paused:
		active_root = _pause_overlay
	for i in range(_buttons.size() - 1, -1, -1):
		var button := _buttons[i]
		if button.is_visible_in_tree() and not button.disabled and active_root.is_ancestor_of(button) and button.get_global_rect().has_point(position):
			return button
	return null

func _end_touch(index: int, release_position: Vector2, activate: bool) -> void:
	if not _touch_contacts.has(index):
		return
	var contact: Dictionary = _touch_contacts[index]
	if contact["kind"] == "slider":
		_touch_contacts.erase(index)
		return
	if contact["kind"] == "direction":
		_set_touch_directions(index, [])
		_touch_contacts.erase(index)
		_joystick_touch_id = -1
		_reset_joystick()
		return
	var button: Button = contact["button"]
	var action := str(contact["action"])
	_touch_contacts.erase(index)
	if not action.is_empty():
		_touch_action_counts[action] = maxi(0, int(_touch_action_counts.get(action, 0)) - 1)
		_sync_action(action)
	else:
		var still_pressed := false
		for other: Dictionary in _touch_contacts.values():
			if other.get("button") == button:
				still_pressed = true
				break
		_touch_highlight(button, still_pressed)
		if activate and button.get_global_rect().has_point(release_position):
			button.pressed.emit()

func _clear_touches() -> void:
	for index in _touch_contacts.keys():
		_end_touch(int(index), Vector2(-1, -1), false)
	_mouse_direction_active = false
	_mouse_settings_slider = null
	_mouse_direction_actions.clear()
	_joystick_touch_id = -1
	_reset_joystick()
	for action in _mouse_held.keys():
		_mouse_held[action] = false
		_sync_action(str(action))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_touches()

func _touch_highlight(button: Button, pressed: bool) -> void:
	button.add_theme_stylebox_override("normal", button.get_theme_stylebox("pressed") if pressed else button.get_meta("normal_style"))
	button.add_theme_color_override("font_color", INK if pressed else button.get_meta("normal_font_color"))

func _update_visibility() -> void:
	_touch_panel.visible = not desktop_controls() and not _menu_open and not _result_open
	_desktop_help.visible = desktop_controls() and not _menu_open and not _result_open and not _paused
	_match_panel.visible = not _menu_open
	_touch_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _overlay() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.025, 0.012, 0.05, 0.91)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(overlay)
	return overlay

func _card(parent: Control, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL, color.darkened(0.45), 18, 2))
	parent.add_child(panel)
	return panel

func _margin(content: Control, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	margin.add_child(content)
	return margin

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	_register_font(label, font_size)
	return label

func _center_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, color: Color, font_size: int = 18) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_stylebox_override("normal", _style(Color("241b30"), color.darkened(0.45), 10, 1))
	button.add_theme_stylebox_override("hover", _style(Color("35243f"), color, 10, 2))
	button.add_theme_stylebox_override("pressed", _style(color, WHITE, 10, 2))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, WHITE, 10, 2))
	button.set_meta("normal_style", button.get_theme_stylebox("normal"))
	button.set_meta("normal_font_color", color)
	_buttons.append(button)
	_register_font(button, font_size)
	return button

func _register_font(control: Control, base: int) -> void:
	control.set_meta("base_font_size", base)
	control.add_theme_font_size_override("font_size", base)
	_font_controls.append(control)

func _style(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style

func _without_padding(style: StyleBoxFlat) -> StyleBoxFlat:
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style
