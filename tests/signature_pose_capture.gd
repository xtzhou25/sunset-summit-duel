extends SceneTree
## Actual native game, controlled position/AI guard fixture. Not a live AI match.
class GuardRobot extends RefCounted:
	var retreat:=0.0
	func reset() -> void: retreat=0.0
	func act(_sim,_delta:float)->Dictionary: return {"move":retreat}
var output:="res://exports/qa-v6/signature-fixture"
var character:=0
var face:=1
var seconds:=7.0
func _init(): call_deferred("run")
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="): output=arg.trim_prefix("--frames=")
		if arg=="--yellow": character=1
		if arg=="--left": face=-1
	DirAccess.make_dir_recursive_absolute(output)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(960,600)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d=true
	root.add_child(viewport)
	var scene=load("res://main.tscn").instantiate()
	viewport.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	var robot:=GuardRobot.new()
	scene.brain=robot
	scene.hud._choose(character)
	scene.toggle_mute()
	scene.sim.fighters[0].x=-face*1.20
	scene.sim.fighters[1].x=face*2.10
	scene.sim.fighters[0].face=face
	scene.sim.fighters[1].face=-face
	var telemetry:Array=[]
	for frame in range(int(seconds*60.0)):
		robot.retreat=float(face) if frame>=220 else 0.0
		scene.on_command("special",frame in [15,280])
		scene._physics_process(1.0/60.0)
		if frame%4==0:
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png(output+"/"+("%04d"%int(frame/4))+".png")
			telemetry.append({"frame":frame,"player":scene.sim.fighters[0].duplicate(),"target":scene.sim.fighters[1].duplicate(),"clips":scene.current_clips.duplicate(),"projectiles":scene.sim.projectiles.duplicate(true),"events":scene.sim.events.duplicate(true),"emitters":scene.emitter_positions.duplicate(true)})
		await process_frame
	var file=FileAccess.open(output+"/telemetry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"kind":"Controlled position and guard fixture, not live AI","samples":telemetry}))
	file.close()
	viewport.queue_free()
	await process_frame
	quit()
