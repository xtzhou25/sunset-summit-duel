extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const Brain=preload("res://scripts/ai.gd")
const Baseline=preload("res://tests/ai_pre_height_gate.gd")
const DT=1.0/60.0
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _init():
 var stats:Dictionary={}
 for type in ["meow","rifle","heart"]:
  stats[type]={"before_jump":0,"after_jump":0,"before_guard":0,"after_guard":0,"after_hesitate":0,"fixtures":0}
  for face in [-1,1]:
   for offset in [0.0,1.5,2.0]:
    var location:float=-face*offset
    for seed_id in range(1,65):
     var before:Dictionary=fixture(Baseline,type,face,location,seed_id,"ground")
     var after:Dictionary=fixture(Brain,type,face,location,seed_id,"ground")
     stats[type].fixtures+=1
     stats[type].before_jump+=int(before.jump);stats[type].after_jump+=int(after.jump)
     stats[type].before_guard+=int(before.guard);stats[type].after_guard+=int(after.guard)
     stats[type].after_hesitate+=int(after.hesitate)
     check(before.guard==after.guard,"guard roll unchanged")
     check(before.early==false and after.early==false,"same finite observation delay")
     if type!="heart":check(not after.jump,"horizontal high projectile never chosen for impossible clearance")
     else:check(before.jump==after.jump,"descending feasible heart retains imperfect jump choice")
     for state in ["air","committed"]:
      var result:Dictionary=fixture(Brain,type,face,location,seed_id,state)
      check(not result.projectile_jump,"no projectile jump while airborne or committed")
  check(stats[type].before_jump>0,"baseline includes attempted jump choice")
  check(stats[type].after_guard>0 and stats[type].after_guard<stats[type].fixtures,"not perfect guard conversion")
 var brain=Brain.new()
 var actual_apex:float=Combat.JUMP_VELOCITY*Combat.JUMP_VELOCITY/(2.0*Combat.GRAVITY)
 check(is_equal_approx(Brain.MAX_JUMP_CLEAR_HEIGHT,actual_apex+.15-.03),"derived envelope tracks same physics")
 check(not brain.jump_clearance_feasible({"threat_vx":0,"threat_y":1,"threat_distance":1}),"stationary malformed threat safe")
 check(not brain.jump_clearance_feasible({"threat_vx":3.6,"threat_y":.1,"threat_distance":1}),"below hurtbox needs no clearance")
 check(brain.jump_clearance_feasible({"threat_vx":3.6,"threat_y":1.2,"threat_distance":1}),"low horizontal shot can remain jump candidate")
 check(not brain.jump_clearance_feasible({"threat_vx":3.6,"threat_y":1.4,"threat_distance":1}),"above envelope rejected")
 # Mutating fresh public height must not bypass the delayed snapshot.
 for face in [-1,1]:
  var a=make_world("heart",face,0,"ground");var b=make_world("heart",face,0,"ground")
  var ba=Brain.new();var bb=Brain.new();ba.rng.seed=17;bb.rng.seed=17;ba.reset();bb.reset()
  for frame in range(10):check(ba.act(a,DT)==bb.act(b,DT),"same initial observation")
  b.projectiles[0].pos.y=1.548;b.projectiles[0].velocity.y=0
  for frame in range(13):check(ba.act(a,DT)==bb.act(b,DT),"new public height not read before delay")
 stats.checks=checks;stats.failures=failures;stats.clearance_height=Brain.MAX_JUMP_CLEAR_HEIGHT
 var file=FileAccess.open("res://exports/qa-matchup/ai-height-gate.json",FileAccess.WRITE);file.store_string(JSON.stringify(stats,"  "));file.close()
 print("AI HEIGHT GATE ",JSON.stringify(stats));quit(failures)
func make_world(type:String,face:int,location:float,state:String):
 var sim=Combat.new();var self_f:Dictionary=sim.fighters[1];var enemy:Dictionary=sim.fighters[0]
 self_f.x=location;enemy.x=location+face*2.0;self_f.face=face
 if state=="air":self_f.y=.7
 if state=="committed":self_f.attack="heavy";self_f.attack_id=42;self_f.duration=.94;self_f.clock=.1
 var y:float=1.499 if type=="meow" else 1.548
 var vy:=0.0
 if type=="heart":y=2.0;vy=-2.5
 sim.projectiles=[{"id":1,"owner":0,"kind":type,"pos":Vector2(location+face*1.5,y),"velocity":Vector2(-face*3.6,vy)}]
 return sim
func fixture(script,type:String,face:int,location:float,seed_id:int,state:String)->Dictionary:
 var sim=make_world(type,face,location,state);var brain=script.new();brain.rng.seed=seed_id;brain.reset()
 var out={"jump":false,"projectile_jump":false,"guard":false,"hesitate":false,"early":false}
 for frame in range(20):
  var cmd:Dictionary=brain.act(sim,DT)
  if frame<14 and (cmd.get("jump",false) or cmd.move!=0):out.early=true
  if brain.intent=="projectile_jump":out.jump=true;out.projectile_jump=true
  if brain.intent=="projectile_guard":out.guard=true
  if brain.intent=="projectile_hesitate":out.hesitate=true
  if state=="committed":check(sim.fighters[1].attack=="heavy" and sim.fighters[1].attack_id==42,"committed action unchanged")
 check(brain.snapshots.size()<=16,"bounded history")
 brain.reset();check(brain.last_projectile_id==-1 and brain.snapshots.is_empty(),"reset drops threat")
 return out
