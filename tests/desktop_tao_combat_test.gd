extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const Brain=preload("res://scripts/ai.gd")
const Characters=preload("res://scripts/characters.gd")
const DT=1.0/60.0
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _init():
 if not FileAccess.file_exists("res://assets/tao_surface_curves.json"):
  printerr("BLOCKED: final exported Tao skin curves unavailable");quit(2);return
 registry_tests()
 for source in range(2):
  for opponent in range(3):
   for face in [-1,1]:
    peach_tests(source,opponent,face)
 pair_melee_tests()
 stress_pairs()
 print("TAO COMBAT checks=",checks," failures=",failures)
 quit(failures)
func registry_tests():
 check(Characters.COUNT==5,"five stable roles")
 check(Characters.get_character(0).name=="因" and Characters.get_character(1).name=="鱼" and Characters.get_character(2).name=="七" and Characters.get_character(3).name=="桃","role names")
 check(Characters.default_opponent(3)==0 and Characters.default_opponent(0)==1 and Characters.default_opponent(1)==0 and Characters.default_opponent(2)==0,"legacy defaults")
 for first in range(4):
  for second in range(4):
   var s=Combat.new();s.reset(first,second)
   check(s.fighters[0].kind==first,"player role remains independent from slot")
   check(s.fighters[1].kind==(second if second!=first else Characters.default_opponent(first)),"explicit opponent or distinct fallback")
   check(s.fighters.size()==2,"two active slots, never three fighter assumption")
 var invalid=Combat.new();invalid.reset(99,-9)
 check(invalid.fighters[0].kind==4 and invalid.fighters[1].kind==0,"invalid registry values bounded")
 var surface:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/tao_surface_curves.json"))
 var hash:=FileAccess.get_sha256("res://assets/tao_surface_curves.json")
 check(hash==Characters.TAO_SURFACE_SOURCE_SHA256,"actual surface data pinned")
 for move in ["punch","straight","heavy"]:
  var clip:String={"punch":"Jab","straight":"Straight","heavy":"HeavyPunch"}[move]
  var hand:String="hand.L" if move=="punch" else "hand.R"
  var start:float={"punch":.14,"straight":.18,"heavy":.34}[move]
  var curve:Array=Characters.TAO_PUNCH_REACH_CURVES[move]
  for i in range(curve.size()):
   var at:=int(round((start+i*.01)*100))
   var expected:=minf(surface.clips[clip+"_R"][at][hand].forward_z[1],surface.clips[clip+"_L"][at][hand].forward_z[1])
   check(absf(curve[i]-expected)<1e-9,"own measured hand subset")
 for i in range(15):
  var p:Dictionary=surface.clips.RoundhouseKick_R[28+i]["foot.R"]
  var expected:Array=p.depth_x+p.height_y+p.forward_z
  for a in range(6):check(absf(Characters.TAO_ROUNDHOUSE_SURFACE_CURVES[i][a]-expected[a])<1e-9,"own measured foot subset")
func fixture(source:int,opponent:int,face:int):
 var s=Combat.new();s.reset(3 if source==0 else opponent,opponent if source==0 else 3)
 s.fighters[source].x=-1.2*face;s.fighters[1-source].x=1.2*face
 s.fighters[source].face=face;s.fighters[1-source].face=-face
 return s
func tick(s,source:int,frames:int,command:Dictionary={},other:Dictionary={})->Dictionary:
 var counts:Dictionary={}
 for n in range(frames):
  var inputs:Array=[{},{}];inputs[source]=command;inputs[1-source]=other;s.step(DT,inputs)
  for event:Dictionary in s.events:
   var key:String=event.type+":"+str(event.get("kind",""));counts[key]=counts.get(key,0)+1
 return counts
