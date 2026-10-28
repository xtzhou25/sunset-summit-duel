"""Reproducible static-host packaging. Keep each payload below25MB."""
from pathlib import Path
import gzip,hashlib,json,math
root=Path(__file__).resolve().parents[1]
web=root/'exports/web';out=root/'dist';out.mkdir(exist_ok=True)
for p in web.iterdir():
 if p.name!='index.wasm' and not p.name.endswith('.import'): (out/p.name).write_bytes(p.read_bytes())
raw=(web/'index.wasm').read_bytes();compressed=gzip.compress(raw,compresslevel=9,mtime=0)
(out/'engine.wasm.gz.bin').write_bytes(compressed)
assert len(compressed)<25_000_000
js=(out/'index.js').read_text();needle='loadPromise = preloader.loadPromise(`${loadPath}.wasm`, size, true);'
replace='''loadPromise = fetch("engine.wasm.gz.bin").then(async response => {
 if (!response.ok) throw new Error("引擎下载失败，请刷新重试");
 if (typeof DecompressionStream === "undefined") throw new Error("浏览器版本过旧，请更新 Safari、Chrome 或 Edge 后重试");
 const bytes = await new Response(response.body.pipeThrough(new DecompressionStream("gzip"))).arrayBuffer();
 if (bytes.byteLength !== WASM_SIZE) throw new Error("引擎文件校验失败");
 const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))).map(x => x.toString(16).padStart(2,"0")).join("");
 if (hash !== "WASM_SHA") throw new Error("引擎完整性校验失败");
 return new Response(bytes, {headers:{"Content-Type":"application/wasm"}});
});'''.replace('WASM_SIZE',str(len(raw))).replace('WASM_SHA',hashlib.sha256(raw).hexdigest())
assert needle in js
from patch_rotated_input import patch_javascript
(out/'index.js').write_text(patch_javascript(js.replace(needle,replace)))
html=(out/'index.html').read_text().replace('<html lang="en">','<html lang="zh-CN">').replace('initial-scale=1.0','initial-scale=1.0, viewport-fit=cover')
html=html.replace('const GODOT_CONFIG =','const GODOT_CONFIG =').replace('"ensureCrossOriginIsolationHeaders":true','"ensureCrossOriginIsolationHeaders":false')
html=html.replace('show-image--true','show-image--false')
download_mb=math.ceil((len(compressed)+sum(p.stat().st_size for p in web.iterdir() if p.is_file() and p.name!='index.wasm' and not p.name.endswith('.import')))/1_000_000)
html=html.replace('<progress id="status-progress">','<div style="text-align:center;font-family:sans-serif;margin:24px"><h1 style="font-size:26px">决战日不落之巅</h1><p id="loadhint">正在准备舞台…首次加载约DOWNLOAD_MB MB</p><p style="font-size:13px;color:#cbbbdc">横屏体验更舒展，竖屏也可游玩</p><a href="CREDITS.txt" style="color:#cbbbdc">素材与许可</a></div><progress id="status-progress">')
html=html.replace('DOWNLOAD_MB',str(download_mb))
html=html.replace('Your browser does not support the canvas tag.','当前浏览器不支持画布。').replace('Your browser does not support JavaScript.','请启用 JavaScript 后打开游戏。')
html=html.replace('Error\\nThe following features required to run Godot projects on the Web are missing:\\n','当前浏览器缺少运行游戏所需功能。请尝试支持 WebGL 2 的新版 Safari、Chrome 或 Edge。\\n缺少：\\n')
html=html.replace("statusMode = mode;","document.getElementById('loadhint').style.display = mode === 'notice' ? 'none' : ''; statusMode = mode;")
credits=(root/'docs/ANIMATION-ATTRIBUTION.txt').read_text()+"\n"+(root/'docs/FONT-LICENSE.txt').read_text()+"\nGodot Engine 4.6.3, MIT license: https://godotengine.org/license/\nGame scene, UI and sound effects were created for this project. Character geometry remains owned by its original rights holder; no blanket redistribution license is granted.\n"
credits+='\n'+(root/'docs/MEOW-AUDIO-LICENSE.txt').read_text()+'\n'
credits+='\n'+(root/'docs/GODOT-LICENSE.txt').read_text()+'\nEngine third-party notices: ENGINE-THIRD-PARTY.json\n'
(out/'CREDITS.txt').write_text(credits)
(out/'ENGINE-THIRD-PARTY.json').write_bytes((root/'docs/ENGINE-THIRD-PARTY.json').read_bytes())
for stale in out.glob('*.import'): stale.unlink()
# Unsupported WebGL is reported honestly, never hidden as success.
from apply_fullscreen_patch import patch_html
html = patch_html(html)
auth_css = (root/'web-ui/duel_auth.css').read_text()
auth_js = (root/'web-ui/duel_auth.js').read_text()
html = html.replace('</head>', '<style id="duel-auth-style">\n' + auth_css + '</style>\n</head>', 1)
html = html.replace('</body>', '<script id="duel-auth-script">\n' + auth_js + '</script>\n</body>', 1)
(out/'index.html').write_text(html)
(out/'BUILD.json').write_text(json.dumps({'engine':'Godot4.6.3','threads':False,'wasm_bytes':len(raw),'compressed_bytes':len(compressed),'wasm_sha256':hashlib.sha256(raw).hexdigest()},indent=2))
print('pack',len(raw),'->',len(compressed),'bytes; maximum file',max(p.stat().st_size for p in out.iterdir()))
