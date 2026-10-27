"""Summarize recorded real-control gameplay telemetry; never creates gameplay states."""
import argparse, collections, hashlib, json
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('telemetry',type=Path)
args=parser.parse_args()
raw=args.telemetry.read_bytes(); rows=json.loads(raw)
summary={'telemetry_sha256':hashlib.sha256(raw).hexdigest(),'samples':len(rows),'first_frame':rows[0]['frame'],'last_frame':rows[-1]['frame'],'facings':sorted(set((r['player']['face'],r['ai']['face']) for r in rows)),'final_wins':rows[-1]['wins'],'actors':{}}
for actor in ['player','ai']:
 summary['actors'][actor]={'states':dict(collections.Counter(r[actor]['state'] for r in rows)),'down_phases':dict(collections.Counter(r[actor].get('down_phase','') for r in rows if r[actor].get('down',False))),'ko_samples':sum(bool(r[actor].get('down_ko',False)) for r in rows),'final_hp':rows[-1][actor]['hp'],'x_range':[min(r[actor]['x'] for r in rows),max(r[actor]['x'] for r in rows)],'maximum_jump_height':max(r[actor]['y'] for r in rows)}
print(json.dumps(summary,indent=2))
