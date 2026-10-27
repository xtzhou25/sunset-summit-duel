extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const Characters=preload("res://scripts/characters.gd")
const Brain=preload("res://scripts/ai.gd")
const DT:=1.0/60.0
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _init():
 if Characters.COUNT!=5:printerr("BLOCKED final five-role registry not ready");quit(2);return
 registry()
 warning_air_cases()
 for slot in range(2):
  for foe in range(4):
   for face in [-1,1]:cake_cases(slot,foe,face)
 for dt in [1.0/120.0,1.0/60.0,1.0/30.0,.1]:timesteps(dt)
 melee_pairs()
 stress_pairs()
 print("HA RULES checks=",checks," failures=",failures)
 quit(failures)
func fixture(slot:int=0,foe:int=0,face:int=1):
 var s=Combat.new();s.reset(4 if slot==0 else foe,foe if slot==0 else 4)
 s.fighters[slot].x=-1.2*face;s.fighters[1-slot].x=1.2*face
 s.fighters[slot].face=face;s.fighters[1-slot].face=-face
 return s
func tick(s,slot:int,frames:int,c:Dictionary={},o:Dictionary={},pin_foe:bool=false,dt:float=DT)->Dictionary:
 var events:Dictionary={};var old_x:float=s.fighters[1-slot].x
 for n in range(frames):
  if pin_foe:s.fighters[1-slot].x=old_x
  var commands:Array=[{},{}];commands[slot]=c;commands[1-slot]=o;s.step(dt,commands)
  for e:Dictionary in s.events:
   var k:String=e.type+":"+str(e.get("kind",""));events[k]=events.get(k,0)+1
 return events
func registry():
 check(Characters.get_character(4).name=="哈","Ha name")
 check(Characters.get_character(4).special_kind=="cake","cake identity")
 for a in range(5):
  for b in range(5):
   var s=Combat.new();s.reset(a,b)
   check(s.fighters.size()==2 and s.fighters[0].kind==a,"five roles two slots")
   check(s.fighters[1].kind==(b if a!=b else Characters.default_opponent(a)),"explicit pair/fallback")
