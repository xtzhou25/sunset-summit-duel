extends Node
const OUT:="res://exports/qa-stage-native/motion"
func _ready():
 if DisplayServer.get_name()=="headless":get_tree().quit();return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 get_window().size=Vector2i(960,600)
 var game=load("res://main.tscn").instantiate();add_child(game);game.set_physics_process(false)
 await get_tree().process_frame
 game.hud.opponent_choice=3;game.hud._choose(4);game.set_physics_process(false);game.stage.set_process(false)
 game.sim.fighters[0].x=-4.0;game.sim.fighters[1].x=-2.0;game.layout_camera()
 for frame in range(120):
  # Scripted shared movement only; the actual simulation/camera/art do all animation.
  var direction:float=1.0 if frame<60 else -1.0
  game.sim.step(0.05,[{"move":direction},{"move":direction}]);game.render_state(.05);game.stage._process(.05)
  await get_tree().process_frame;await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png(OUT+"/%03d.png"%frame)
 print("STAGE_MOTION_COMPLETE frames120 actualviewport=",get_viewport().get_visible_rect().size);get_tree().quit()
