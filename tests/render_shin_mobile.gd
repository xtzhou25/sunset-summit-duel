extends Node
func _ready():
 for dims in [Vector2i(1280,800),Vector2i(375,614),Vector2i(568,267)]:
  var vp:=SubViewport.new();vp.size=dims;vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
  var game=load("res://main.tscn").instantiate();vp.add_child(game);game.set_physics_process(false);game.auto_demo=false
  await get_tree().process_frame
  for kind in [2,3,4]:
   game.hud.opponent_choice=0;game.hud._choose(kind);game.set_physics_process(false);game.render_state(0)
   await get_tree().process_frame;await RenderingServer.frame_post_draw
   vp.get_texture().get_image().save_png("res://exports/qa-v15/mobile-%dx%d-%s.png"%[dims.x,dims.y,["qi","tao","ha"][kind-2]])
  vp.queue_free();await get_tree().process_frame
 print("SHIN_NATIVE_MOBILE_COMPLETE")
 get_tree().quit()
