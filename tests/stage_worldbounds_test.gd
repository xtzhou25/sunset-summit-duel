extends SceneTree
## Finite deterministic simulation gate. No live scene or production mutations.
const Combat=preload("res://scripts/combat.gd")
const Brain=preload("res://scripts/ai.gd")
const Characters=preload("res://scripts/characters.gd")
const DT:=1.0/60.0
var checks:=0
var failures:=0
var messages:Array=[]
var rows:Array=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:
  failures+=1
  if not messages.has(label):messages.append(label);printerr("FAIL ",label)
func _init():
 for a in range(5):
  for b in range(5):
   if a==b:continue
   var first:Dictionary=play(a,b,6127)
   var repeated:Dictionary=play(a,b,6127)
   check(first==repeated,"deterministic replay %d/%d"%[a,b])
   rows.append(first)
 for side in [-1.0,1.0]:
  wall_case(side)
  cake_case(side)
 var out:={"checks":checks,"failures":failures,"failure_labels":messages,"ordered_pairs":rows,"bounds":[Combat.LEFT,Combat.RIGHT],"scope":"headless deterministic simulation; no browser or device claim"}
 var dest:="res://exports/qa-stage/worldbounds.json"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):dest=arg.trim_prefix("--output=")
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest.get_base_dir()))
 FileAccess.open(dest,FileAccess.WRITE).store_string(JSON.stringify(out,"  "))
 print("STAGE_WORLD checks=",checks," failures=",failures," pairs=",rows.size()," repeated=20")
 quit(1 if failures else 0)
func play(a:int,b:int,seed_id:int)->Dictionary:
 var sim=Combat.new();sim.reset(a,b)
 var bot=Brain.new();bot.rng.seed=seed_id;bot.reset()
 var casts:Dictionary={};var spawns:Dictionary={};var emissions:Dictionary={};var frames:=0
 for frame in range(3650):
  var f:Dictionary=sim.fighters[0];var o:Dictionary=sim.fighters[1]
  var face:float=1.0 if o.x>f.x else -1.0
  var cmd:Dictionary={"move":face if absf(o.x-f.x)>.78 else 0.0,"punch":frame%23==0,"heavy":frame%83==0,"roundhouse":frame%113==0,"kick":frame%97==0,"special":frame%251==0,"jump":frame%137==0,"crouch":frame%157>=145}
  if frame%500>=400:cmd.move=-face
  sim.step(DT,[cmd,bot.act(sim,DT)]);frames=frame+1
  for actor:Dictionary in sim.fighters:
   check(is_finite(actor.x) and is_finite(actor.y) and actor.x>=Combat.LEFT-.00001 and actor.x<=Combat.RIGHT+.00001 and actor.y>=0,"finite world bounds")
   check(actor.hp>=0 and actor.hp<=100 and actor.guard>=0 and actor.guard<=100,"bounded resources")
   check(not(actor.blocking and actor.y>.001),"no aerial guard")
  check(absf(sim.fighters[0].x-sim.fighters[1].x)<=Combat.SEPARATION_MAX+.000001,"live pair shared-window maximum")
  if sim.fighters[0].y<=.001 and sim.fighters[1].y<=.001:
   check(absf(sim.fighters[0].x-sim.fighters[1].x)>=Combat.BODY*2-.00001,"grounded pushboxes separated")
  for event:Dictionary in sim.events:
   if event.type=="attack" and event.kind=="special":casts[event.attack_id]=true
   if event.type=="projectile_spawn":
    check(not spawns.has(event.attack_id) and casts.has(event.attack_id),"one emission per committed cast")
    spawns[event.attack_id]=true
    var kind:String=Characters.get_character(sim.fighters[int(event.source)].kind).special_kind
    check(event.kind==kind,"role-correct special identity")
    emissions[kind]=int(emissions.get(kind,0))+1
  check(sim.projectiles.size()<=2,"bounded projectile count")
  for p:Dictionary in sim.projectiles:
   check(p.pos.is_finite() and p.pos.x>=Combat.LEFT-.00001 and p.pos.x<=Combat.RIGHT+.00001 and p.pos.y>=0,"projectiles in world")
   check(p.age<=Combat.PROJECTILE_LIFETIME+.00001 and p.distance<=Combat.PROJECTILE_RANGE+.00001,"unchanged projectile lifetime and range")
  if sim.round_over:break
 check(sim.round_over,"finite round termination")
 return {"pair":[a,b],"frames":frames,"winner":sim.winner,"emissions":emissions,"fighters":sim.fighters.duplicate(true)}
func wall_case(side:float):
 var sim=Combat.new();sim.reset(2,3)
 var bound:float=Combat.RIGHT if side>0 else Combat.LEFT
 sim.fighters[0].x=bound-side*.7;sim.fighters[1].x=bound
 for n in range(240):
  sim.step(DT,[{"move":side},{"move":side}])
  check(absf(sim.fighters[0].x-sim.fighters[1].x)>=Combat.BODY*2-.00001,"wall separation")
  for f:Dictionary in sim.fighters:check(f.x>=Combat.LEFT-.00001 and f.x<=Combat.RIGHT+.00001,"wall clamping")
 sim.reset(2,3);sim.fighters[0].x=-.35;sim.fighters[1].x=.35
 var crossed:=false
 for n in range(65):
  sim.step(DT,[{"move":1.0,"jump":n==0},{"move":-1.0}])
  crossed=crossed or (sim.fighters[0].x>sim.fighters[1].x and sim.fighters[0].y>Combat.AIR_PASS_HEIGHT)
 check(crossed,"actual jump crossover remains possible")
 check(sim.fighters[0].y==0 and absf(sim.fighters[0].x-sim.fighters[1].x)>=Combat.BODY*2-.00001,"crossover lands separated")
func cake_case(side:float):
 var sim=Combat.new();sim.reset(4,2)
 var target:float=Combat.RIGHT if side>0 else Combat.LEFT
 sim.fighters[1].x=target;sim.fighters[0].x=target-side*1.2
 sim.step(DT,[{"special":true},{}])
 check(absf(sim.fighters[0].cake_target_x-target)<.00001,"cake locks new world edge")
 var count:=0
 for n in range(100):
  sim.step(DT,[{},{}])
  for e:Dictionary in sim.events:
   if e.type=="projectile_spawn":count+=1;check(absf(e.pos.x-target)<.00001,"cake spawns at locked world edge")
 check(count==1 and sim.fighters[1].hp==88,"edge cake single hit")
 sim.reset(4,2)
 check(sim.projectiles.is_empty() and sim.cake_warnings().is_empty() and sim.fighters[0].x==-1.3 and sim.fighters[1].x==1.3,"reset clears cake and restores centered spawn")
