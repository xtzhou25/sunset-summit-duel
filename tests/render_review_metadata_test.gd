extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false);game.auto_demo=false
 var harness=load("res://tests/render_rifle_review.gd").new();harness.game=game
 game.brain=harness.PassiveAI.new();game.hud.opponent_choice=0;game.hud._choose(2)
 game.sim.fighters[0].x=-1.5;game.sim.fighters[1].x=2.1;game.on_command("special",true)
 var failures:=0
 for frame in range(70):
  game._physics_process(1.0/60)
  var row:Dictionary=harness.capture_metadata("test","frame",0,Vector2i(1280,800),Vector2i(1280,800),Vector2(1280,800))
  if frame<23 and (row.has_emitted_marker or row.muzzle!=null):failures+=1
  if frame>25 and not row.has_emitted_marker:failures+=1
 game.show_menu()
 var menu:Dictionary=harness.capture_metadata("test","menu",0,Vector2i(1280,800),Vector2i(1280,800),Vector2(1280,800))
 if menu.has_emitted_marker or menu.muzzle!=null:failures+=1
 # The phone harness accesses only always-defined SubViewport fields and Image size.
 for dims in [Vector2i(568,267),Vector2i(375,614)]:
  var viewport:=SubViewport.new();viewport.size=dims;viewport.own_world_3d=true;root.add_child(viewport)
  if viewport.size!=dims or not viewport.own_world_3d:failures+=1
  viewport.queue_free()
 print("REVIEW_METADATA actual frame calls=70 + menu; failures=",failures)
 harness.free();game.queue_free();await process_frame;quit(failures)
