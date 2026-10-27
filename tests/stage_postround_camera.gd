extends "res://tests/hud_test.gd"
var rows:Array=[]
func _initialize():call_deferred("run_tests")
func run_tests():
 var probes:Array=JSON.parse_string(FileAccess.get_file_as_string("res://exports/qa-stage/postround-probe.json"))
 var game=load("res://main.tscn").instantiate();root.add_child(game);await settle();game.set_physics_process(false)
 var global_min:float=INF
 for probe:Dictionary in probes:
  game.start_match(4,int(probe.kind));game.set_physics_process(false);mesh_cache.clear()
  for snapshot:Dictionary in probe.snapshots:
   game.sim.fighters=snapshot.fighters.duplicate(true);game.sim.round_over=true;game.sim.winner=0
   game.render_state(0.0)
   var points:Array=posed_world_vertices(game.actors[0]);points.append_array(posed_world_vertices(game.actors[1]))
   for dims in [Vector2i(1280,800),Vector2i(375,614),Vector2i(568,267)]:
    root.size=dims;await settle();game.layout_camera()
    var top:float=game.hud._match_panel.get_global_rect().end.y
    var bottom:float=game.hud._touch_panel.position.y
    var minimum:float=INF
    for point:Vector3 in points:
     var p:Vector2=game.camera.unproject_position(point)
     minimum=minf(minimum,minf(minf(p.x,float(dims.x)-p.x),minf(p.y-top,bottom-p.y)))
    check(minimum>=0,"KO settled actual skin fits %d/%s/%s frame%d margin%.3f"%[probe.kind,str(probe.side),str(dims),snapshot.frame,minimum])
    global_min=minf(global_min,minimum)
    rows.append({"kind":probe.kind,"side":probe.side,"frame":snapshot.frame,"viewport":str(dims),"margin_px":minimum,"camera_x":game.camera.position.x,"camera_width":game.camera.size})
 FileAccess.open("res://exports/qa-stage/postround-camera.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"minimum_pixel_margin":global_min,"rows":rows,"scope":"Headless mathematical projection of actual weightedKO/winner skin; not native pixels/device"},"  "))
 print("STAGE_POSTROUND_CAMERA checks=",checks," failures=",failures," minpx=",global_min)
 game.queue_free();await process_frame;await process_frame;quit(failures)
