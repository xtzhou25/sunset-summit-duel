extends "res://tests/hud_test.gd"
var rows:Array=[]
func check(ok:bool,description:String) -> void:
 checks+=1
 if not ok: failures+=1;printerr("FAIL: ",description)
func _initialize(): call_deferred("run_tests")
func run_tests():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://exports/qa-stage"))
 var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_physics_process(false)
 await settle()
 var samples:Array=[]
 for kind in range(5):
  game.start_match(kind,(kind+1)%5);game.set_physics_process(false);mesh_cache.clear()
  for face in [-1,1]:
   for pose in ["idle","jump","special","roundhouse","kick"]:
    var f:Dictionary=game.sim.fighters[0]
    f.x=0.0;f.face=face;f.special_face=face;f.attack=pose if pose in ["special","roundhouse","kick"] else ""
    f.y=game.sim.JUMP_VELOCITY*game.sim.JUMP_VELOCITY/(2.0*game.sim.GRAVITY) if pose=="jump" else 0.0
    f.vy=0;f.clock=0.35;f.duration=1.15;f.special_phase="cast";f.special_phase_clock=.45
    game.previous_height[0]=f.y;game.landing_remaining[0]=0
    game.render_state(0.0)
    samples.append({"kind":kind,"face":face,"pose":pose,"points":posed_world_vertices(game.model_cache[kind])})
 for dims in [Vector2i(960,600),Vector2i(1280,800),Vector2i(1920,1080)]:
  root.size=dims;await settle()
  for positions in [[-2.9,2.9],[-4.2,1.6],[-1.6,4.2],[-4.2,-2.2],[2.2,4.2],[-1.3,1.3]]:
   game.sim.fighters[0].x=positions[0];game.sim.fighters[1].x=positions[1];game.layout_camera()
   var top:float=game.hud._match_panel.get_global_rect().end.y
   var bottom:float=game.hud._touch_panel.position.y
   var minimum:float=INF
   for sample:Dictionary in samples:
    for x:float in positions:
     for point:Vector3 in sample.points:
      var p:Vector2=game.camera.unproject_position(point+Vector3(x,0,0))
      minimum=minf(minimum,minf(minf(p.x,dims.x-p.x),minf(p.y-top,bottom-p.y)))
   for x:float in positions:
    for dx in [-.29,.29]:
     for y in [.025,3.29]:
      for z in [-.29,.29]:
       var p:Vector2=game.camera.unproject_position(Vector3(x+dx,y,z))
       minimum=minf(minimum,minf(minf(p.x,dims.x-p.x),minf(p.y-top,bottom-p.y)))
   check(minimum>=-0.5,"%s %s all5role actualskin/jump/cast+cake fits %.2fpx"%[str(dims),str(positions),minimum])
   rows.append({"viewport":str(dims),"positions":positions,"minimum_px":minimum,"camera_x":game.camera.position.x,"width":game.camera.size,"standing_2m_px":2.0*dims.x/game.camera.size})
  # Twenty continuous crosses, no teleport and no direction-dependent camera flips.
  game.sim.fighters[0].x=-1;game.sim.fighters[1].x=1;game.layout_camera()
  var initial_basis:Basis=game.camera.basis
  for frame in range(1200):
   var phase:float=float(frame)*TAU/60.0
   game.sim.fighters[0].x=2.9*sin(phase);game.sim.fighters[1].x=-2.9*sin(phase)
   var before_x:float=game.camera.position.x
   game.update_fight_camera(1.0/60.0)
   check(game.camera.basis.is_equal_approx(initial_basis),"no camera rotation")
   check(is_finite(game.camera.size) and game.camera.size+0.0001>=game.camera_rig.viewport_min_width,"finite bounded viewport-safe width")
   check(absf(game.camera.position.x-before_x)<.5,"continuous crossover has no x jump")
   for f:Dictionary in game.sim.fighters:
    var p:Vector2=game.camera.unproject_position(Vector3(f.x,1.0,0))
    check(p.x>=0 and p.x<=dims.x,"bothfighters remain visible during20crosses")
 game.start_match(4,0);check(absf(game.camera.position.x)<.001,"rematch camera reset")
 game.sim.fighters[0].x=3;game.sim.fighters[1].x=4;game.layout_camera();game.show_menu()
 check(absf(game.camera.position.x)<.001,"menu camera reset")
 var file=FileAccess.open("res://exports/qa-stage/desktop-camera.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows,"skin_samples":samples.size(),"scope":"Headless actual weighted skin projection, not native pixel/browser/device proof"},"  "))
 print("STAGE_CAMERA checks=",checks," failures=",failures)
 mesh_cache.clear();game.queue_free();await process_frame
 quit(failures)
