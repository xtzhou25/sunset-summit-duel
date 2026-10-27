extends SceneTree
# Explicit layout fixtures, not a recording of a played match.
func _init():call_deferred("run")
func run():
 var output:="res://exports/qa-v6/layout"
 DirAccess.make_dir_recursive_absolute(output)
 for size in [Vector2i(960,547),Vector2i(844,337),Vector2i(390,791),Vector2i(375,614),Vector2i(568,267)]:
  for kind in [0,1]:
   var vp:=SubViewport.new();vp.size=size;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;vp.own_world_3d=true;root.add_child(vp)
   var scene=load("res://main.tscn").instantiate();vp.add_child(scene);scene.set_physics_process(false)
   await process_frame
   scene.hud._choose(kind);scene.hud.mute_requested.emit()
   for i in [0,1]:
    var f:Dictionary=scene.sim.fighters[i]
    f.x=scene.sim.LEFT if i==0 else scene.sim.RIGHT;f.face=1 if i==0 else -1
    scene.sim.begin_attack(f,"special");f.clock=.38 if f.kind==0 else .48
    f.special_phase="cast" if f.kind==0 else "air";f.special_phase_clock=.38 if f.kind==0 else .28
    f.y=scene.sim.special_root_height(f.kind,f.clock)
   scene.render_state(0.0)
   await RenderingServer.frame_post_draw
   var path=output+"/layout-fixture-%dx%d-kind%d.png"%[size.x,size.y,kind]
   print("LAYOUT FIXTURE ",path," ",vp.get_texture().get_image().save_png(path))
   scene.sound.stop();vp.queue_free();await process_frame
 quit()
