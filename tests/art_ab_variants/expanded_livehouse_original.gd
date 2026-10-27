extends "res://scripts/stage.gd"
## Additive art-only expansion. Never moves physics, actors, or combat effects.
const FanBand = preload("res://tests/art_ab_variants/fan_band_original.gd")
var far_layer: Node3D
var back_layer: Node3D
var audience: Control
var reduce_motion := false
var motion_active := true

func _ready() -> void:
	far_layer = Node3D.new()
	far_layer.name = "FarVenueParallax"
	add_child(far_layer)
	back_layer = Node3D.new()
	back_layer.name = "AcousticWallParallax"
	add_child(back_layer)
	super._ready()
	var canvas := CanvasLayer.new()
	canvas.name = "BelowStageAudience"
	canvas.layer = 0 # Above 3D; below the existing HUD CanvasLayer (1).
	add_child(canvas)
	audience = FanBand.new()
	canvas.add_child(audience)

func _architecture() -> void:
	super._architecture()
	# Widen existing slabs, not a second coincident surface. Room keeps its identity.
	for child in get_children():
		if not child is MeshInstance3D or not child.mesh is BoxMesh:
			continue
		var box: BoxMesh = child.mesh
		if box.size.x > 12.0:
			box.size.x = 30.0 if child.position.z < -5.0 else 24.0
		if absf(child.position.x) > 7.0:
			child.position.x = signf(child.position.x) * 13.0
		if child.position.z < -5.0 or child.position.y > 5.0:
			child.reparent(far_layer)
	# Matching outer wings behind the original balcony; instanced curtain folds.
	var curtain := _mat(Color("14121e"))
	var fold := _mat(Color("211a2b"))
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 9.0, 2.2, -4.95), Vector3(9.0, 5.4, 0.18), curtain, far_layer)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 4.8, 0.16)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = 72
	for i in range(72):
		var side := -1.0 if i < 36 else 1.0
		var x := side * (4.65 + float(i % 36) * 0.25)
		batch.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 2.2, -4.81)))
	var folds := MultiMeshInstance3D.new()
	folds.multimesh = batch
	folds.material_override = fold
	far_layer.add_child(folds)
	# Seams continue beyond the former floor ends without adding collision.
	var seam := _mat(Color("15151e"))
	for side in [-1.0, 1.0]:
		for i in range(9):
			_box(Vector3(side * (6.6 + i * 0.6), 0.002, -0.15), Vector3(0.012, 0.004, 3.9), seam)

func _backdrop() -> void:
	var before := get_children()
	super._backdrop()
	for child in get_children():
		if child not in before:
			child.reparent(back_layer)

func _gallery() -> void:
	var before := get_children()
	super._gallery()
	for child in get_children():
		if child not in before:
			child.reparent(far_layer)

func _process(delta: float) -> void:
	# No animation while paused; reduce motion freezes original light/stick modulation.
	super._process(0.0 if reduce_motion or not motion_active else delta)
	if is_instance_valid(audience):
		audience.advance(0.0 if reduce_motion or not motion_active else delta)

func update_view(camera: Camera3D, gameplay_bottom: float, reduced: bool = false) -> void:
	reduce_motion = reduced
	far_layer.position.x = camera.position.x * 0.25
	back_layer.position.x = camera.position.x * 0.12
	if is_instance_valid(audience):
		audience.update_view(camera, gameplay_bottom)
