"""Package a fresh Godot4.6.3 PCK with byte-verified unchanged RC17 Web engine/input bridge.
Usage: python3 scripts/pack_stage_web.py /absolute/path/to/verified/RC17/dist
No export template or new engine download is needed for this source-only update.
"""
from pathlib import Path
import hashlib,json,re,shutil,sys
root=Path(__file__).resolve().parents[1]
baseline=Path(sys.argv[1]).resolve(); out=root/'dist';out.mkdir(exist_ok=True)
expected_engine='26b61ce95247012ab3dca3ff51e96d1cdbff44ee91a8c20a83e150afca83f1b6'
metadata=json.loads((baseline/'BUILD.json').read_text());assert metadata['wasm_sha256']==expected_engine
import gzip
assert hashlib.sha256(gzip.decompress((baseline/'engine.wasm.gz.bin').read_bytes())).hexdigest()==expected_engine
for source in baseline.iterdir():
 if source.is_file() and not source.name.endswith('.import'):shutil.copy2(source,out/source.name)
pck=root/'exports/web/index.pck';assert pck.stat().st_size<25_000_000
shutil.copy2(pck,out/'index.pck')
html=(out/'index.html').read_text();html,count=re.subn(r'("index.pck"\s*:\s*)\d+',lambda m:m[1]+str(pck.stat().st_size),html);assert count==1
(out/'index.html').write_text(html)
proof={'baseline':'verified RC17 / Sites18 / functionalv16','engine_sha256':expected_engine,'pck_bytes':pck.stat().st_size,'pck_sha256':hashlib.sha256(pck.read_bytes()).hexdigest(),'unchanged_engine_and_bridge':{},'scope':'Fresh source PCK; unchanged Godot4.6.3 Web engine, rotated-input bridge, page shell except declared PCK size.'}
for name in ['engine.wasm.gz.bin','index.js','index.audio.worklet.js','index.audio.position.worklet.js']:
 proof['unchanged_engine_and_bridge'][name]=hashlib.sha256((out/name).read_bytes()).hexdigest();assert (out/name).read_bytes()==(baseline/name).read_bytes()
(root/'exports/web-package-proof.json').write_text(json.dumps(proof,indent=2));print(json.dumps(proof,indent=2))
