extends SceneTree
class QuietOpponent extends RefCounted:
 func reset():pass
 func act(_s,_d):return {}
var game
var checks:=0
var failures:Array=[]
var metrics:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func touch(id:int,v:Vector2,on:bool,cancel:=false):
 var e=InputEventScreenTouch.new();e.index=id;e.position=point(v);e.pressed=on;e.canceled=cancel;root.push_input(e,true)
func drag(id:int,v:Vector2):
 var e=InputEventScreenDrag.new();e.index=id;e.position=point(v);root.push_input(e,true)
func point(v:Vector2)->Vector2:return game.hud._direction_pad.get_global_rect().get_center()+v*game.hud._direction_pad.size.x*.5
func tick(n:=1):
 for i in range(n):game._physics_process(1.0/60.0)
func key(code:int,on:bool):
 var e=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=on;root.push_input(e,true)
func main_inputs_released()->bool:
 for value in game.held.values():
  if bool(value):return false
 return game.taps.is_empty()
func choose(kind:int):
 game.hud.opponent_choice=(kind+1)%3;game.hud._choose(kind);game.brain=QuietOpponent.new();game.set_physics_process(false)
 await process_frame;await process_frame
func run():
 root.size=Vector2i(844,337);game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false)
 for kind in range(3):
  await choose(kind);var label="kind"+str(kind)
  var x0:float=game.sim.fighters[0].x
  touch(1,Vector2(.65,-.65),true);tick(12)
  check(game.sim.fighters[0].y>.1 and game.sim.fighters[0].x>x0 and game.sim.fighters[0].vx>0,label+" direct diagonal jumps with horizontal heading")
  var early:Vector2=Vector2(game.sim.fighters[0].x,game.sim.fighters[0].y)
  for i in range(18):drag(1,Vector2(-.65,-.65));tick()
  check(game.sim.fighters[0].y>0 and game.sim.fighters[0].vx<0,label+" captured top drag reverses airborne velocity")
  tick(100);check(game.sim.fighters[0].y==0 and game.held.get("jump",false),label+" held up never auto jumps after landing")
  var rest_x:float=game.sim.fighters[0].x
  drag(1,Vector2.ZERO);tick();drag(1,Vector2(0,-.8));tick()
  check(game.sim.fighters[0].y>0,label+" return center and fresh up jumps again")
  touch(1,Vector2.ZERO,false);tick(100)
  touch(1,Vector2(0,.8),true);tick(15)
  check(game.sim.fighters[0].crouching and game.sim.fighters[0].crouch_amount>.9,label+" down holds actual crouch")
  touch(1,Vector2.ZERO,false);tick(15);check(not game.sim.fighters[0].crouching and game.sim.fighters[0].crouch_amount<.01,label+" release returns to stand")
  await choose(kind);key(KEY_A,true);touch(1,Vector2(.8,0),true);tick()
  check(game.held.get("left",false) and game.held.get("right",false),label+" keyboard and joystick remain independent sources")
  touch(1,Vector2.ZERO,false);tick();check(game.held.get("left",false) and not game.held.get("right",false),label+" releasing touch preserves keyboard hold")
  key(KEY_A,false);tick();check(not game.held.get("left",false),label+" keyboard release clears final source")
  touch(1,Vector2(.65,-.65),true);tick(3);root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
  check(game.paused and main_inputs_released() and game.hud._joystick_touch_id==-1 and game.hud._joystick_vector==Vector2.ZERO,label+" focus clears main input and HUD nub")
  if game.paused:game.toggle_pause()
  drag(1,Vector2(.65,-.65));check(game.taps.is_empty(),label+" stale drag after focus cannot recapture")
  await choose(kind);touch(1,Vector2(.8,0),true);game.toggle_pause()
  check(game.paused and game.hud._joystick_touch_id==-1 and game.hud._joystick_vector==Vector2.ZERO,label+" pause clears ownership visual")
  game.toggle_pause();touch(1,Vector2(0,-.8),true);tick();check(game.sim.fighters[0].y>0,label+" fresh touch after pause is accepted")
  game.show_menu();check(main_inputs_released() and game.hud._joystick_touch_id==-1 and game.hud._joystick_vector==Vector2.ZERO,label+" menu reset clears movement")
  metrics.append({"kind":kind,"early_jump_position":[early.x,early.y],"held_up_landed_x":rest_x})
 var f=FileAccess.open("res://exports/qa-v12/joystick/gameplay.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"characters":metrics,"scope":"actual native main loop with synthetic viewport input; quiet opponent is explicit fixture; not device or visual QA"},"  "));f.close()
 print("JOYSTICK_GAMEPLAY checks=",checks," failures=",failures.size()," characters=",metrics.size());game.queue_free();await process_frame;quit(failures.size())
