extends "res://tests/hud_test.gd"
## Real simulation jump trajectory plus actual weighted imported skin. Pose/bounds fixture.
func _initialize() -> void:
 call_deferred("run_tests")
func run_tests() -> void:
 var game=load("res://main.tscn").instantiate()
 root.add_child(game);game.set_physics_process(false)
 await settle();game.hud._choose(0)
 var samples:Array=[]
 var highest:=0.0
 for kind in [0,1]:
  for face in [-1,1]:
   game.sim.reset(0)
   var f:Dictionary=game.sim.fighters[kind]
   f.x=0.0;game.sim.fighters[1-kind].x=2.1*face
   for frame in range(70):
    var commands:Array=[{},{}]
    commands[kind]={"jump":frame==0}
    game.sim.step(1.0/60.0,commands)
    f.face=face
    highest=maxf(highest,float(f.y))
    game.render_state(1.0/60.0)
    if frame%3==0:
     samples.append({"kind":kind,"face":face,"frame":frame,"points":posed_world_vertices(game.actors[kind])})
 for dims in [Vector2i(960,600),Vector2i(844,337),Vector2i(667,322),Vector2i(568,267),Vector2i(390,791),Vector2i(375,614)]:
  root.size=dims;await settle();game.layout_camera()
  var top:float=game.hud._match_panel.get_global_rect().end.y
  var bottom:float=game.hud._touch_panel.position.y
  var margin:=INF
  for sample:Dictionary in samples:
   for edge in [game.sim.LEFT,game.sim.RIGHT]:
    for point:Vector3 in sample.points:
     var screen:Vector2=game.camera.unproject_position(point+Vector3(edge,0,0))
     margin=minf(margin,minf(minf(screen.x,dims.x-screen.x),minf(screen.y-top,bottom-screen.y)))
  check(margin>=-0.5,"%s true jump trajectory and weighted skins at both walls/facings fit %.3fpx, peak %.4fm"%[str(dims),margin,highest])
 game.queue_free();await process_frame
 print("Spacing bounds checks: ",checks,"; failures: ",failures,"; poses: ",samples.size(),"; root peak: ",highest)
 quit(failures)
