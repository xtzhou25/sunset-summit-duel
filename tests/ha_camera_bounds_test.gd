extends "res://tests/hud_test.gd"
const Combat = preload("res://scripts/combat.gd")
## Actual exported weighted skin (not static AABBs) plus conservative cake/ring envelopes.
func _initialize() -> void:
 call_deferred("run_tests")
func edge_margin(game,point:Vector3,dims:Vector2i,top:float,bottom:float)->float:
 var screen:Vector2=game.camera.unproject_position(point)
 return minf(minf(screen.x,dims.x-screen.x),minf(screen.y-top,bottom-screen.y))
func run_tests() -> void:
 var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_physics_process(false)
 await settle();game.start_match(4,0);game.set_physics_process(false)
 await settle()
 var samples:Array=[]
 for face in [-1,1]:
  for n in range(24):
   var age:float=float(n)*.05
   var f:Dictionary=game.sim.fighters[0]
   f.x=0;f.y=0;f.vy=0;f.face=face;f.special_face=face;f.attack="special";f.duration=1.15;f.clock=age
   f.special_phase="cast";f.special_phase_clock=age;f.stun=0;f.down=false
   game.render_state(0.0)
   samples.append({"face":face,"age":age,"kind":"cakecast","points":posed_world_vertices(game.actors[0])})
  for age in [0.0,.2,.4]:
   var f:Dictionary=game.sim.fighters[0]
   f.attack="";f.special_phase="";f.y=game.sim.JUMP_VELOCITY*game.sim.JUMP_VELOCITY/(2.0*game.sim.GRAVITY);f.vy=0;f.x=0;f.face=face
   game.previous_height[0]=f.y;game.landing_remaining[0]=0
   game.render_state(0.0)
   game.anims[0].advance(.11);game.anims[0].seek(age,true);game.anims[0].advance(0.0)
   samples.append({"face":face,"age":age,"kind":"jump_apex","points":posed_world_vertices(game.actors[0])})
 var rows:Array=[];var all_margin:float=INF
 for dims in [Vector2i(960,600),Vector2i(844,337),Vector2i(667,322),Vector2i(568,267),Vector2i(390,791),Vector2i(375,614)]:
  root.size=dims;await settle();game.layout_camera()
  var top:float=game.hud._match_panel.get_global_rect().end.y
  var bottom:float=game.hud._touch_panel.position.y
  var skin_margin:float=INF;var cake_margin:float=INF;var ring_margin:float=INF;var worst:String=""
  for sample:Dictionary in samples:
   for edge in [game.sim.LEFT,game.sim.RIGHT]:
    for point:Vector3 in sample.points:
     var m:float=edge_margin(game,point+Vector3(edge,0,0),dims,top,bottom)
     if m<skin_margin:skin_margin=m;worst=sample.kind+" "+str(sample.face)+" "+str(sample.age)
  for x in [game.sim.LEFT,0.0,game.sim.RIGHT]:
   for y in [0.14,.5,1.0,2.0,Combat.CAKE_SPAWN_HEIGHT]:
    for dx in [-.23,.23]:
     for dy in [-.14,.14]:
      for dz in [-.17,.17]:
       cake_margin=minf(cake_margin,edge_margin(game,Vector3(x+dx,y+dy,dz),dims,top,bottom))
   for dx in [-.29,.29]:
    for dz in [-.29,.29]:
     for dy in [-.005,.005]:
      ring_margin=minf(ring_margin,edge_margin(game,Vector3(x+dx,.025+dy,dz),dims,top,bottom))
  check(skin_margin>=-0.5,"%s %d actual weighted poses bothwalls/faces fit, margin %.3fpx %s"%[str(dims),samples.size(),skin_margin,worst])
  check(cake_margin>=-0.5,"%s cake spawn/drop envelope fits margin %.3fpx"%[str(dims),cake_margin])
  check(ring_margin>=-0.5,"%s warning ring envelope fits margin %.3fpx"%[str(dims),ring_margin])
  all_margin=minf(all_margin,minf(skin_margin,minf(cake_margin,ring_margin)))
  rows.append({"viewport":[dims.x,dims.y],"skin_min_px":skin_margin,"cake_min_px":cake_margin,"ring_min_px":ring_margin,"worst_skin_sample":worst,"hud_bottom":top,"touch_top":bottom})
 var output={"checks":checks,"failures":failures,"actual_weighted_samples":samples.size(),"minimum_pixel_margin":all_margin,"rows":rows,"runtime_sha256":FileAccess.get_sha256("res://assets/ha.glb"),"limits":"Headless mathematical projection of actual weighted skin and bounded effects; not browser or phone hardware acceptance."}
 FileAccess.open("res://qa-ha-rules/CAMERA-BOUNDS.json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
 game.queue_free();await process_frame
 print("HA CAMERA bounds checks=",checks," failures=",failures," minimum_px=",all_margin)
 quit(failures)
