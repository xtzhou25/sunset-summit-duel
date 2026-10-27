import json,statistics,random,collections,pathlib
p=pathlib.Path(__file__).resolve().parent.parent
m=json.loads((p/'exports/qa-matchup/symmetric-matchups.json').read_text());rows=m['rounds'];out={'pairs':[],'ordered':[],'method':m['method'],'checks':m['checks'],'failures':m['failures'],'left_wins':sum(r['winner_slot']==0 for r in rows),'right_wins':sum(r['winner_slot']==1 for r in rows)}
for a,b in [(0,1),(0,2),(1,2)]:
 rr=[r for r in rows if r['pair']==[a,b]];samples=[];disagreements=0
 for seed in range(24):
  ss=[r for r in rr if r['seed']==seed];samples.append(statistics.mean(1 if r['winner_role']==a else .5 if r['winner_role']<0 else 0 for r in ss));disagreements+=ss[0]['winner_role']!=ss[1]['winner_role']
 rng=random.Random(55);boot=sorted(statistics.mean(rng.choices(samples,k=24)) for _ in range(10000))
 o={'pair':[a,b],'wins':{str(k):sum(r['winner_role']==k for r in rr) for k in [-1,a,b]},'paired_bootstrap95_role_a_win_share':[boot[249],boot[9749]],'side_swapped_seed_winner_disagreements':disagreements,'mean_round_seconds':statistics.mean(r['simulation_seconds'] for r in rr),'roles':{}}
 for role in [a,b]:
  get=lambda r,key:r[key][0 if r['left']==role else 1]
  counts=collections.Counter()
  for r in rr:counts.update(get(r,'move_counts'))
  casts=sum(get(r,'casts') for r in rr);spawns=sum(get(r,'spawns') for r in rr);hits=sum(get(r,'ranged_hits') for r in rr)
  o['roles'][str(role)]={'mean_event_damage':statistics.mean(get(r,'event_damage_dealt') for r in rr),'mean_hp_end':statistics.mean(get(r,'hp_end') for r in rr),'blocks_received':sum(get(r,'blocks_received') for r in rr),'guard_breaks_received':sum(get(r,'guard_breaks_received') for r in rr),'guard_mean':statistics.mean(get(r,'guard_mean') for r in rr),'guard_min':min(get(r,'guard_min') for r in rr),'casts':casts,'spawns':spawns,'ranged_hits':hits,'hit_per_spawn':hits/spawns if spawns else None,'min_recast_seconds':min(get(r,'minimum_recast_seconds') for r in rr),'move_counts':dict(counts)}
 out['pairs'].append(o)
for left in range(3):
 for right in range(3):
  if left==right:continue
  rr=[r for r in rows if r['left']==left and r['right']==right]
  out['ordered'].append({'left':left,'right':right,'left_wins':sum(r['winner_slot']==0 for r in rr),'right_wins':sum(r['winner_slot']==1 for r in rr),'draws':sum(r['winner_slot']==-1 for r in rr),'mean_round_seconds':statistics.mean(r['simulation_seconds'] for r in rr)})
(p/'exports/qa-matchup/symmetric-summary.json').write_text(json.dumps(out,indent=2));print(json.dumps(out,indent=2))
