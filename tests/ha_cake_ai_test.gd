extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const Brain=preload("res://scripts/ai.gd")
const DT:=1.0/60.0
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _init():
 var branches:Dictionary={}
 for seed_id in range(180):
  var s=Combat.new();s.reset(4,0);s.fighters[0].x=-1.2;s.fighters[1].x=1.2
  var brain=Brain.new();brain.rng.seed=seed_id;brain.reset();s.begin_special(s.fighters[0])
  var responded:=false
  for n in range(45):
   # Freeze simulation motion to isolate AI delayed publicly visible warning.
   var command:Dictionary=brain.act(s,DT)
   if n<13:check(not brain.intent.begins_with("cake_"),"no early pre240ms cake decision")
   if brain.intent.begins_with("cake_") and not responded:
    responded=true;branches[brain.intent]=branches.get(brain.intent,0)+1
    check((n+1)*DT>=brain.reaction,"reaction delay respected")
    check(not command.get("jump",false),"no futile jump under overhead")
  check(responded,"one delayed cake decision available")
 check(branches.get("cake_guard",0)>20 and branches.get("cake_evade",0)>10 and branches.get("cake_hesitate",0)>30,"fallible outcomes retain guard/evade/error branches")
 for edge in [Combat.LEFT,Combat.RIGHT]:
  var observed_evade:=false
  for seed_id in range(50):
   var s=Combat.new();s.reset(4,0);s.fighters[0].x=0;s.fighters[1].x=edge;s.begin_special(s.fighters[0])
   var brain=Brain.new();brain.rng.seed=seed_id;brain.reset()
   for n in range(20):
    var c:Dictionary=brain.act(s,DT)
    if brain.intent=="cake_evade":
     observed_evade=true;check(float(c.move)==(1.0 if edge==Combat.LEFT else -1.0),"evade points into arena not wall");break
  check(observed_evade,"edge evade sampled")
 var s=Combat.new();s.reset(4,0);var brain=Brain.new();brain.reset();s.begin_special(s.fighters[0]);s.fighters[1].attack="heavy"
 for n in range(60):
  var c:Dictionary=brain.act(s,DT)
  check(not brain.intent.begins_with("cake_"),"committed attack cannot instantcancel for warning")
 brain.reset();check(brain.last_cake_attack_id==-1 and brain.snapshots.is_empty(),"reset clears warning observation")
 print("HA CAKE AI checks=",checks," failures=",failures," branches=",branches)
 quit(failures)
