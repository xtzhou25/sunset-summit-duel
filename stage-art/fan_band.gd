extends Control
## Single bounded custom draw; no lights, physics, textures or per-frame nodes.
const FAN_COUNT := 28
const COLORS := [Color("a18bc3"), Color("c6af79"), Color("88aec4"), Color("c691a4"), Color("c39770")]
var clock := 0.0
var scroll := 0.0
var band_top := 0.0
var band_bottom := 0.0
var _upper_arms := PackedVector2Array()
var _lower_arms := PackedVector2Array()
var _sticks := PackedVector2Array()
var _ink_colors := PackedColorArray()
var _halo_colors := PackedColorArray()
var _stick_colors := PackedColorArray()
var _body_outline := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

func _ready() -> void:
	name = "ClippedFanSilhouettes"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_upper_arms.resize(FAN_COUNT * 2)
	_lower_arms.resize(FAN_COUNT * 2)
	_sticks.resize(FAN_COUNT * 2)
	_ink_colors.resize(FAN_COUNT)
	_halo_colors.resize(FAN_COUNT)
	_stick_colors.resize(FAN_COUNT)

func update_view(camera: Camera3D, gameplay_bottom: float) -> void:
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var ground := camera.unproject_position(Vector3(0, 0, 0)).y
	# The frontmost floor edge is lower than fighter ground; neither feet nor warning
	# decals may enter the band. A slim clear apron remains visible above the heads.
	band_top = maxf(ground + 5.0, gameplay_bottom - 70.0)
	band_bottom = minf(gameplay_bottom - 2.0, viewport_size.y)
	position = Vector2(0, band_top)
	size = Vector2(viewport_size.x, maxf(0.0, band_bottom - band_top))
	visible = size.y >= 8.0
	scroll = camera.position.x * viewport_size.x / maxf(camera.size, 1.0) * 1.12
	queue_redraw()

func advance(delta: float) -> void:
	clock += delta
	if delta > 0.0 and visible:
		queue_redraw()

func _draw() -> void:
	if size.y < 8.0:
		return
	var height := size.y
	var spacing := size.x / float(FAN_COUNT - 2)
	var drift := fposmod(scroll, spacing * float(FAN_COUNT))
	var ux := minf(spacing / 17.0, 1.65)
	var uy := height / 45.0
	for i in range(FAN_COUNT):
		# Wrapping only outside the clipped edges; stable identity/phase as camera moves.
		var x := fposmod(float(i) * spacing - drift, spacing * float(FAN_COUNT)) - spacing
		var phase := float(i) * 2.39996
		var radius := clampf(3.8 * minf(ux, uy), 1.8, 6.0)
		var head := Vector2(x, height - (17.0 + float(i % 3)) * uy)
		var ink := Color("191d2b") if i % 3 else Color("232636")
		draw_circle(head, radius, ink)
		var shoulder := head + Vector2(0, radius + 2.0 * uy)
		_body_outline[0] = shoulder + Vector2(-5.0 * ux, 0)
		_body_outline[1] = shoulder + Vector2(5.0 * ux, 0)
		_body_outline[2] = Vector2(x + 9.0 * ux, height + 2.0)
		_body_outline[3] = Vector2(x - 9.0 * ux, height + 2.0)
		draw_colored_polygon(_body_outline, ink)
		var wave := sin(clock * (0.85 + float(i % 5) * 0.065) + phase) * 0.23
		var side := -1.0 if i % 2 else 1.0
		var elbow := shoulder + Vector2(side * 7.0 * ux, -4.0 * uy)
		var hand := elbow + Vector2(side * (3.0 + wave * 7.0) * ux, -11.0 * uy)
		_upper_arms[i * 2] = shoulder + Vector2(side * 3.0 * ux, 0)
		_upper_arms[i * 2 + 1] = elbow
		_lower_arms[i * 2] = elbow
		_lower_arms[i * 2 + 1] = hand
		_ink_colors[i] = ink
		var tip := hand + Vector2(sin(wave + side * 0.16), -cos(wave + side * 0.16)) * 10.0 * uy
		var color: Color = COLORS[i % COLORS.size()]
		if absf(x - size.x * 0.5) < minf(62.0, size.x * 0.15):
			color = color.darkened(0.45)
		_sticks[i * 2] = hand
		_sticks[i * 2 + 1] = tip
		_halo_colors[i] = Color(color, 0.13)
		_stick_colors[i] = color
	# Same geometry/colors/AA, but only four line submissions instead of 112.
	draw_multiline_colors(_upper_arms, _ink_colors, maxf(1.0, 3.2 * minf(ux, uy)), true)
	draw_multiline_colors(_lower_arms, _ink_colors, maxf(1.0, 2.7 * minf(ux, uy)), true)
	draw_multiline_colors(_sticks, _halo_colors, maxf(2.0, 4.2 * minf(ux, uy)), true)
	draw_multiline_colors(_sticks, _stick_colors, maxf(1.0, 1.5 * minf(ux, uy)), true)
