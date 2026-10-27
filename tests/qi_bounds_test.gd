extends "res://tests/hud_test.gd"
# Actual final GLB weighted vertices and separately visible rifle; fixed pose geometry, not live-input proof.
func _initialize():call_deferred("run_tests")
func run_tests():
 var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_physics_process(false);await settle();game.start_match(2,0)
 var samples:Array=[]
 for face in [-1,1]:
  for n in range(56):
   var age:float=float(n)*0.02
   var f:Dictionary=game.sim.fighters[0]
   f.x=0.0;f.face=face;f.special_face=face;f.attack="special";f.duration=1.10;f.clock=age;f.y=0.0;f.special_phase_clock=age
   game.render_state(0.0)
   var points:PackedVector3Array=posed_world_vertices(game.model_cache[2])
   if game.rifle_props[0].visible:points.append_array(posed_world_vertices(game.rifle_props[0]))
   check(game.rifle_props[0].visible==(age>=.08 and age<=.94),"prop interval pose "+str(age))
   samples.append(points)
 var results:Array=[]
 for dims in [Vector2i(960,600),Vector2i(844,337),Vector2i(667,322),Vector2i(568,267),Vector2i(390,791),Vector2i(375,614)]:
  root.size=dims;await settle();game.layout_camera()
  var top:float=game.hud._match_panel.get_global_rect().end.y
  var bottom:float=game.hud._touch_panel.position.y
  var margin:float=INF
  for points:PackedVector3Array in samples:
   for edge in [game.sim.LEFT,game.sim.RIGHT]:
    for point:Vector3 in points:
     var screen:Vector2=game.camera.unproject_position(point+Vector3(edge,0,0))
     margin=minf(margin,minf(minf(screen.x,dims.x-screen.x),minf(screen.y-top,bottom-screen.y)))
  check(margin>=-.5,"Qi skin and rifle 112 poses both walls fit "+str(dims)+" margin="+str(margin))
  results.append({"viewport":str(dims),"margin_px":margin})
 var file=FileAccess.open("res://exports/qa-v10/qi-bounds.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"weighted_pose_samples":samples.size(),"results":results},"  "));file.close()
 print("QI BOUNDS checks=",checks," failures=",failures," poses=",samples.size())
 game.queue_free();await process_frame;quit(failures)