func cake_cases(slot:int,foe:int,face:int):
 var label:=str(slot)+"/"+str(foe)+"/"+str(face)
 var s=fixture(slot,foe,face);var f:Dictionary=s.fighters[slot]
 tick(s,slot,1,{"special":true})
 check(f.attack=="special" and f.special_cooldown>3.9,"accepted paid cooldown "+label)
 check(f.y==0.0 and f.vy==0.0,"grounded summon "+label)
 var emit:float=f.special_emit_age
 tick(s,slot,int(floor(emit/DT))-2)
 check(s.projectiles.is_empty(),"no early damaging cake "+label)
 var rest:Dictionary=tick(s,slot,120)
 check(rest.get("projectile_spawn:cake",0)==1,"single cake spawn "+label)
 check(rest.get("hit:cake",0)==1 and s.fighters[1-slot].hp==88,"exact single12 hit "+label)
 check(s.projectiles.is_empty(),"cake cleaned on hit "+label)
 check(f.attack=="" and f.y==0.0,"summon returns grounded "+label)
 s=fixture(slot,foe,face)
 var blocked:Dictionary=tick(s,slot,120,{"special":true},{"move":float(face)},true)
 check(blocked.get("block:cake",0)==1 and s.fighters[1-slot].hp==100,"backward grounded guard protects "+label)
 s=fixture(slot,foe,face)
 tick(s,slot,1,{"special":true})
 var locked_x:float=s.fighters[1-slot].x
 s.fighters[1-slot].x=0.0
 # Verify visible spawn remains at originally telegraphed target after move during windup.
 var found:=false
 for n in range(70):
  s.step(DT,[{},{}])
  for e:Dictionary in s.events:
   if e.type=="projectile_spawn" and e.kind=="cake":
    found=true;check(absf(e.pos.x-locked_x)<1e-6,"target locked before emission "+label)
  for p:Dictionary in s.projectiles:
   check(absf(p.velocity.x)<1e-9 and p.velocity.y<0,"vertical descent only "+label)
   check(absf(p.pos.x-locked_x)<1e-6,"no homing "+label)
 check(found and s.fighters[1-slot].hp==100,"moving off landing mark avoids cake "+label)
 check(s.projectiles.is_empty(),"miss cleans at ground "+label)
 s=fixture(slot,foe,face);s.time_left=600
 var held:Dictionary=tick(s,slot,360,{"special":true})
 check(held.get("projectile_spawn:cake",0)==1,"held key never autofires "+label)
 tick(s,slot,1)
 var again:Dictionary=tick(s,slot,120,{"special":true})
 check(again.get("projectile_spawn:cake",0)==1,"fresh press after cooldown "+label)
 for lethal in [false,true]:
  s=fixture(slot,foe,face);f=s.fighters[slot]
  f.x=-.35*face;s.fighters[1-slot].x=.35*face
  if lethal:f.hp=8
  var interrupted:Dictionary=tick(s,slot,90,{"special":true},{"punch":true})
  check(interrupted.get("projectile_spawn:cake",0)==0,"startup hit/KO no cake "+label)
  check(f.special_cooldown>2.4,"interrupted cooldown paid "+label)
  check(not f.special_pending_emit,"no delayed emission after cancel "+label)
 s=fixture(slot,foe,face);f=s.fighters[slot];f.y=.4;f.vy=1.0
 tick(s,slot,1,{"special":true})
 check(f.attack!="special" and f.special_cooldown==0,"air summon refused without charge "+label)
 # Real opposing punch begins after emission, contacts before cake impact.
 s=fixture(slot,foe,face);s.fighters[slot].x=-.35*face;s.fighters[1-slot].x=.35*face
 s.begin_special(s.fighters[slot]);tick(s,slot,29)
 var post_launch:Dictionary=tick(s,slot,75,{}, {"punch":true})
 check(s.fighters[slot].hp<100 and post_launch.get("hit:cake",0)==1,"real postlaunch hit preserves cake "+label)
 # Once launched, nonlethal hit does not delete the existing cake.
 s=fixture(slot,foe,face);f=s.fighters[slot];s.begin_special(f)
 while s.projectiles.is_empty():s.step(DT,[{},{}])
 var id:int=s.projectiles[0].id
 f.stun=.2;f.attack="";s._clear_special(f)
 check(s.projectiles.size()==1 and s.projectiles[0].id==id,"launched cake persists after nonlethal interrupt "+label)
 tick(s,slot,90)
 check(s.fighters[1-slot].hp==88,"launched cake resolves normally "+label)
 s=fixture(slot,foe,face);s.begin_special(s.fighters[slot])
 while s.projectiles.is_empty():s.step(DT,[{},{}])
 s.reset(4 if slot==0 else foe,foe if slot==0 else 4)
 check(s.projectiles.is_empty(),"reset clears falling cake "+label)
 var no_delayed:Dictionary=tick(s,slot,120)
 check(no_delayed.get("projectile_spawn:cake",0)==0,"no old cake after reset "+label)
 s=fixture(slot,foe,face);s.begin_special(s.fighters[slot])
 while s.projectiles.is_empty():s.step(DT,[{},{}])
 s.round_over=true;s.step(DT,[{},{}])
 check(s.projectiles.is_empty(),"KO/result clears all cake "+label)
 for edge in [Combat.LEFT,Combat.RIGHT]:
  s=fixture(slot,foe,face);s.fighters[1-slot].x=edge
  var edge_result:Dictionary=tick(s,slot,120,{"special":true})
  check(edge_result.get("projectile_spawn:cake",0)==1 and edge_result.get("hit:cake",0)==1,"arenaedge cake valid "+label)
func timesteps(dt:float):
 var s=fixture();s.begin_special(s.fighters[0]);var events:Dictionary=tick(s,0,int(ceil(2.0/dt)),{},{},false,dt)
 check(events.get("projectile_spawn:cake",0)==1 and events.get("hit:cake",0)==1 and s.fighters[1].hp==88,"swept downward collision dt="+str(dt))
func melee_pairs():
 for a in range(5):
  for b in range(5):
   if a==b:continue
   for move in ["punch","straight","heavy","roundhouse","kick"]:
    var s=Combat.new();s.reset(a,b);s.fighters[0].x=-.35;s.fighters[1].x=.35
    if move=="straight":s.begin_attack(s.fighters[0],move)
    tick(s,0,90,{move:true})
    check(s.fighters[1].hp<100,"20pair melee "+str(a)+"/"+str(b)+" "+move)
