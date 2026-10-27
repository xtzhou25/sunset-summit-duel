extends SceneTree
var output:="res://exports/qa-v3/gameplay-purple"
var character:=0
var seconds:=20.0
func _init(): call_deferred("run")
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--frames="):output=arg.trim_prefix("--frames=")
  if arg=="--yellow":character=1
  if arg.begins_with("--seconds="):seconds=float(arg.trim_prefix("--seconds="))
 DirAccess.make_dir_recursive_absolute(output)
 var viewport:=SubViewport.new();viewport.size=Vector2i(960,600);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.own_world_3d=true;root.add_child(viewport)
 var scene=load("res://main.tscn").instantiate();viewport.add_child(scene);scene.set_physics_process(false)
 await process_frame
 scene.hud._choose(character);scene.hud.mute_requested.emit()
 var telemetry:Array=[]
 var cross_direction:=1
 for frame in range(int(seconds*60.0)):
  var f:Dictionary=scene.sim.fighters[0];var o:Dictionary=scene.sim.fighters[1]
  var cycle:int=frame%480
  if cycle==60:cross_direction=1 if o.x>f.x else -1
  var move:float=0.0
  if cycle<60:move=-float(f.face)
  elif cycle<115:move=float(cross_direction)
  elif absf(o.x-f.x)>0.78:move=1.0 if o.x>f.x else -1.0
  scene.on_command("left",move<0)
  scene.on_command("right",move>0)
  scene.on_command("punch",cycle>=115 and frame%47==0)
  scene.on_command("kick",cycle>=115 and frame%103==25)
  scene.on_command("jump",cycle==65)
  scene._physics_process(1.0/60.0)
  if frame%4==0:
   if DisplayServer.get_name()!="headless":
    await RenderingServer.frame_post_draw
    viewport.get_texture().get_image().save_png(output+"/"+("%04d"%int(frame/4))+".png")
   telemetry.append({"frame":frame,"time":scene.sim.time_left,"wins":scene.wins.duplicate(),"player":scene.sim.fighters[0].duplicate(),"ai":scene.sim.fighters[1].duplicate(),"clips":scene.current_clips.duplicate()})
  if not scene.playing:break
  await process_frame
 var file=FileAccess.open(output+"/telemetry.json",FileAccess.WRITE);file.store_string(JSON.stringify(telemetry));file.close()
 print("REAL GAMEPLAY ",output," frames ",telemetry.size()," real AI; no HP/position/state fixtures")
 scene.sound.stop();viewport.queue_free();await process_frame;quit()
