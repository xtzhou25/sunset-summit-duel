"""Extract exact patched Godot callbacks into a browser-only mock-sink harness.
No WASM/game logic is executed. Run after changing dist/index.js.
"""
from pathlib import Path
import hashlib
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import patch_rotated_input as patch
root = Path(__file__).resolve().parents[1]
source = (root / 'dist/index.js').read_text()
assert patch.patch_javascript(source) == source, 'Dist must already contain verified input patch'
parts = []
for _, exact in patch.PATCHES:
    assert source.count(exact) == 1
    start = source.index(exact)
    parts.append(source[start:start + len(exact)])
modifiers = 'getModifiers:function(evt){return evt.shiftKey+0+(evt.altKey+0<<1)+(evt.ctrlKey+0<<2)+(evt.metaKey+0<<3)}'
assert modifiers in source[source.index('var GodotInput='):source.index('var GodotInput=')+6000]
sha = hashlib.sha256(source.encode()).hexdigest()
prefix = '''/* Generated exact Godot input callback probe. MOCK sink, NOT WASM gameplay. */
(function(){'use strict';
window.installLivehouseExactRuntimeProbe=function(options){
 const canvas=options.canvas,heap=new Map(),events=[],heldMouse=new Set(),heldTouch=new Map(),heldKeys=new Set(),counts={};
 let currentEvent=null,keyData=null;
 const GodotConfig={canvas};
 const GodotRuntime={get_func:f=>f,setHeapValue:(address,value)=>heap.set(address,value)};
 const GodotEventListeners={add:(target,name,fn,capture)=>target.addEventListener(name,function(e){currentEvent=e;try{fn(e);}finally{currentEvent=null;}},capture)};
 function record(data){const event={kind:data.kind,sourceEvent:currentEvent?.type||'direct cancellation',trusted:currentEvent?.isTrusted||false,...data};events.push(event);if(events.length>160)events.shift();if(options.oninput)options.oninput(event);options.onchange();}
'''
body = 'const GodotInput={' + modifiers + ',' + parts[0] + ',' + parts[4] + '};\n' + '\n'.join(parts[1:4])
suffix = '''
 _godot_js_input_mouse_button_cb(function(pressed,button,x,y,modifiers){
  const hit=options.hit([x,y]);if(pressed){heldMouse.add(button);if(currentEvent?.isTrusted&&hit)counts[hit]=(counts[hit]||0)+1;}else heldMouse.delete(button);
  record({kind:'mouse',pressed,button,x,y,modifiers,hit});return true;
 });
 _godot_js_input_mouse_move_cb(function(x,y,dx,dy,modifiers,pressure){if(currentEvent?.buttons)record({kind:'move',x,y,dx,dy,modifiers,pressure,hit:options.hit([x,y])});});
 _godot_js_input_touch_cb(function(type,count){
  const values=[];for(let i=0;i<count;i++){const id=heap.get(128+i*4),x=heap.get(1024+i*16),y=heap.get(1024+i*16+8);values.push({id,x,y,hit:options.hit([x,y])});if(type===1)heldTouch.delete(id);else heldTouch.set(id,options.hit([x,y]));}
  record({kind:'touch',type,values,active:[...heldTouch]});
 },128,1024);
 GodotInput.setInputKeyData=(code,key)=>{keyData={code,key}};
 GodotInput.inputKeyCallback=(pressed,repeat,modifiers)=>{if(pressed)heldKeys.add(keyData.code);else heldKeys.delete(keyData.code);record({kind:'key',...keyData,pressed,repeat,modifiers});};
 GodotEventListeners.add(canvas,'keydown',e=>GodotInput.onKeyEvent(true,e),false);
 GodotEventListeners.add(canvas,'keyup',e=>GodotInput.onKeyEvent(false,e),false);
 return {report:()=>({label:'Exact dist/index.js input callbacks with mock sinks; no WASM/gameplay',sourceSha256:SOURCE_SHA,trustedMouseDownHits:{...counts},heldMouse:[...heldMouse],heldTouch:[...heldTouch],heldKeys:[...heldKeys],events:events.slice()}),reset:()=>{canvas.__livehouseCancelInput();events.length=0;for(const n in counts)delete counts[n];}};
};
}());
'''.replace('SOURCE_SHA', repr(sha))
output = root / 'tests/browser_runtime_input_probe.js'
output.write_text(prefix + body + suffix)
print('Extracted verified runtime input functions:', output)
print('dist/index.js sha256:', sha)
