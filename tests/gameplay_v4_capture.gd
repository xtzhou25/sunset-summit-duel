extends SceneTree
var output:="res://exports/qa-v4/gameplay-purple"
var character:=0
var seconds:=20.0
var early_cross:=false
func _init(): call_deferred("run")
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--frames="):output=arg.trim_prefix("--frames=")
  if arg=="--yellow":character=1
  if arg=="--early-cross":early_cross=true
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
  var cycle:int=(frame+(400 if early_cross else 0))%600
  if cycle==440:cross_direction=1 if o.x>f.x else -1
  var move:float=0.0
  if cycle>=400 and cycle<440:move=-float(f.face)
  elif cycle>=440 and cycle<495:move=float(cross_direction)
  elif absf(o.x-f.x)>0.78:move=1.0 if o.x>f.x else -1.0
  scene.on_command("left",move<0)
  scene.on_command("right",move>0)
  var jab_now:bool=(cycle<400 or cycle>=495) and (frame%91==0 or (f.attack=="punch" and f.duration-f.clock<=0.09 and f.duration-f.clock>0.06))
  scene.on_command("punch",jab_now)
  scene.on_command("heavy",(cycle<400 or cycle>=495) and frame%181==43)
  scene.on_command("kick",(cycle<400 or cycle>=495) and frame%103==25)
  scene.on_command("jump",cycle==445)
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
