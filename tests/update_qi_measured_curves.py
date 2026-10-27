"""Regenerate ONLY Qi's embedded contact subset after verified GLB sampling.
Input: assets/qi_surface_curves.json from actual exported skin at scale1.2.
Legacy 0/1 constants and all gameplay timings remain unchanged.
"""
from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parents[1];source=root/'assets/qi_surface_curves.json'
clips=json.loads(source.read_text())['clips'];punch={}
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
 assert max(abs(a-b) for a,b in zip(*both))<1e-5,'Foot facings differ; do not silently merge distinct surfaces'
 foot.append(both[0])
registry=root/'scripts/characters.gd';text=registry.read_text()
for key,value in {'QI_SURFACE_SOURCE_SHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'QI_PUNCH_REACH_CURVES':punch,'QI_ROUNDHOUSE_SURFACE_CURVES':foot}.items():
 text,count=re.subn(r'^const '+key+r' := .*$',lambda m:'const '+key+' := '+json.dumps(value,separators=(',',':')),text,flags=re.M)
 assert count==1,key
registry.write_text(text)
print(json.dumps({'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'samples':{k:len(v) for k,v in punch.items()},'foot_samples':len(foot)}))
