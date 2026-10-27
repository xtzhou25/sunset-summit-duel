from pathlib import Path
import hashlib,json,re
r=Path(__file__).resolve().parents[1];src=r.parent/'ha-character/animation/ha_surface_curves.json'
clips=json.loads(src.read_text())['clips'];punch={}
for move,(clip,limb,start,end) in {'punch':('Jab','hand.L',.14,.24),'straight':('Straight','hand.R',.18,.28),'heavy':('HeavyPunch','hand.R',.34,.46)}.items():
 punch[move]=[]
 for i in range(round((end-start)*100)+1):
  t=round(start+i*.01,2)
  values=[next(row for row in clips[clip+'_'+side] if abs(row['time']-t)<1e-7)[limb]['forward_z'][1] for side in ('R','L')]
  punch[move].append(min(values))
foot=[]
for i in range(15):
 t=round(.28+i*.01,2);both=[]
 for side in ('R','L'):
  row=next(row for row in clips['RoundhouseKick_'+side] if abs(row['time']-t)<1e-7)['foot.R'];both.append(row['depth_x']+row['height_y']+row['forward_z'])
 assert max(abs(a-b) for a,b in zip(*both))<1e-5,'Foot facings differ'
 foot.append(both[0])
p=r/'scripts/characters.gd';s=p.read_text()
s=s.replace('# Provisional common-limb curves; replace with measured final Ha contract before release.','# Measured final Ha skin at game scale1.2, active windows unchanged.\nconst HA_SURFACE_SOURCE_SHA256 := "'+hashlib.sha256(src.read_bytes()).hexdigest()+'"')
for key,value in {'HA_PUNCH_REACH_CURVES':punch,'HA_ROUNDHOUSE_SURFACE_CURVES':foot}.items():
 s,n=re.subn(r'^const '+key+r' (?::)?= .*$',lambda m:'const '+key+' := '+json.dumps(value,separators=(',',':')),s,flags=re.M);assert n==1,key
p.write_text(s)
(r/'qa-ha-rules/HA-MEASURED-CURVES.json').write_text(json.dumps({'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'runtime_sha256':hashlib.sha256((src.parent/'Ha-v02-Runtime.glb').read_bytes()).hexdigest(),'punch':punch,'roundhouse':foot},indent=2))
print('HA measured constants embedded. Source',hashlib.sha256(src.read_bytes()).hexdigest())
