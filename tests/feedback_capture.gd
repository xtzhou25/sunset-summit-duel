extends SceneTree
class FixtureBrain:
 extends RefCounted
 var command:Dictionary={}
 func reset(): command.clear()
 func act(_sim,_delta): return command
var output:="res://exports/qa-v2/frames"
var character:=0
var facing:=1
func _init(): call_deferred('run')
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with('--frames='):output=arg.trim_prefix('--frames=')
  if arg=='--yellow':character=1
  if arg=='--left':facing=-1
 DirAccess.make_dir_recursive_absolute(output)
 var viewport:=SubViewport.new();viewport.size=Vector2i(960,600);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.own_world_3d=true;root.add_child(viewport)
 var scene=load('res://main.tscn').instantiate();viewport.add_child(scene);scene.set_physics_process(false)
 await process_frame
 scene.brain=FixtureBrain.new();scene.hud._choose(character);scene.muted=true
 scene.sim.fighters[0].x=-.35*facing;scene.sim.fighters[1].x=.35*facing
 for a in scene.anims: a.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var has_manual:=false
 for prop in scene.get_property_list():
  if prop.name=='animation_manual':has_manual=true
 for frame in range(180):
  if frame==55:scene.taps.punch=true
  if frame==110:
   scene.sim.fighters[0].x=-.35*facing;scene.sim.fighters[1].x=.35*facing
   scene.brain.command={'move':float(facing)}
   scene.taps.punch=true
  scene._physics_process(1.0/60.0)
  if not has_manual:
   for a in scene.anims:a.advance(1.0/60.0)
  if frame%3==0:
   await RenderingServer.frame_post_draw
   var img=viewport.get_texture().get_image()
   img.save_png(output+'/'+('%04d'%int(frame/3))+'.png')
  await process_frame
 print('FEEDBACK CAPTURE ',output,' 60 native frames at20fps; character ',character,' facing ',facing)
 scene.sound.stop();viewport.queue_free();await process_frame;quit()
