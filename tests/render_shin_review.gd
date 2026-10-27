extends Node
func _ready():
 var phase=FileAccess.get_file_as_string("res://tests/shin-phase.txt").strip_edges()
 var vp:=SubViewport.new();vp.size=Vector2i(900,900);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var game=load("res://main.tscn").instantiate();vp.add_child(game);game.set_physics_process(false);game.auto_demo=false
 await get_tree().process_frame
 for kind in [2,3,4]:
  game.start_match(kind,0);game.sim.fighters[0].x=0;game.sim.fighters[1].x=3;game.render_state(0);game.hud.visible=false
  for detail in [false,true]:
   game.camera.v_offset=0;game.camera.size=0.9 if detail else 2.5
   var center=Vector3(0,.45 if detail else 1.1,0)
   game.camera.position=center+Vector3(.15,0,5);game.camera.look_at(center)
   await get_tree().process_frame;await RenderingServer.frame_post_draw
   vp.get_texture().get_image().save_png("res://exports/qa-v15/%s-%s-%s.png"%[phase,["qi","tao","ha"][kind-2],"shin" if detail else "full"])
 game.start_match(4,0);game.sim.fighters[0].x=0;game.sim.fighters[1].x=3;game.render_state(0);game.hud.visible=false;game.camera.size=.85;game.camera.v_offset=0
 game.camera.position=Vector3(.2,1.88,5);game.camera.look_at(Vector3(0,1.8,0))
 await get_tree().process_frame;await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png("res://exports/qa-v15/%s-ha-glasses.png"%phase)
 print("SHIN_NATIVE_REVIEW_COMPLETE ",phase)
 get_tree().quit()
