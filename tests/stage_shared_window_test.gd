extends SceneTree
const C=preload("res://scripts/combat.gd")
const Brain=preload("res://scripts/ai.gd")
const DT:=1.0/60.0
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _init():
 for side in [-1.0,1.0]:
  var s=C.new();s.reset(2,3)
  s.fighters[0].x=-2.6*side;s.fighters[1].x=2.6*side
  var other:float=s.fighters[1].x
  var first_delta:=0.0;var last_delta:=0.0
  for frame in range(300):
   var old:float=s.fighters[0].x
   s.step(DT,[{"move":-side},{}])
   var shift:float=absf(s.fighters[0].x-old)
   if frame==0:first_delta=shift
   if frame==299:last_delta=shift
   check(absf(s.fighters[0].x-s.fighters[1].x)<=C.SEPARATION_MAX+.000001,"unilateral retreat never exceeds shared maximum")
   check(s.fighters[1].x==other,"retreat never drags stationary rival")
  check(first_delta>.01 and last_delta<first_delta*.01,"retreat tapers smoothly toward cap")
  var gap:float=absf(s.fighters[0].x-s.fighters[1].x)
  s.step(DT,[{"move":side},{}])
  check(absf(s.fighters[0].x-s.fighters[1].x)<gap-.02,"inward motion remains immediately available at cap")
  s.reset(2,3);s.fighters[0].x=-2.8;s.fighters[1].x=2.8
  var positions:Array=[s.fighters[0].x,s.fighters[1].x]
  s.step(DT,[{"move":side},{"move":side}])
  check(signf(s.fighters[0].x-positions[0])==side and signf(s.fighters[1].x-positions[1])==side,"both same-direction commands move both actors")
  check(absf(s.fighters[0].x-s.fighters[1].x)<5.6,"same-direction movement preserves inward relative gain")
 # Direct presentation-independent limiter contract: exact equal translation unchanged.
 var s=C.new();s.reset(0,1)
 for shift in [-.04,.04]:
  s.fighters[0].x=-2.9+shift;s.fighters[1].x=2.9+shift
  s.fighters[0].y=.7;s.fighters[0].vy=1.2
  var before:Array=s.fighters.duplicate(true)
  s._limit_shared_window([-2.9,2.9])
  check(s.fighters==before,"common translation and all non-x state unchanged")
 s.fighters[0].x=-4.2;s.fighters[1].x=4.2
 s._limit_shared_window([-4.2,4.2])
 check(s.fighters[0].x==-4.2 and s.fighters[1].x==4.2,"diagnostic preexisting wide fixture never teleports")
 # Real jump crossing near shared cap follows the same vertical parabola as close center.
 var narrow=C.new();narrow.reset(2,3);narrow.fighters[0].x=-.35;narrow.fighters[1].x=.35
 s.reset(2,3);s.fighters[0].x=-2.8;s.fighters[1].x=2.8
 for frame in range(65):
  var command:Dictionary={"move":-1.0,"jump":frame==0}
  narrow.step(DT,[command,{}]);s.step(DT,[command,{}])
  check(is_equal_approx(s.fighters[0].y,narrow.fighters[0].y) and is_equal_approx(s.fighters[0].vy,narrow.fighters[0].vy),"shared window leaves actual jump y/vy unchanged")
 var approaches:Array=[]
 for side in [-1.0,1.0]:
  s.reset(0,1);s.fighters[0].x=-2.9*side;s.fighters[1].x=2.9*side
  var bot=Brain.new();bot.rng.seed=6127;bot.reset()
  var reached:=false;var seconds:=0.0
  for frame in range(360):
   s.step(DT,[{},bot.act(s,DT)])
   seconds=(frame+1)*DT
   if absf(s.fighters[0].x-s.fighters[1].x)<=1.35:reached=true;break
  check(reached and seconds<6.0,"AI approaches from maximum shared gap within six seconds")
  approaches.append({"side":side,"seconds_to_1_35m":seconds,"reached":reached})
 var out:={"checks":checks,"failures":failures,"ai_approach":approaches,"seed":6127,"scope":"headless deterministic actual simulation with stationary player and unchanged AI"}
 FileAccess.open("res://exports/qa-stage/shared-window.json",FileAccess.WRITE).store_string(JSON.stringify(out,"  "))
 print("STAGE_SHARED_WINDOW checks=",checks," failures=",failures," approach=",approaches)
 quit(1 if failures else 0)