func stress_pairs():
 for a in range(5):
  for b in range(5):
   if a==b:continue
   for seed_id in range(2):
    var one:Dictionary=play(a,b,seed_id);var two:Dictionary=play(a,b,seed_id)
    check(one==two,"20pair deterministic "+str(a)+"/"+str(b)+" seed="+str(seed_id))
func play(a:int,b:int,seed_id:int)->Dictionary:
 var s=Combat.new();s.reset(a,b);var brain=Brain.new();brain.rng.seed=2026+seed_id;brain.reset()
 var emitted:Dictionary={};var damage:Dictionary={};var frames:=0
 for frame in range(3650):
  var f:Dictionary=s.fighters[0];var o:Dictionary=s.fighters[1]
  var face:float=1 if o.x>f.x else -1
  var cmd:Dictionary={"move":face if absf(o.x-f.x)>.8 else 0.0,"punch":frame%19==0,"heavy":frame%83==0,"roundhouse":frame%113==0,"kick":frame%97==0,"special":frame%251==0,"jump":frame%137==0}
  if frame%500>=400:cmd.move=-face
  s.step(DT,[cmd,brain.act(s,DT)]);frames=frame+1
  for actor:Dictionary in s.fighters:
   check(actor.x>=Combat.LEFT and actor.x<=Combat.RIGHT and actor.y>=0 and actor.hp>=0 and actor.hp<=100,"finite state")
  for e:Dictionary in s.events:
   if e.type=="projectile_spawn":
    check(not emitted.has(e.attack_id),"one projectile each cast across20pairs");emitted[e.attack_id]=true
    check(e.kind==["meow","heart","rifle","peach","cake"][s.fighters[e.source].kind],"role identity")
   if e.type in ["hit","block"] and e.get("kind","")=="cake":
    var key:int=e.get("attack_id",-1)
    if key>=0:check(not damage.has(key),"one cake damage/contact");damage[key]=true
  check(s.projectiles.size()<=2,"bounded pool")
  if s.round_over:break
 check(s.round_over,"match terminates")
 return {"frames":frames,"winner":s.winner,"fighters":s.fighters.duplicate(true),"emitted":emitted}

func warning_air_cases():
 for face in [-1,1]:
  var s=fixture(0,0,face)
  check(s.cake_warnings().is_empty(),"no stale warning initially")
  s.begin_special(s.fighters[0])
  var warnings:Array=s.cake_warnings()
  check(warnings.size()==1 and warnings[0].owner==0 and absf(warnings[0].x-1.2*face)<1e-6,"warning visible at cast start")
  var warning_x:float=warnings[0].x
  s.fighters[1].x=0.0
  tick(s,0,10)
  check(s.cake_warnings().size()==1 and s.cake_warnings()[0].x==warning_x,"warning never tracks target")
  s.fighters[0].attack="";s.fighters[0].stun=.2;s._clear_special(s.fighters[0])
  check(s.cake_warnings().is_empty(),"startup interruption removes warning")
  tick(s,0,90)
  check(s.projectiles.is_empty(),"interrupted warning has no deferred projectile")
  s=fixture(0,0,face);s.begin_special(s.fighters[0])
  for n in range(35):s.step(DT,[{},{}])
  check(s.projectiles.size()==1 and s.cake_warnings().size()==1,"falling phase has one warning")
  check(s.cake_warnings()[0].x==s.projectiles[0].pos.x,"warning aligns cake")
  tick(s,0,120)
  check(s.cake_warnings().is_empty(),"resolved cake clears warning")
  # Airborne defender cannot block even with backward input; pin horizontal position only.
  s=fixture(0,0,face);s.begin_special(s.fighters[0]);tick(s,0,25)
  var air:Dictionary=tick(s,0,65,{}, {"jump":true,"move":float(face)},true)
  check(air.get("block:cake",0)==0,"air backward is not guard")
  check(air.get("hit:cake",0)==1,"cake can hit airborne target under drop")
  # Cross-side guard is deliberately simplified to backward block, per contract.
  s=fixture(0,0,face);s.begin_special(s.fighters[0]);tick(s,0,28)
  s.fighters[0].x=1.7*face;s.fighters[1].face=face
  var cross:Dictionary=tick(s,0,80,{}, {"move":float(-face)},true)
  check(cross.get("block:cake",0)==1,"overhead backward guard remains after caster crosses")
