extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const Brain=preload("res://scripts/ai.gd")
const OldBrain=preload("res://tests/p3_baseline_ai.gd")
const DT=1.0/60.0
var failures:=0
var checks:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok: failures+=1; printerr("FAIL ",label)
func _init():
 var report={"scope":"Deterministic fixed-60Hz rules audit, not native rendering or phone performance","before":[],"after":[]}
 for version in range(2):
  for kind in range(2):
   for policy in range(5):
    for seed_id in range(1,9):
     var first=run_round(version,kind,policy,seed_id)
     var second=run_round(version,kind,policy,seed_id)
     check(first==second,"identical seed reproducible")
     report["before" if version==0 else "after"].append(first)
 rule_tests()
 report.checks=checks;report.failures=failures
 var file=FileAccess.open("res://exports/qa-p3/rhythm-metrics.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 print("P3 AUDIT checks=",checks," failures=",failures)
 quit(failures)
func run_round(version:int,kind:int,policy:int,seed_id:int)->Dictionary:
 var s=Combat.new();s.reset(kind)
 var brain=OldBrain.new() if version==0 else Brain.new();brain.rng.seed=seed_id*1717+33;brain.reset()
 var distances:Array=[];var close:=0;var lost:=[0,0];var longest:=[0,0];var moves={};var ids:=[-1,-1];var frame_count:=0
 for frame in range(3650):
  var me:Dictionary=s.fighters[0];var foe:Dictionary=s.fighters[1]
  var face:=1.0 if foe.x>me.x else -1.0
  var dist:float=absf(foe.x-me.x)
  var cmd={"move":face if dist>0.77 else 0.0}
  match policy:
   0:cmd.punch=frame%15==0;cmd.heavy=frame%83==0;cmd.roundhouse=frame%113==0;cmd.special=frame%251==0;cmd.jump=frame%137==0
   1:cmd.punch=true
   2:cmd.heavy=frame%2==0
   3:cmd.move=-face;cmd.special=frame%2==0
   4:cmd.jump=frame%53==0;cmd.move=face if frame%180<100 else -face;cmd.kick=frame%43==0
  s.step(DT,[cmd,brain.act(s,DT)])
  frame_count+=1;distances.append(absf(s.fighters[0].x-s.fighters[1].x))
  if distances[-1]<1.0:close+=1
  for i in range(2):
   var f:Dictionary=s.fighters[i]
   if f.hp>0 and (f.stun>0 or f.down):lost[i]+=1;longest[i]=maxi(longest[i],lost[i])
   else:lost[i]=0
   if f.attack!="" and f.attack_id!=ids[i]:
    ids[i]=f.attack_id;var key=str(i)+"_"+f.attack;moves[key]=moves.get(key,0)+1
   check(f.x>=Combat.LEFT and f.x<=Combat.RIGHT and f.y>=0,"bounds")
  if s.round_over:break
 check(s.round_over,"round terminates")
 distances.sort()
 return {"kind":kind,"policy":policy,"seed":seed_id,"frames":frame_count,"round_seconds":frame_count*DT,"winner":s.winner,"close_fraction":float(close)/frame_count,"distance_p10":distances[int(distances.size()*.1)],"distance_median":distances[int(distances.size()*.5)],"distance_p90":distances[int(distances.size()*.9)],"max_loss_seconds":[longest[0]*DT,longest[1]*DT],"moves":moves}
func rule_tests():
 for kind in range(2):
  for move in ["punch","heavy","roundhouse","special"]:
   var s=Combat.new();s.reset(kind);s.time_left=600;s.fighters[0].hp=10000;s.fighters[1].hp=10000;s.fighters[0].x=-1.9;s.fighters[1].x=1.9
   var seen={}
   for f in range(360):
    s.step(DT,[{move:true},{}]);var a:Dictionary=s.fighters[0]
    if a.attack!="":seen[a.attack_id]=true
   check(seen.size()==1,"holding "+move+" produces only one attack")
  for move in ["heavy","roundhouse","kick"]:
   var s=Combat.new();s.reset(kind);var cfg:Dictionary=s.attack_config(s.fighters[0],move)
   check(cfg.recovery>=.4,"large reward move has >=400ms recovery")
   check(cfg.startup>=.28,"large reward move has readable startup")
 # Public snapshots ignore private player keys and queues, even when mutated.
 var a=Combat.new();var b=Combat.new();var ba=Brain.new();var bb=Brain.new();ba.reset();bb.reset()
 for frame in range(180):
  b.fighters[0].queued="straight";b.fighters[0].punch_held=frame%2==0;b.fighters[0].input_rearm=true
  check(ba.act(a,DT)==bb.act(b,DT),"does not read player private inputs")
 # One delayed public projectile must not guarantee defense across seeds.
 var choices={"guard":0,"jump":0,"none":0}
 for seed_id in range(1,65):
  var s=Combat.new();s.fighters[0].x=-1;s.fighters[1].x=1
  s.projectiles=[{"id":1,"owner":0,"pos":Vector2(-.5,1.2),"velocity":Vector2(3.6,0)}]
  var brain=Brain.new();brain.rng.seed=seed_id;brain.reset();var choice="none"
  for frame in range(16):
   var cmd:Dictionary=brain.act(s,DT)
   if frame<14:check(not cmd.get("jump",false) and cmd.move==0,"projectile observation delay")
   if brain.intent=="projectile_guard":choice="guard"
   elif brain.intent=="projectile_jump":choice="jump"
  choices[choice]+=1
 check(choices.guard>0 and choices.jump>0 and choices.none>0,"ranged response is varied and imperfect")
 print("Projectile response fixtures ",choices)
