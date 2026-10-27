extends SceneTree
var fails:=0
func _init():call_deferred("run")
func run():
	for dims in [Vector2i(1280,800),Vector2i(844,390),Vector2i(390,844),Vector2i(375,667)]:
		var vp:=SubViewport.new();vp.size=dims;root.add_child(vp)
		var game=load("res://main.tscn").instantiate();vp.add_child(game);game.set_physics_process(false)
		await process_frame;game.layout_camera()
		var low=game.camera.unproject_position(Vector3(-2.72,0,0))
		var high=game.camera.unproject_position(Vector3(2.72,2.85,0))
		var limit:float=dims.y*game.hud.gameplay_height_ratio()
		var ok=low.x>=0 and high.x<=dims.x and low.y<limit and high.y>78
		print("CAMERA ",dims," low ",low," high ",high," controlstop ",limit," pass ",ok)
		if not ok:fails+=1
		vp.queue_free();await process_frame
	quit(fails)
