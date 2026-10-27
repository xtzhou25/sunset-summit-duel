extends Node3D
## A completely original, asset-free underground livehouse.
## Decorative geometry only: fighter collision and camera belong to the game.

const VIOLET := Color("a784ef")
const GOLD := Color("f7c977")
const INK := Color("11121b")
const STEEL := Color("34333f")

var _violet_light: OmniLight3D
var _gold_light: OmniLight3D
var _clock := 0.0
var _glowsticks: Array[Node3D] = []
var _shadow_targets: Array[Node3D] = []
var _ground_shadows: Array[Node3D] = []

func _ready() -> void:
	name = "SunsetSummitStage"
	_environment()
	_architecture()
	_backdrop()
	_equipment()
	_gallery()
	_lighting()
	call_deferred("_bind_fighter_shadows")

func _process(delta: float) -> void:
	_clock += delta
	# Slow, tiny changes give the room life without distracting from the fight.
	if is_instance_valid(_violet_light):
		_violet_light.light_energy = 0.30 + sin(_clock * 0.85) * 0.015
	if is_instance_valid(_gold_light):
		_gold_light.light_energy = 0.28 + sin(_clock * 0.73 + 1.6) * 0.015
	_update_fighter_shadows()
	for i in _glowsticks.size():
		_glowsticks[i].rotation.z = sin(_clock * 1.0 + float(i) * 1.9) * 0.14