func peach_tests(source:int,opponent:int,face:int):
 var s=fixture(source,opponent,face);var f:Dictionary=s.fighters[source]
 var before:Dictionary=tick(s,source,1,{"special":true})
 check(f.attack=="special" and absf(f.duration-1.10)<1e-9,"peach accepted with explicit total")
 check(absf(f.special_emit_age-.42)<1e-9 and f.special_cooldown>3.9,"exact emission and immediate cooldown")
 var prior:Dictionary=tick(s,source,23)
 check(prior.get("projectile_spawn:peach",0)==0 and s.projectiles.is_empty(),"no peach before420ms")
 check(f.y==0 and f.vy==0,"peach does not inherit heart jump")
 var rest:Dictionary=tick(s,source,80)
 check(rest.get("projectile_spawn:peach",0)==1,"one peach per cast")
 check(s.fighters[1-source].hp==88,"peach contacts once for12")
 check(f.y==0 and f.attack=="","peach exits flat and recovers")
 check(rest.get("hit:peach",0)==1,"one damage event per fruit")
 check(f.special_cooldown>2.0,"cooldown continues after completion")
 s=fixture(source,opponent,face);f=s.fighters[source]
 var block:Dictionary=tick(s,source,110,{"special":true},{"move":float(face)})
 check(block.get("projectile_spawn:peach",0)==1 and block.get("block:peach",0)==1,"front guard blocks peach once")
 check(s.fighters[1-source].hp==100,"guard no HP damage")
 s=fixture(source,opponent,face)
 # Deliberately high emitter: isolate geometric miss without changing hurtbox or invulnerability.
 s.emitter_provider=func(_slot:int,_age:float):return Vector2(-0.8*face,4.0)
 var miss:Dictionary=tick(s,source,100,{"special":true})
 check(miss.get("hit:peach",0)==0 and s.fighters[1-source].hp==100,"high forward trajectory misses ground target without phantom damage")
 s=fixture(source,opponent,face);s.time_left=600
 var hold:Dictionary=tick(s,source,600,{"special":true})
 check(hold.get("projectile_spawn:peach",0)==1,"holding through cooldown never auto fires")
 var release:Dictionary=tick(s,source,1,{"special":false})
 var fresh:Dictionary=tick(s,source,80,{"special":true})
 check(fresh.get("projectile_spawn:peach",0)==1,"fresh press after cooldown works")
 for lethal in [false,true]:
  s=fixture(source,opponent,face);f=s.fighters[source]
  f.x=-.35*face;s.fighters[1-source].x=.35*face
  if lethal:f.hp=8
  var interrupted:Dictionary=tick(s,source,60,{"special":true},{"punch":true})
  check(interrupted.get("projectile_spawn:peach",0)==0,"pre-fire hit or KO cancels peach")
  check(f.special_cooldown>2.5,"interruption retains paid cooldown")
  check(f.attack!="special" and not f.special_pending_emit,"interruption clears state")
 s=fixture(source,opponent,face);f=s.fighters[source];f.y=.5;f.vy=1.0
 tick(s,source,1,{"special":true})
 check(f.attack!="special" and f.special_cooldown==0,"airborne peach rejected without cooldown")
 s=fixture(source,opponent,face);f=s.fighters[source]
 s.begin_special(f);f.face=-face
 s.step(.5,[{},{}])
 var spawns:=0
 for e:Dictionary in s.events:
  if e.type=="projectile_spawn" and e.kind=="peach":spawns+=1
 check(spawns==1,"large timestep emits once")
 if not s.projectiles.is_empty():check(s.projectiles[0].face==face,"committed firing direction frozen")
 s.reset(3 if source==0 else opponent,opponent if source==0 else 3)
 check(s.projectiles.is_empty() and s.fighters[source].special_cooldown==0,"round/menu reset clears peach and cooldown")
 var after_reset:Dictionary=tick(s,source,90)
 check(after_reset.get("projectile_spawn:peach",0)==0,"reset has no delayed cast emission")
func pair_melee_tests():
 for a in range(4):
  for b in range(4):
   if a==b:continue
   for face in [-1,1]:
    for move in ["punch","straight","heavy","roundhouse","kick"]:
     var s=Combat.new();s.reset(a,b)
     s.fighters[0].x=-.35*face;s.fighters[1].x=.35*face;s.fighters[0].face=face;s.fighters[1].face=-face
     if move=="straight":s.begin_attack(s.fighters[0],move)
     var before:float=s.fighters[1].hp
     tick(s,0,80,{move:true})
     check(s.fighters[1].hp<before,"twelve role pairs melee remains usable: "+str(a)+"/"+str(b)+" "+move)
     check(s.fighters[0].x>=Combat.LEFT and s.fighters[0].x<=Combat.RIGHT,"melee stays in arena")
     check(is_finite(s.effective_reach(s.fighters[0],move,.35)),"all role geometry exists")

func stress_pairs():
 var rounds:=0
 for a in range(4):
  for b in range(4):
   if a==b:continue
   for seed_id in range(4):
    var first:Dictionary=play_pair(a,b,seed_id)
    var second:Dictionary=play_pair(a,b,seed_id)
    check(first==second,"deterministic pair "+str(a)+"/"+str(b)+" seed "+str(seed_id))
    rounds+=1
 print("TAO PAIR STRESS rounds=",rounds," repeated=",rounds)
func play_pair(a:int,b:int,seed_id:int)->Dictionary:
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
    check(event.kind==["meow","heart","rifle","peach"][role],"projectile identity follows role not slot")
  check(sim.projectiles.size()<=2,"bounded projectiles with CD4")
  if sim.round_over:break
 check(sim.round_over,"full match terminates")
 return {"frames":elapsed,"winner":sim.winner,"fighters":sim.fighters.duplicate(true),"spawns":spawn_ids.duplicate()}
