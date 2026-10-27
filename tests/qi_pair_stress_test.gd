extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const Brain=preload("res://scripts/ai.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _init():
 var rounds:=0
 for a in range(3):
  for b in range(3):
   if a==b:continue
   for seed_id in range(8):
    var first:Dictionary=play(a,b,seed_id)
    var repeat:Dictionary=play(a,b,seed_id)
    check(first==repeat,"seed reproducibility "+str(a)+"/"+str(b)+" seed"+str(seed_id))
    rounds+=1
 print("QI PAIR STRESS rounds=",rounds," repeated=",rounds," checks=",checks," failures=",failures)
 quit(failures)
func play(a:int,b:int,seed_id:int)->Dictionary:
 var sim=Combat.new();sim.reset(a,b)
 var brain=Brain.new();brain.rng.seed=1717+seed_id;brain.reset()
 var special_casts:Dictionary={};var spawn_ids:Dictionary={};var elapsed:=0
 var rng:=RandomNumberGenerator.new();rng.seed=seed_id*53+101
 for frame in range(3650):
  var f:Dictionary=sim.fighters[0];var o:Dictionary=sim.fighters[1]
  var dist:float=absf(o.x-f.x);var face:float=1 if o.x>f.x else -1
  var cmd:Dictionary={"move":face if dist>0.8 else 0.0,"punch":frame%19==0,"heavy":frame%83==0,"roundhouse":frame%113==0,"kick":frame%97==0,"special":frame%251==0,"jump":frame%137==0,"crouch":frame%157>=145}
  if frame%500>=400:cmd.move=-face
  sim.step(1.0/60.0,[cmd,brain.act(sim,1.0/60.0)])
  elapsed=frame+1
  for actor:Dictionary in sim.fighters:
   check(actor.x>=Combat.LEFT and actor.x<=Combat.RIGHT and actor.y>=0,"finite arena")
   check(actor.hp>=0 and actor.hp<=100 and is_finite(actor.x) and is_finite(actor.y),"finite HP and positions")
  for event:Dictionary in sim.events:
   if event.type=="attack" and event.kind=="special":special_casts[event.attack_id]=true
   if event.type=="projectile_spawn":
    check(not spawn_ids.has(event.attack_id),"one projectile per cast across roles")
    check(special_casts.has(event.attack_id),"projectile follows committed cast")
    spawn_ids[event.attack_id]=true
    var role:int=sim.fighters[int(event.source)].kind
    check(event.kind==["meow","heart","rifle"][role],"projectile identity follows role not slot")
  check(sim.projectiles.size()<=2,"bounded projectiles with CD4")
  if sim.round_over:break
 check(sim.round_over,"full match terminates")
 return {"frames":elapsed,"winner":sim.winner,"fighters":sim.fighters.duplicate(true),"spawns":spawn_ids.duplicate()}