func _mat(color: Color, emission: float = 0.0, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.86
	result.metallic = metallic
	if emission > 0.0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = emission
	return result

func _mesh(mesh: Mesh, pos: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	parent.add_child(instance)
	return instance

func _box(pos: Vector3, size: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return _mesh(shape, pos, material, parent)

func _cylinder(pos: Vector3, radius: float, height: float, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 16
	return _mesh(shape, pos, material, parent)

func _sphere(pos: Vector3, radius: float, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 10
	shape.rings = 5
	return _mesh(shape, pos, material, parent)

func _bar(a: Vector3, b: Vector3, width: float, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var midpoint := (a + b) * 0.5
	var result := _box(midpoint, Vector3(width, a.distance_to(b), width), material, parent)
	var direction := (b - a).normalized()
	result.quaternion = Quaternion(Vector3.UP, direction)
	return result

func _label(value: String, pos: Vector3, size: int, color: Color, pixel: float = 0.008) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font = preload("res://assets/ui_font.otf")
	label.position = pos
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.shaded = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)
	return label

func _environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "LivehouseAtmosphere"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("080b14")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b6bed5")
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)

func _architecture() -> void:
	var floor_mat := _mat(Color("26252d"), 0.0, 0.12)
	var dark_mat := _mat(INK)
	var seam_mat := _mat(Color("15151e"))
	var metal_mat := _mat(STEEL, 0.0, 0.5)
	# Top surface is exactly y = 0. The playable strip has no scenery on it.
	_box(Vector3(0, -0.22, -0.15), Vector3(12.8, 0.44, 4.0), dark_mat)
	_box(Vector3(0, -0.015, -0.15), Vector3(12.65, 0.03, 3.95), floor_mat)
	for i in range(21):
		_box(Vector3(-6.0 + float(i) * 0.6, 0.002, -0.15), Vector3(0.012, 0.004, 3.9), seam_mat)
	# A restrained thin stage lip keeps footwork legible against the black apron.
	_box(Vector3(0, -0.03, 1.86), Vector3(12.65, 0.055, 0.055), _mat(Color("c6a56a"), 0.35))
	_box(Vector3(0, -0.26, 1.88), Vector3(12.75, 0.20, 0.04), _mat(Color("13131d")))
	for x in [-5.6, -3.9, 3.9, 5.6]:
		_box(Vector3(x, -0.27, 1.91), Vector3(0.52, 0.045, 0.025), _mat(GOLD, 0.65))
	# Stage-safe edge markings, kept away from the performers' feet.
	for x in [-5.9, 5.9]:
		for i in range(3):
			_box(Vector3(x, 0.007, 1.3 - float(i) * 0.23), Vector3(0.18, 0.008, 0.10), _mat(Color("9b8355")))
	# Recessed black venue shell. Side bays reveal a distant balcony.
	_box(Vector3(0, 2.3, -5.8), Vector3(17.0, 6.3, 0.20), _mat(Color("090b13")))
	_box(Vector3(0, 5.25, -1.7), Vector3(16.0, 0.20, 9.0), dark_mat)
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 7.5, 2.3, -1.5), Vector3(0.2, 5.4, 8.0), dark_mat)
		for z in [-2.4, -1.85]:
			_bar(Vector3(side * 6.35, 0.0, z), Vector3(side * 6.35, 4.55, z), 0.085, metal_mat)
		for j in range(7):
			var y := float(j) * 0.64
			_bar(Vector3(side * 6.35, y, -2.4), Vector3(side * 6.35, y + 0.64, -1.85), 0.044, metal_mat)
			_bar(Vector3(side * 6.35, y, -1.85), Vector3(side * 6.35, y + 0.64, -2.4), 0.044, metal_mat)
	# A low profile overhead truss. No beams descend into the combat silhouette.
	for y in [4.35, 4.70]:
		_bar(Vector3(-6.4, y, -2.05), Vector3(6.4, y, -2.05), 0.072, metal_mat)
	for i in range(16):
		var x := -6.4 + float(i) * 0.8
		_bar(Vector3(x, 4.35, -2.05), Vector3(x + 0.8, 4.70, -2.05), 0.037, metal_mat)

func _backdrop() -> void:
	var ink_mat := _mat(Color("181620"))
	var slat_mat := _mat(Color("25222f"))
	var lilac_mat := _mat(VIOLET, 0.48)
	var gold_mat := _mat(GOLD, 0.48)
	# Central acoustic wall sits behind the arena; side bays remain open.
	_box(Vector3(0, 2.10, -2.45), Vector3(8.55, 4.20, 0.18), ink_mat)
	for i in range(31):
		var x := -4.05 + float(i) * 0.27
		_box(Vector3(x, 1.95, -2.33), Vector3(0.038, 3.70, 0.10), slat_mat)
	# The sign is actual geometry, including custom Chinese glyph strokes.
	_box(Vector3(0, 2.65, -2.18), Vector3(3.5, 1.10, 0.18), _mat(Color("11111a")))
	_box(Vector3(0, 3.22, -2.16), Vector3(3.52, 0.025, 0.06), lilac_mat)
	_box(Vector3(0, 2.08, -2.16), Vector3(3.52, 0.025, 0.06), gold_mat)
	_label("决战日不落之巅", Vector3(0, 2.55, -2.05), 38, Color("e4d1fc"), 0.007)
	_label("S U N S E T   S U M M I T", Vector3(0, 2.28, -2.04), 14, Color("d7c8e7"), 0.007)
	_label("LIVEHOUSE  /  AFTER HOURS", Vector3(0, 2.13, -2.04), 10, Color("8b7e96"), 0.006)
	# Short broken soundwave motif, never through the central fight silhouette.
	for side in [-1.0, 1.0]:
		for i in range(6):
			var h := 0.08 + float((i * 3 + 2) % 5) * 0.09
			_box(Vector3(side * (3.18 + float(i) * 0.14), 3.36, -2.20), Vector3(0.042, h, 0.025), lilac_mat if side < 0.0 else gold_mat)
		_poster(side)
	# Vertical edge washes delineate the wings, not the arena boundaries.
	_box(Vector3(-4.33, 2.12, -2.26), Vector3(0.032, 3.80, 0.04), lilac_mat)
	_box(Vector3(4.33, 2.12, -2.26), Vector3(0.032, 3.80, 0.04), gold_mat)

func _poster(side: float) -> void:
	var x := side * 3.60
	var face_z := -2.15
	_box(Vector3(x, 1.88, -2.20), Vector3(1.0, 1.48, 0.04), _mat(Color("111119")))
	var accent := VIOLET if side < 0.0 else GOLD
	_box(Vector3(x, 2.55, face_z), Vector3(0.86, 0.025, 0.02), _mat(accent, 0.18))
	_label("NOCTURNE" if side < 0.0 else "ENCORE", Vector3(x, 2.34, face_z + 0.02), 21, accent, 0.0052)
	_label("VOL. 01" if side < 0.0 else "ALL NIGHT", Vector3(x, 2.15, face_z + 0.02), 13, Color("978b9f"), 0.006)
	# Poster artwork: a little original orbit / soundwave graphic.
	for i in range(7):
		var h := 0.10 + sin(float(i) / 6.0 * PI) * 0.36
		_box(Vector3(x - 0.30 + float(i) * 0.10, 1.77, face_z + 0.02), Vector3(0.025, h, 0.012), _mat(accent * 0.65))
	_label("LIVE / 23:00", Vector3(x, 1.34, face_z + 0.02), 14, Color("978b9f"), 0.0058)

func _equipment() -> void:
	var cabinet_mat := _mat(Color("14151c"))
	var grill_mat := _mat(Color("2c2c35"), 0.0, 0.15)
	var cone_mat := _mat(Color("0b0c13"))
	var ring_mat := _mat(Color("44414d"), 0.0, 0.4)
	for side in [-1.0, 1.0]:
		var x: float = side * 3.5
		_box(Vector3(x, 0.76, -0.90), Vector3(0.97, 1.52, 0.82), cabinet_mat)
		_box(Vector3(x, 0.82, -0.475), Vector3(0.84, 1.24, 0.02), grill_mat)
		for y in [0.49, 1.08]:
			var ring := _cylinder(Vector3(x, y, -0.447), 0.245, 0.027, ring_mat)
			ring.rotation.x = PI * 0.5
			var cone := _cylinder(Vector3(x, y, -0.425), 0.214, 0.031, cone_mat)
			cone.rotation.x = PI * 0.5
			var center := _sphere(Vector3(x, y, -0.405), 0.079, grill_mat)
			center.scale.z = 0.32
		_box(Vector3(x, 1.92, -0.93), Vector3(0.84, 0.72, 0.72), cabinet_mat)
		_box(Vector3(x, 1.91, -0.552), Vector3(0.66, 0.48, 0.025), grill_mat)
		_box(Vector3(x, 2.03, -0.528), Vector3(0.43, 0.09, 0.015), cone_mat)
		_box(Vector3(x, 1.80, -0.528), Vector3(0.49, 0.10, 0.015), cone_mat)
		# Amp label and a tiny live power LED.
		_label("LIVE", Vector3(x, 0.16, -0.45), 14, Color("85808e"), 0.004)
		_sphere(Vector3(x + side * 0.30, 1.39, -0.44), 0.018, _mat(GOLD, 1.0))
		# A cable run lives only at the back edge of the platform.
		_bar(Vector3(x, 0.024, -1.36), Vector3(side * 4.6, 0.024, -1.75), 0.024, cone_mat)
		_bar(Vector3(side * 4.6, 0.024, -1.75), Vector3(side * 1.0, 0.024, -1.75), 0.024, cone_mat)
	# Practical overhead lamps, with small emissive lenses instead of heavy effects.
	for i in range(6):
		var x := -4.5 + float(i) * 1.8
		var can := _cylinder(Vector3(x, 4.19, -1.98), 0.16, 0.30, cabinet_mat)
		can.rotation.x = deg_to_rad(22.0)
		var lens := _cylinder(Vector3(x, 4.04, -1.92), 0.12, 0.025, _mat(VIOLET if i < 3 else GOLD, 0.85))
		lens.rotation.x = deg_to_rad(22.0)
		_bar(Vector3(x - 0.21, 4.38, -1.98), Vector3(x - 0.21, 4.15, -1.98), 0.035, ring_mat)
		_bar(Vector3(x + 0.21, 4.38, -1.98), Vector3(x + 0.21, 4.15, -1.98), 0.035, ring_mat)

func _gallery() -> void:
	# Sparse, deliberately distant spectators in the dark side galleries.
	var audience_mat := _mat(Color("10121c"))
	var rail_mat := _mat(Color("242330"))
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 5.35, 0.74, -4.7), Vector3(2.3, 0.13, 1.0), _mat(Color("0b0c14")))
		_bar(Vector3(side * 4.35, 1.65, -4.10), Vector3(side * 6.65, 1.65, -4.10), 0.038, rail_mat)
		for j in range(4):
			var x: float = side * (4.55 + float(j) * 0.56)
			var y := 1.42 + float(j % 2) * 0.08
			_cylinder(Vector3(x, y - 0.16, -4.65), 0.16, 0.55, audience_mat)
			_sphere(Vector3(x, y + 0.28, -4.65), 0.14, audience_mat)
			if j % 2 == 0:
				var stick := Node3D.new()
				stick.position = Vector3(x - side * 0.22, y + 0.30, -4.45)
				add_child(stick)
				var color := Color("8263ac") if side < 0.0 else Color("ac925d")
				_box(Vector3(0, 0.10, 0), Vector3(0.025, 0.22, 0.025), _mat(color, 0.50), stick)
				_glowsticks.append(stick)

