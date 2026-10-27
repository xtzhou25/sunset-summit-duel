extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("ART ", label, " PASS=" , ok)
	if not ok: failures += 1
func run() -> void:
	for dims in [Vector2i(1280,800), Vector2i(844,390), Vector2i(390,844), Vector2i(375,667)]:
		var viewport := SubViewport.new()
		viewport.size = dims
		viewport.own_world_3d = true
		root.add_child(viewport)
		var world := Node3D.new()
		viewport.add_child(world)
		var stage = load("res://stage-art/expanded_livehouse.gd").new()
		world.add_child(stage)
		stage.set_process(false)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.position = Vector3(0,3.25,11.5)
		camera.look_at(Vector3(0,1.55,0))
		camera.size = 9.0
		camera.current = true
		await process_frame
		var ground := camera.unproject_position(Vector3.ZERO).y
		var bottom := minf(dims.y - 20.0, ground + 26.0)
		var count: int = stage.get_child_count()
		for x in [-4.2,0.0,4.2]:
			camera.position.x = x
			stage.update_view(camera, bottom)
			check(is_equal_approx(stage.far_layer.position.x,x*0.25) and is_equal_approx(stage.back_layer.position.x,x*0.12), str(dims)+" parallax "+str(x))
			check(stage.audience.position.y >= ground + 4.0 and stage.audience.position.y + stage.audience.size.y <= bottom, str(dims)+" clipping")
			check(stage.audience.mouse_filter == Control.MOUSE_FILTER_IGNORE, "audience ignores input")
		for frame in range(600): stage._process(1.0 / 60.0)
		check(stage.get_child_count() == count,"bounded node count")
		var previous: float = stage.audience.clock
		stage.motion_active = false
		stage._process(2.0)
		check(stage.audience.clock == previous,"pause freezes audience")
		stage.motion_active = true
		stage.reduce_motion = true
		stage._process(2.0)
		check(stage.audience.clock == previous,"reduce motion freezes audience")
		viewport.queue_free()
		await process_frame
	quit(failures)
