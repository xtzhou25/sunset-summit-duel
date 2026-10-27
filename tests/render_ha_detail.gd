extends Node
func _ready():
 var vp:=SubViewport.new();vp.size=Vector2i(900,700);vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
 var game=load("res://main.tscn").instantiate();vp.add_child(game);game.set_physics_process(false);game.auto_demo=false
 await get_tree().process_frame
 game.start_match(4,0);game.sim.fighters[0].x=0;game.sim.fighters[1].x=2
 game.render_state(0);game.hud.visible=false;game.camera.size=.85;game.camera.v_offset=0
 game.camera.position=Vector3(.2,1.88,5);game.camera.look_at(Vector3(0,1.8,0))
 await get_tree().process_frame;await RenderingServer.frame_post_draw
 vp.get_texture().get_image().save_png("res://exports/qa-v14/native-ha/glasses-native-detail.png")
 print("HA_NATIVE_DETAIL_COMPLETE final_asset_sha=",FileAccess.get_sha256("res://assets/ha.glb"))