func _lighting() -> void:
	# Neutral front key preserves skin/clothing readability under the colored rim.
	var key := DirectionalLight3D.new()
	key.name = "SoftWhiteKey"
	key.rotation_degrees = Vector3(-48, -15, 0)
	key.light_color = Color("f5eee5")
	key.light_energy = 0.55
	key.shadow_enabled = false
	key.directional_shadow_max_distance = 20.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(key)
	_violet_light = _omni(Vector3(-4.2, 3.3, 0.3), VIOLET, 0.30, 7.0)
	_gold_light = _omni(Vector3(4.2, 3.3, 0.3), GOLD, 0.28, 7.0)
	_omni(Vector3(0, 2.8, 3.5), Color("e1e3f6"), 0.18, 8.0)
	_omni(Vector3(0, 3.6, -1.5), Color("a18bca"), 0.10, 4.0)

func _omni(pos: Vector3, color: Color, energy: float, radius: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.25
	light.shadow_enabled = false
	add_child(light)
	return light


func _bind_fighter_shadows() -> void:
	# Optional integration: the containing game owns an `actors` array.
	# Standalone stage previews need neither this controller nor characters.
	var world := get_parent()
	if world == null or world.get_parent() == null:
		return
	var controller := world.get_parent()
	if not "actors" in controller:
		return
	var actors_value = controller.get("actors")
	if not actors_value is Array:
		return
	for actor in actors_value:
		if not actor is Node3D:
			continue
		_shadow_targets.append(actor)
		var shadow := Node3D.new()
		shadow.name = "SoftGroundContact"
		add_child(shadow)
		_ground_shadows.append(shadow)
		# Layered translucent disks are a cheap texture-free contact shadow.
		for layer in range(3):
			var material := _mat(Color(0.008, 0.009, 0.016, 0.10))
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var radius := 0.43 - float(layer) * 0.105
			var disk := _cylinder(Vector3(0, 0.012 + float(layer) * 0.002, 0), radius, 0.001, material, shadow)
			disk.scale.z = 0.57
			disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_fighter_shadows()

func _update_fighter_shadows() -> void:
	for i in _shadow_targets.size():
		if not is_instance_valid(_shadow_targets[i]):
			_ground_shadows[i].visible = false
			continue
		var actor_position := to_local(_shadow_targets[i].global_position)
		_ground_shadows[i].position = Vector3(actor_position.x, 0.0, actor_position.z + 0.04)
		var size_value := clampf(1.0 - maxf(0.0, actor_position.y) * 0.16, 0.65, 1.0)
		_ground_shadows[i].scale = Vector3(size_value, 1.0, size_value)
