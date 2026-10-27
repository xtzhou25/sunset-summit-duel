extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const Brain=preload("res://scripts/ai.gd")
const Roles=preload("res://scripts/characters.gd")
const DT=1.0/60.0
class PublicView extends RefCounted:
 var fighters:Array=[]
 var projectiles:Array=[]
var checks:=0
var failures:=0
var offsets:Dictionary={}
var game
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func _initialize():call_deferred("run")
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false)
 for role in range(3):
  game.start_match(role);game.set_physics_process(false)
  for face in [-1,1]:
   var f:Dictionary=game.sim.fighters[0];f.x=0;f.y=0;f.face=face;f.special_face=face
   var age:float=Roles.get_character(role).special_emit
   var point:Vector2=game.signature_emitter(0,age)
   offsets[str(role)+":"+str(face)]=point
 var results:Array=[]
 for a in range(3):
  for b in range(a+1,3):
   for seed_id in range(24):
    for swap in range(2):
     var left:int=a if swap==0 else b;var right:int=b if swap==0 else a
     var one:Dictionary=play(left,right,a,b,seed_id)
     var repeat:Dictionary=play(left,right,a,b,seed_id)
     check(one==repeat,"exact seed repeat")
     results.append(one)
   print("DONE PAIR ",a," ",b)
 var data={"method":"same unchanged AI for both slots; each unordered pair 24 paired seeds switching sides; RNG streams attached to character, not slot; each round replayed exactly; fixed60Hz simulation seconds excluding common hitstop, actual imported marker offsets","seed_count_per_pair":24,"rounds":results,"emitter_offsets":{},"checks":checks,"failures":failures,"ai_sha256":FileAccess.get_sha256("res://scripts/ai.gd"),"combat_sha256":FileAccess.get_sha256("res://scripts/combat.gd"),"characters_sha256":FileAccess.get_sha256("res://scripts/characters.gd")}
 for key in offsets:data.emitter_offsets[key]=[offsets[key].x,offsets[key].y]
 var file=FileAccess.open("res://exports/qa-matchup/symmetric-matchups.json",FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
 print("SYMMETRIC MATCHUPS rounds=",results.size()," exact_repeats=",results.size()," checks=",checks," failures=",failures)
 game.queue_free();await process_frame;quit(failures)
func view_for(s,slot:int)->PublicView:
 var v=PublicView.new();v.fighters=[s.fighters[1-slot],s.fighters[slot]]
 for p in s.projectiles:
  var q:Dictionary=p.duplicate();q.owner=1 if int(p.owner)==slot else 0;v.projectiles.append(q)
 return v
func play(left:int,right:int,a:int,b:int,seed_id:int, reverse_streams:bool=false, disable_specials:bool=false)->Dictionary:
 var s=Combat.new();s.reset(left,right)
 s.emitter_provider=func(index:int,_age:float)->Vector2:
  var f:Dictionary=s.fighters[index];var o:Vector2=offsets[str(f.kind)+":"+str(int(f.special_face))]
  return Vector2(f.x+o.x,o.y)
 var bots=[Brain.new(),Brain.new()]
 for i in range(2):
  var stream:int=0 if s.fighters[i].kind==a else 1
  if reverse_streams:stream=1-stream
  bots[i].rng.seed=100003+seed_id*7919+stream*104729;bots[i].reset()
 var damage=[0.0,0.0];var blocks=[0,0];var breaks=[0,0];var guard_min=[100.0,100.0];var guard_sum=[0.0,0.0];var last_cast=[-100.0,-100.0];var shortest_cd=[100.0,100.0];var casts=[0,0];var spawns=[0,0];var hits=[0,0];var ranged_hits=[0,0];var move_counts=[{},{}];var projectile_attacks={};var elapsed:=0
 for frame in range(3650):
  var commands=[bots[0].act(view_for(s,0),DT),bots[1].act(view_for(s,1),DT)]
  if disable_specials:
   commands[0].erase("special");commands[1].erase("special")
  s.step(DT,commands);elapsed=frame+1
  for i in range(2):
   var f:Dictionary=s.fighters[i];guard_min[i]=minf(guard_min[i],f.guard);guard_sum[i]+=f.guard
   check(f.hp>=0 and f.hp<=100 and f.guard>=0 and f.guard<=100 and is_finite(f.x),"finite health guard")
   check(f.special_cooldown>=0 and f.special_cooldown<=4.00001,"cooldown bounds")
  for e in s.events:
   if e.type=="attack":
    var i:int=e.source;move_counts[i][e.kind]=move_counts[i].get(e.kind,0)+1
    if e.kind=="special":
     if casts[i]>0:shortest_cd[i]=minf(shortest_cd[i],s.elapsed-last_cast[i]);check(s.elapsed-last_cast[i]>=4.0-.00001,"no CD bypass")
     casts[i]+=1;last_cast[i]=s.elapsed
   if e.type=="projectile_spawn":
    check(not projectile_attacks.has(e.attack_id),"one projectile per cast");projectile_attacks[e.attack_id]=true;spawns[e.source]+=1
   if e.type=="block":blocks[e.fighter]+=1
   if e.type=="break":breaks[e.fighter]+=1
   if e.type=="hit" or e.type=="break":
    damage[e.source]+=e.damage;hits[e.source]+=1
    if e.kind in ["meow","heart","rifle"]:ranged_hits[e.source]+=1
  if s.round_over:break
 check(s.round_over,"round complete")
 return {"reverse_streams":reverse_streams,"specials_disabled":disable_specials,"left":left,"right":right,"pair":[a,b],"seed":seed_id,"winner_slot":s.winner,"winner_role":-1 if s.winner<0 else s.fighters[s.winner].kind,"simulation_seconds":elapsed*DT,"hp_end":[s.fighters[0].hp,s.fighters[1].hp],"event_damage_dealt":damage,"hits":hits,"ranged_hits":ranged_hits,"blocks_received":blocks,"guard_breaks_received":breaks,"guard_min":guard_min,"guard_mean":[guard_sum[0]/elapsed,guard_sum[1]/elapsed],"casts":casts,"spawns":spawns,"minimum_recast_seconds":shortest_cd,"move_counts":move_counts}
