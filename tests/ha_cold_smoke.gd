extends SceneTree
var game
var errors:=0
func _initialize():call_deferred("run")
func check(ok:bool):
 if not ok:errors+=1
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false)
 for a in range(5):
  for b in range(5):
   if a==b:continue
   game.start_match(a,b);game.set_physics_process(false);game.render_state(0)
   check(game.loaded_pair==[a,b]);check(game.anims[0]!=null and game.anims[1]!=null)
 game.start_match(4,2);game.sim.fighters[0].x=-1;game.sim.fighters[1].x=1
 game.on_command("special",true)
 for i in range(28):game._physics_process(1.0/60.0)
 check(game.current_clips[0]=="CakeCast_R");check(game.projectile_view.views.size()==1);check(game.projectile_view.warnings.size()==1)
 print("HA_COLD_PACK errors=",errors," pairs=20 clip=",game.current_clips[0]," cake_views=",game.projectile_view.views.size())
 game.show_menu();await process_frame;game.queue_free();await process_frame;await process_frame;quit(errors)
