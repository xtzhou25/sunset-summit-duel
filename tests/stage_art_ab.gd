extends Node
## Controlled graphical fixture only. No simulation steps, AI, attacks or production writes.
const MODES:=["original","batched","original","batched"]
const BLOCK_SECONDS:=30.0
const WARMUP_SECONDS:=5.0
var game
var active:=false
var block_started:=0
var block_index:=-1
var previous_draw:=0
var frame_ms:Array=[]
var samples:Array=[]
var captures:Array=[]
var results:Array=[]
var draw_count:=0
var last_second:=-1
var captured:=false
var hashes:Dictionary={}
var errors:Array=[]
func _ready():
 RenderingServer.frame_post_draw.connect(frame_drawn)
 call_deferred("run")
func check(ok:bool,label:String):
 if not ok and not errors.has(label):errors.append(label);printerr("FAIL ",label)
func fixture_hashes()->Dictionary:
 var h:Dictionary={}
 for file in ["fan_band_original","fan_band_batched","expanded_livehouse_original","expanded_livehouse_batched"]:
  h[file]=FileAccess.get_sha256("res://tests/art_ab_variants/"+file+".gd")
 for file in ["main","combat","ai","stage","fight_camera","hud"]:
  h[file]=FileAccess.get_sha256("res://scripts/"+file+".gd")
 return h
func run():
 DirAccess.make_dir_recursive_absolute("res://exports/qa-stage/art-ab")
 hashes=fixture_hashes()
 get_tree().root.size=Vector2i(1280,800)
 game=load("res://main.tscn").instantiate();add_child(game)
 await get_tree().process_frame
 game.set_physics_process(false);game.hud.opponent_choice=3;game.hud._choose(4);game.set_physics_process(false)
 game.shake_enabled=true;game.paused=false
 for index in range(MODES.size()):
  active=false;block_index=index
  if is_instance_valid(game.stage):game.stage.queue_free()
  await get_tree().process_frame;await get_tree().process_frame
  game.stage=load("res://tests/art_ab_variants/expanded_livehouse_"+MODES[index]+".gd").new()
  game.world.add_child(game.stage)
  await get_tree().process_frame;await get_tree().process_frame
  game.stage.set_process(false);game.stage.motion_active=true;game.stage.reduce_motion=false
  game.sim.fighters[0].x=-1.0;game.sim.fighters[1].x=1.0
  game.layout_camera();game.render_state(0.0)
  for anim in game.anims:anim.seek(.8,true);anim.advance(0.0)
  game.stage._clock=1.25;game.stage.audience.clock=1.25
  game.stage._process(0.0)
  game.stage.update_view(game.camera,game.hud._touch_panel.position.y,false)
  await RenderingServer.frame_post_draw
  await RenderingServer.frame_post_draw
  if index<2:
   var image:Image=game.get_viewport().get_texture().get_image()
   var path:String="res://exports/qa-stage/art-ab/static-%s.png"%MODES[index]
   var error:int=image.save_png(path)
   captures.append({"block":index,"path":path,"kind":"fixedclock1.25-camera0-staticpose0.8","dimensions":str(image.get_size()),"save_error":error,"band_top":game.stage.audience.band_top,"band_bottom":game.stage.audience.band_bottom})
   check(error==OK,"static comparison PNG saved")
   check(image.get_size()==Vector2i(1280,800),"controlled viewport exactly1280x800")
  game.stage._clock=0.0;game.stage.audience.clock=0.0
  frame_ms=[];samples=[];draw_count=0;last_second=-1;captured=false
  block_started=Time.get_ticks_usec();previous_draw=block_started;active=true
  print("ART_AB_START block=",index," mode=",MODES[index])
  await get_tree().create_timer(BLOCK_SECONDS).timeout
  active=false
  var sorted:Array=frame_ms.duplicate();sorted.sort()
  check(not sorted.is_empty(),"actual rendered samples present")
  var row:={"block":index,"mode":MODES[index],"seconds":float(Time.get_ticks_usec()-block_started)/1000000.0,"warmup_seconds":WARMUP_SECONDS,"measured_rendered_frames":draw_count,"render_fps":float(draw_count)/(BLOCK_SECONDS-WARMUP_SECONDS),"frame_ms":frame_ms.duplicate(),"samples":samples.duplicate(true)}
  if not sorted.is_empty():
   row.frame_ms_p50=sorted[int(sorted.size()*.5)];row.frame_ms_p95=sorted[int(sorted.size()*.95)];row.frame_ms_p99=sorted[int(sorted.size()*.99)]
  results.append(row)
  print("ART_AB_DONE block=",index," mode=",MODES[index]," measured_fps=",row.render_fps)
 check(DisplayServer.get_name()!="headless","native graphical renderer required")
 check(hashes==fixture_hashes(),"fixture/runtime hashes unchanged throughout")
 var report:={"status":"pass" if errors.is_empty() else "fail","errors":errors,"display":DisplayServer.get_name(),"actual_viewport":str(game.get_viewport().get_visible_rect().size),"hashes":hashes,"ending_hashes":fixture_hashes(),"blocks":results,"captures":captures,"scope":"Controlled native art A/B: original/batched/original/batched, each30s with5s warmup; same fixedHa/TaoFightIdle pose and sinusoidal commontranslation; noAI/combat/events. Stage fans/lights retain animated clock. PNGs only duringwarmup. Not browser/phone or GPU-onlybenchmark."}
 FileAccess.open("res://exports/qa-stage/art-ab/results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("ART_AB_COMPLETE ",report.status)
 game.queue_free();await get_tree().process_frame;await get_tree().process_frame
 get_tree().quit(0 if errors.is_empty() else 1)
func _process(delta:float):
 if not active:return
 var elapsed:float=float(Time.get_ticks_usec()-block_started)/1000000.0
 var center:float=2.45*sin(elapsed*TAU/12.0)
 game.sim.fighters[0].x=center-1.0;game.sim.fighters[1].x=center+1.0
 game.update_fight_camera(delta);game.render_state(0.0)
 for anim in game.anims:anim.seek(.8,true);anim.advance(0.0)
 game.stage._process(delta)
 if elapsed>=4.0 and not captured:
  captured=true;capture.call_deferred(block_index)
 if elapsed>=WARMUP_SECONDS:
  var second:=int(elapsed)
  if second!=last_second:
   last_second=second
   samples.append({"elapsed":elapsed,"fps":Engine.get_frames_per_second(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"static_memory":OS.get_static_memory_usage(),"nodes":get_tree().get_node_count(),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"camera_x":game.camera.position.x,"camera_width":game.camera.size})
func frame_drawn():
 var now:=Time.get_ticks_usec()
 if active:
  var elapsed:float=float(now-block_started)/1000000.0
  if elapsed>=WARMUP_SECONDS and elapsed<=BLOCK_SECONDS:
   frame_ms.append(float(now-previous_draw)/1000.0);draw_count+=1
 previous_draw=now
func capture(index:int):
 await RenderingServer.frame_post_draw
 var image:Image=get_viewport().get_texture().get_image()
 var path:String="res://exports/qa-stage/art-ab/block-%d-%s.png"%[index,MODES[index]]
 var error:int=image.save_png(path)
 captures.append({"block":index,"path":path,"dimensions":str(image.get_size()),"save_error":error})
 check(error==OK,"warmup PNG saved")
