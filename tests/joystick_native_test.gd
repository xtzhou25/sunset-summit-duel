extends SceneTree
const HUD=preload("res://scripts/hud.gd")
const DIRS=["left","right","jump","crouch"]
const ATTACKS=["punch","kick","heavy","roundhouse","special"]
var hud
var checks:=0
var failures:Array=[]
var commands:Array=[]
var cases:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func settle():
 await process_frame;await process_frame;await process_frame
func touch(id:int,p:Vector2,on:bool,cancel:=false):
 var e=InputEventScreenTouch.new();e.index=id;e.position=p;e.pressed=on;e.canceled=cancel;root.push_input(e,true)
func drag(id:int,p:Vector2):
 var e=InputEventScreenDrag.new();e.index=id;e.position=p;root.push_input(e,true)
func mouse(v:Vector2,on:bool):
 var e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.button_mask=MOUSE_BUTTON_MASK_LEFT if on else 0;e.position=point(v);e.global_position=e.position;e.pressed=on;root.push_input(e,true)
func mouse_drag(v:Vector2,on:=true):
 var e=InputEventMouseMotion.new();e.position=point(v);e.global_position=e.position;e.button_mask=MOUSE_BUTTON_MASK_LEFT if on else 0;root.push_input(e,true)
func point(v:Vector2)->Vector2:return hud._direction_pad.get_global_rect().get_center()+v*hud._direction_pad.size.x*.5
func held(a:String)->bool:return bool(hud._sent_actions.get(a,false))
func dirs()->Array:
 var out:Array=[]
 for a in DIRS:
  if held(a):out.append(a)
 return out
func equal_dirs(wanted:Array)->bool:
 var actual=dirs();actual.sort();wanted=wanted.duplicate();wanted.sort();return actual==wanted
