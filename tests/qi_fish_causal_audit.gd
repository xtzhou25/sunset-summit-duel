extends "res://tests/symmetric_matchup_audit.gd"
func run():
 var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://exports/qa-matchup/symmetric-matchups.json"))
 for key in baseline.emitter_offsets:
  var a:Array=baseline.emitter_offsets[key];offsets[key]=Vector2(a[0],a[1])
 var result:Dictionary={"curves":{},"traces":[],"checks":0,"failures":0}
 var sim=Combat.new()
 for move in ["punch","straight","heavy","roundhouse","kick"]:
  var fish:Dictionary=sim.fresh(1,0,1);var qi:Dictionary=sim.fresh(2,0,1)
  var cfg:Dictionary=sim.attack_config(fish,move);var max_delta:=0.0;var min_delta:=INF;var max_signed:=-INF;var depth_diffs:=0;var config_diff:Dictionary={}
  var qcfg:Dictionary=sim.attack_config(qi,move)
  for key in cfg:
   if cfg[key]!=qcfg[key]:config_diff[key]=[cfg[key],qcfg[key]]
  for step in range(int(cfg.active*1000)+1):
   var t:float=cfg.startup+step*.001
   var fgeo:Dictionary=sim.contact_geometry(fish,move,t);var qgeo:Dictionary=sim.contact_geometry(qi,move,t)
   var d:float=qgeo.reach-fgeo.reach;max_delta=maxf(max_delta,absf(d));min_delta=minf(min_delta,d);max_signed=maxf(max_signed,d)
   if fgeo.depth_overlap!=qgeo.depth_overlap:depth_diffs+=1
  result.curves[move]={"max_abs_reach_difference_m":max_delta,"min_qi_minus_fish_m":min_delta,"max_qi_minus_fish_m":max_signed,"depth_gate_different_samples":depth_diffs,"config_differences":config_diff}
 for seed_id in [0,4,8,12,16,20]:
  for swap in range(2):
   var left:int=1 if swap==0 else 2;var right:int=2 if swap==0 else 1
   var trace:Dictionary=trace_round(left,right,seed_id)
   var previous:Array=baseline.rounds.filter(func(x):return x.left==left and x.right==right and x.seed==seed_id)
   check(previous.size()==1 and previous[0].winner_role==trace.winner_role and is_equal_approx(previous[0].simulation_seconds,trace.seconds),"instrumentation retains baseline outcome/time")
   result.traces.append(trace)
 result.checks=checks;result.failures=failures
 var file=FileAccess.open("res://exports/qa-matchup/qi-fish-causal-audit.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 print("CAUSAL READ ONLY checks=",checks," failures=",failures);quit(failures)
func trace_round(left:int,right:int,seed_id:int)->Dictionary:
 var s=Combat.new();s.reset(left,right)
 s.emitter_provider=func(index:int,_age:float)->Vector2:
  var f:Dictionary=s.fighters[index];var o:Vector2=offsets[str(f.kind)+":"+str(int(f.special_face))];return Vector2(f.x+o.x,o.y)
 var bots=[Brain.new(),Brain.new()]
 for i in range(2):bots[i].rng.seed=100003+seed_id*7919+(0 if s.fighters[i].kind==1 else 1)*104729;bots[i].reset()
 var attacks:Dictionary={};var elapsed:=0
 for frame in range(3650):
  var dist:float=absf(s.fighters[0].x-s.fighters[1].x)
  s.step(DT,[bots[0].act(view_for(s,0),DT),bots[1].act(view_for(s,1),DT)]);elapsed=frame+1
  for e in s.events:
   if e.type=="attack":
    attacks[str(e.attack_id)]={"slot":e.source,"resolution":"pending","role":s.fighters[e.source].kind,"move":e.kind,"accept_distance":dist,"swing_or_spawn":false,"outcome":"no_contact","post_resolution_root_separation":null,"accepted_time":s.elapsed}
   if e.type=="swing" or e.type=="projectile_spawn":
    if attacks.has(str(e.attack_id)):attacks[str(e.attack_id)].swing_or_spawn=true
   if e.type in ["hit","block","break"]:
    if attacks.has(str(e.attack_id)):
     attacks[str(e.attack_id)].outcome=e.type;attacks[str(e.attack_id)].contact_distance=absf(s.fighters[0].x-s.fighters[1].x)
  for key in attacks:
   var item:Dictionary=attacks[key]
   if item.resolution!="pending":continue
   var actor:Dictionary=s.fighters[item.slot]
   if actor.attack=="" or actor.attack_id!=int(key):
    item.resolution="interrupted" if actor.stun>0 or actor.down else "action_completed"
  if s.round_over:break
 return {"left":left,"right":right,"seed":seed_id,"winner_role":-1 if s.winner<0 else s.fighters[s.winner].kind,"seconds":elapsed*DT,"attacks":attacks}
