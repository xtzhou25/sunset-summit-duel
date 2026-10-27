"""Refresh the PCK while retaining the exact verified Godot4.6.3 RC6 web engine.

Use `godot --headless --export-pack Web exports/web/index.pck` first. This avoids
downloading/replacing an unchanged engine. The complete dist/ engine is included
in each release archive, so restoration does not depend on a temporary server.
"""
from pathlib import Path
import hashlib,json,re,shutil
from apply_fullscreen_patch import patch_html
from patch_rotated_input import patch_javascript
root=Path(__file__).resolve().parents[1]
out=root/'dist'
# Godot editor may generate local import sidecars; these are not hosted assets.
for sidecar in out.glob('*.import'):
    sidecar.unlink()
wasm=out/'engine.wasm.gz.bin'
assert wasm.is_file()
assert hashlib.sha256(wasm.read_bytes()).hexdigest()=='9352825a316f4449b81d326706e78be95ed5a81c0e797f35879ef8b39bc505bd', 'Unexpected engine bytes'
build=json.loads((out/'BUILD.json').read_text())
assert build['engine']=='Godot4.6.3' and build['threads'] is False
pack=root/'exports/web/index.pck'
assert pack.is_file() and pack.stat().st_size>100000
shutil.copyfile(pack,out/'index.pck')
html=(out/'index.html').read_text()
html,count=re.subn(r'("index.pck"\s*:\s*)\d+',lambda m:m.group(1)+str(pack.stat().st_size),html)
assert count==1,'Expected exactly one PCK size in Godot config'
(out/'index.html').write_text(patch_html(html))
(out/'index.js').write_text(patch_javascript((out/'index.js').read_text()))
credits=(out/'CREDITS.txt').read_text()
audio=(root/'docs/MEOW-AUDIO-LICENSE.txt').read_text()
if audio not in credits:
    (out/'CREDITS.txt').write_text(credits+'\n\n'+audio)
print(json.dumps({'engine_reused':'verified RC6 Godot4.6.3','pck_bytes':pack.stat().st_size,'pck_sha256':hashlib.sha256(pack.read_bytes()).hexdigest(),'files':len(list(out.iterdir()))},indent=2))