func center_ok()->bool:return hud._joystick_vector.length()<.001 and hud._joystick_nub.get_global_rect().get_center().distance_to(hud._direction_pad.get_global_rect().get_center())<.1
func fresh():hud._clear_touches();commands.clear()
func run():
 hud=HUD.new();root.add_child(hud);hud.command.connect(func(a,on):commands.append([a,on]))
 for dims in [Vector2i(568,267),Vector2i(844,337),Vector2i(375,614),Vector2i(390,791),Vector2i(960,600),Vector2i(1280,800)]:
  root.size=dims;hud.show_menu();await settle();hud._choose(2);hud.set_match({"special_kind":2,"special_cd":0.0});await settle()
  var label=str(dims);var pad:Rect2=hud._direction_pad.get_global_rect();var panel:Rect2=hud._touch_panel.get_global_rect()
  check(panel.grow(.6).encloses(pad) and pad.size.x>=44 and is_equal_approx(pad.size.x,pad.size.y),label+" fixed base fits reserved controls")
  check(center_ok(),label+" nub centered initially")
  var layout_ok:=true
  for a in ATTACKS:
   var rect:Rect2=hud._touch_buttons[a].get_global_rect()
   layout_ok=layout_ok and panel.grow(.6).encloses(rect) and rect.size.x>=44 and rect.size.y>=44 and not rect.intersects(pad)
  check(layout_ok,label+" five independent attacks fit >=44px without base overlap")
  for item in [[Vector2.ZERO,[]],[Vector2(-.8,0),["left"]],[Vector2(.8,0),["right"]],[Vector2(0,-.8),["jump"]],[Vector2(0,.8),["crouch"]],[Vector2(-.65,-.65),["left","jump"]],[Vector2(.65,-.65),["right","jump"]],[Vector2(-.65,.65),["left","crouch"]],[Vector2(.65,.65),["right","crouch"]]]:
   fresh();touch(1,point(item[0]),true);check(equal_dirs(item[1]),label+" direction "+str(item[0]));touch(1,point(item[0]),false);check(equal_dirs([]) and center_ok(),label+" direction release "+str(item[0]))
  fresh();touch(1,point(Vector2.ZERO),true)
  for v in [Vector2(.1,0),Vector2(0,-.15),Vector2(.16,.08),Vector2(-.1,.12)]:drag(1,point(v))
  check(commands.is_empty() and equal_dirs([]),label+" center jitter emits no directions")
  drag(1,point(Vector2(.45,0)));drag(1,point(Vector2(.32,0)));check(equal_dirs(["right"]),label+" axis hysteresis preserves accepted right")
  drag(1,point(Vector2(.20,0)));drag(1,point(Vector2(.32,0)));check(equal_dirs([]),label+" neutral re-entry below axis enter remains neutral")
  drag(1,point(Vector2(.65,-.65)));var starts=commands.count(["jump",true])
  for i in range(20):drag(1,point(Vector2(.6 if i%2==0 else -.6,-.7)))
  check(commands.count(["jump",true])==starts and held("jump"),label+" repeated top drag does not repeat jump")
  drag(1,point(Vector2.ZERO));drag(1,point(Vector2(0,-.8)));check(commands.count(["jump",true])==starts+1,label+" center then up makes one new jump edge")
  fresh();touch(1,point(Vector2(-.8,0)),true);touch(2,point(Vector2(.8,0)),true);drag(2,point(Vector2(0,-.8)))
  check(equal_dirs(["left"]) and hud._joystick_touch_id==1,label+" second base finger cannot steal or merge")
  touch(1,point(Vector2.ZERO),false);drag(2,point(Vector2(.8,0)));check(equal_dirs([]) and center_ok(),label+" ignored second finger cannot inherit capture")
  touch(2,point(Vector2.ZERO),false)
  for a in ATTACKS:
   fresh();var attack:Vector2=hud._touch_buttons[a].get_global_rect().get_center();touch(1,point(Vector2(-.65,-.65)),true);touch(2,attack,true)
   check(held(a) and equal_dirs(["left","jump"]),label+" second-finger "+a)
   touch(2,attack,false);check(not held(a) and equal_dirs(["left","jump"]),label+" attack release retains owner "+a)
  fresh();touch(1,point(Vector2(.8,0)),true);var attack_center:Vector2=hud._touch_buttons["heavy"].get_global_rect().get_center();drag(1,attack_center)
  check(not held("heavy") and hud._joystick_touch_id==1 and hud._joystick_vector.length()<=1.001,label+" owner drag beyond base clamps and never becomes attack")
  check(hud._direction_pad.get_global_rect()==pad and pad.grow(.6).encloses(hud._joystick_nub.get_global_rect()),label+" fixed base never floats and clamped nub stays inside")
  touch(1,Vector2(-1000000,-1000000),false,true);check(equal_dirs([]) and center_ok() and hud._joystick_touch_id==-1,label+" cancellation recenters and clears ownership")
  fresh();touch(3,pad.position-Vector2(10,10),true);drag(3,point(Vector2(0,-.8)));check(equal_dirs([]) and hud._joystick_touch_id==-1,label+" outside-origin drag cannot acquire joystick");touch(3,point(Vector2.ZERO),false)
  fresh();mouse(Vector2(-.8,0),true);touch(1,point(Vector2(.8,0)),true);drag(1,point(Vector2(0,-.8)))
  check(equal_dirs(["left"]) and hud._mouse_direction_active and hud._joystick_touch_id==-1,label+" touch cannot steal mouse joystick")
  mouse_drag(Vector2(.65,-.65));check(equal_dirs(["right","jump"]),label+" mouse drag steers and jumps")
  mouse(Vector2.ZERO,false);drag(1,point(Vector2(.8,0)));check(equal_dirs([]) and center_ok(),label+" ignored touch does not inherit mouse release")
  touch(1,point(Vector2.ZERO),false)
  fresh();touch(1,point(Vector2(-.8,0)),true);mouse(Vector2(.8,0),true);mouse_drag(Vector2(0,-.8))
  check(equal_dirs(["left"]) and hud._joystick_touch_id==1 and not hud._mouse_direction_active,label+" mouse cannot steal captured touch")
  mouse(Vector2.ZERO,false);touch(1,point(Vector2.ZERO),false);check(equal_dirs([]) and center_ok(),label+" mixed mouse touch release clean")
  fresh();touch(1,point(Vector2(-.8,0)),true);touch(2,attack_center,true);touch(1,point(Vector2.ZERO),false)
  check(equal_dirs([]) and held("heavy") and center_ok(),label+" releasing owner preserves attack finger")
  touch(2,attack_center,false);check(not held("heavy"),label+" independent attack final release")
  fresh();touch(2,attack_center,true);drag(2,point(Vector2(0,-.8)))
  check(not held("heavy") and equal_dirs([]) and hud._joystick_touch_id==-1,label+" attack finger cannot slide into joystick")
  drag(2,point(Vector2(.8,0)));check(equal_dirs([]),label+" canceled attack drag cannot acquire later");touch(2,point(Vector2.ZERO),false)
  fresh();mouse(Vector2(.8,0),true);mouse_drag(Vector2(.8,0),false)
  check(equal_dirs([]) and center_ok() and not hud._mouse_direction_active,label+" missing mouse button mask cancels capture")
  for kind in ["pause","focus","menu","resize"]:
   fresh();touch(1,point(Vector2(.65,-.65)),true);touch(2,attack_center,true)
   if kind=="pause":hud.set_paused(true)
   elif kind=="focus":hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
   elif kind=="menu":hud.show_menu()
   else:hud._resize()
   check(equal_dirs([]) and not held("heavy") and center_ok() and hud._joystick_touch_id==-1,label+" "+kind+" clears both contacts and visual")
   drag(1,point(Vector2(0,-.8)));check(equal_dirs([]),label+" stale drag after "+kind+" cannot reacquire")
   hud.set_paused(false);hud._choose(2);await settle()
  cases.append({"viewport":str(dims),"base_px":pad.size.x,"checks_so_far":checks})
 var f=FileAccess.open("res://exports/qa-v12/joystick/native.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"layouts":cases,"scope":"native synthetic events through viewport, not physical touch hardware"},"  "));f.close()
 print("JOYSTICK_NATIVE checks=",checks," failures=",failures.size()," layouts=",cases.size());hud.queue_free();await process_frame;quit(failures.size())
