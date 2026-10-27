extends SceneTree
func _init(): call_deferred("run")
func run():
	for sample in [{"name":"landscape-844x390-edge-jump","size":Vector2i(844,390),"mode":"jump"},{"name":"portrait-390x844-menu","size":Vector2i(390,844),"mode":"menu"},{"name":"portrait-390x844","size":Vector2i(390,844),"mode":"idle"},{"name":"portrait-375x667","size":Vector2i(375,667),"mode":"idle"},{"name":"desktop-guard","size":Vector2i(1280,800),"mode":"guard"},{"name":"desktop-ko","size":Vector2i(1280,800),"mode":"ko"},{"name":"desktop-kick","size":Vector2i(1280,800),"mode":"kick"}]:
		var viewport:=SubViewport.new();viewport.size=sample.size;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.own_world_3d=true;root.add_child(viewport)
		var scene=load("res://main.tscn").instantiate();viewport.add_child(scene);scene.set_physics_process(false)
		await process_frame
		if sample.mode!="menu": scene.hud._choose(0)
		scene.sim.fighters[0].x=-1.1;scene.sim.fighters[1].x=1.1
		if sample.mode in ["guard","ko","kick"]: scene.sim.fighters[0].x=-0.35;scene.sim.fighters[1].x=0.35
		if sample.mode=="ko": scene.sim.fighters[1].hp=8
		if sample.mode=="jump": scene.sim.fighters[0].x=-2.1;scene.sim.fighters[1].x=2.1
		for frame in range(75):
			var a:Dictionary={};var b:Dictionary={}
			if sample.mode=="guard":
				a.move=-1.0
				if frame==1: b.punch=true
			if sample.mode=="ko" and frame==1: a.punch=true
			if sample.mode=="kick" and frame==1:a.kick=true
			if sample.mode=="jump" and frame==1:a.jump=true;b.jump=true
			scene.sim.step(1.0/60.0,[a,b]);scene.render_state(1.0/60.0)
			await process_frame
			if sample.mode=="guard" and frame==12: break
			if sample.mode=="kick" and frame==27: break
			if sample.mode=="jump" and frame==18: break
		if sample.mode=="kick": print("KICK STATE ",scene.sim.fighters[0]," clip=",scene.anims[0].current_animation," time=",scene.anims[0].current_animation_position," length=",scene.anims[0].current_animation_length)
		await RenderingServer.frame_post_draw
		var img=viewport.get_texture().get_image();var output="res://exports/qa/"+sample.name+".png"
		print("QA CAPTURE ",sample.name," ",img.get_size()," result ",img.save_png(output))
		viewport.queue_free();await process_frame
	quit()
