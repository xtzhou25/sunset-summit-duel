extends "res://tests/hud_test.gd"
## Actual weighted GLB skin, sampled before screen projection. Pose fixture only.
func _initialize() -> void:
	call_deferred("run_tests")
func run_tests() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	await settle()
	game.hud._choose(0)
	var samples:Array=[]
	for kind in [0,1]:
		for face in [-1,1]:
			for n in range(22):
				var age:float=float(n)*0.05
				if kind==0 and age>1.0: continue
				var f:Dictionary=game.sim.fighters[kind]
				f.x=0.0; f.face=face; f.attack="special"; f.duration=1.0 if kind==0 else 1.05
				f.clock=age; f.y=game.sim.special_root_height(kind,age)
				f.special_phase="cast" if kind==0 else ("start" if age<0.20 else ("air" if age<0.80 else "land"))
				f.special_phase_clock=age if kind==0 else (age if age<0.20 else (age-0.20 if age<0.80 else age-0.80))
				game.render_state(0.0)
				samples.append({"kind":kind,"face":face,"age":age,"points":posed_world_vertices(game.actors[kind])})
	var pose_count:int=samples.size()
	for dims in [Vector2i(960,600),Vector2i(844,337),Vector2i(667,322),Vector2i(568,267),Vector2i(390,791),Vector2i(375,614)]:
		root.size=dims
		await settle()
		game.layout_camera()
		var top:float=game.hud._match_panel.get_global_rect().end.y
		var bottom:float=game.hud._touch_panel.position.y
		var margin:float=INF
		var effect_margin:float=INF
		for sample:Dictionary in samples:
			for edge in [game.sim.LEFT,game.sim.RIGHT]:
				for point:Vector3 in sample.points:
					var screen:Vector2=game.camera.unproject_position(point+Vector3(edge,0,0))
					margin=minf(margin,minf(minf(screen.x,dims.x-screen.x),minf(screen.y-top,bottom-screen.y)))
		for kind in [0,1]:
			for face in [-1,1]:
				var f:Dictionary=game.sim.fighters[kind]
				f.face=face; f.special_face=face
				for edge in [game.sim.LEFT,game.sim.RIGHT]:
					f.x=edge
					game.signature_emitter(kind,0.38 if kind==0 else 0.48)
					var origin:Vector3=game.emitter_positions[kind]
					for dx in [-0.30,0.30]:
						for dy in [-0.26,0.26]:
							var screen:Vector2=game.camera.unproject_position(origin+Vector3(dx,dy,0))
							effect_margin=minf(effect_margin,minf(minf(screen.x,dims.x-screen.x),minf(screen.y-top,bottom-screen.y)))
		check(margin>=-0.5,"%s all %d actual weighted special poses both walls/faces fit, margin %.3fpx"%[str(dims),pose_count,margin])
		check(effect_margin>=-0.5,"%s mouth/heart emission visual envelope fits, margin %.3fpx"%[str(dims),effect_margin])
	game.queue_free()
	await process_frame
	print("Signature bounds checks: ",checks,"; failures: ",failures,"; weighted poses: ",pose_count)
	quit(failures)
