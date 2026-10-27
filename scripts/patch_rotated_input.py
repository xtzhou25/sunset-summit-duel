"""Add bounded coordinate and cancellation hooks to the verified Godot 4.6 export.

Run after every fresh Godot web export. Exact-match guards deliberately reject an
unknown engine rather than silently patching its input implementation incorrectly.
The HTML shell owns window.LivehouseCanvasInput; this file preserves native event
registration, trusted event identity, focus, modifiers, pressure, and prevention.
"""
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[1]
MARKER = "/* livehouse-rotated-input-v1 */"

OLD_COMPUTE = 'computePosition:function(evt,rect){const canvas=GodotConfig.canvas;const rw=canvas.width/rect.width;const rh=canvas.height/rect.height;const x=(evt.clientX-rect.x)*rw;const y=(evt.clientY-rect.y)*rh;return[x,y]}'
OLD_BUTTONS = 'function _godot_js_input_mouse_button_cb(callback){const func=GodotRuntime.get_func(callback);const canvas=GodotConfig.canvas;function button_cb(p_pressed,evt){const rect=canvas.getBoundingClientRect();const pos=GodotInput.computePosition(evt,rect);const modifiers=GodotInput.getModifiers(evt);if(p_pressed){GodotConfig.canvas.focus()}if(func(p_pressed,evt.button,pos[0],pos[1],modifiers)){evt.preventDefault()}}GodotEventListeners.add(canvas,"mousedown",button_cb.bind(null,1),false);GodotEventListeners.add(window,"mouseup",button_cb.bind(null,0),false)}'
OLD_MOVE = 'function _godot_js_input_mouse_move_cb(callback){const func=GodotRuntime.get_func(callback);const canvas=GodotConfig.canvas;function move_cb(evt){const rect=canvas.getBoundingClientRect();const pos=GodotInput.computePosition(evt,rect);const rw=canvas.width/rect.width;const rh=canvas.height/rect.height;const rel_pos_x=evt.movementX*rw;const rel_pos_y=evt.movementY*rh;const modifiers=GodotInput.getModifiers(evt);func(pos[0],pos[1],rel_pos_x,rel_pos_y,modifiers,evt.pressure)}GodotEventListeners.add(window,"pointermove",move_cb,false)}'
OLD_TOUCH = 'function _godot_js_input_touch_cb(callback,ids,coords){const func=GodotRuntime.get_func(callback);const canvas=GodotConfig.canvas;function touch_cb(type,evt){if(type===0){GodotConfig.canvas.focus()}const rect=canvas.getBoundingClientRect();const touches=evt.changedTouches;for(let i=0;i<touches.length;i++){const touch=touches[i];const pos=GodotInput.computePosition(touch,rect);GodotRuntime.setHeapValue(coords+i*2*8,pos[0],"double");GodotRuntime.setHeapValue(coords+(i*2+1)*8,pos[1],"double");GodotRuntime.setHeapValue(ids+i*4,touch.identifier,"i32")}func(type,touches.length);if(evt.cancelable){evt.preventDefault()}}GodotEventListeners.add(canvas,"touchstart",touch_cb.bind(null,0),false);GodotEventListeners.add(canvas,"touchend",touch_cb.bind(null,1),false);GodotEventListeners.add(canvas,"touchcancel",touch_cb.bind(null,1),false);GodotEventListeners.add(canvas,"touchmove",touch_cb.bind(null,2),false)}'
OLD_KEYS = 'onKeyEvent:function(pIsPressed,pEvent){if(GodotInput.inputKeyCallback==null){throw new TypeError("GodotInput.onKeyEvent(): GodotInput.inputKeyCallback is null, cannot process key event.")}if(GodotInput.setInputKeyData==null){throw new TypeError("GodotInput.onKeyEvent(): GodotInput.setInputKeyData is null, cannot process key event.")}const modifiers=GodotInput.getModifiers(pEvent);GodotInput.setInputKeyData(pEvent.code,pEvent.key);GodotInput.inputKeyCallback(pIsPressed?1:0,pEvent.repeat,modifiers);pEvent.preventDefault()}'

# Returning null, missing methods, exceptions or invalid pairs preserve stock input.
NEW_COMPUTE = '''computePosition:function(evt,rect){
 const canvas=GodotConfig.canvas;
 const adapter=globalThis.LivehouseCanvasInput;
 if(adapter&&typeof adapter.position==="function"){
  try{const pair=adapter.position(canvas,evt,rect);
   if(Array.isArray(pair)&&pair.length===2&&pair.every(Number.isFinite))return pair;
  }catch(_){}
 }
 const rw=canvas.width/rect.width;const rh=canvas.height/rect.height;
 return[(evt.clientX-rect.x)*rw,(evt.clientY-rect.y)*rh];
}'''

NEW_BUTTONS = '''function _godot_js_input_mouse_button_cb(callback){
 const func=GodotRuntime.get_func(callback);const canvas=GodotConfig.canvas;
 const held=new Map();const suppressed=new Set();
 function button_cb(p_pressed,evt){
  if(p_pressed)suppressed.delete(evt.button);
  else if(suppressed.delete(evt.button)){if(evt.cancelable)evt.preventDefault();return;}
  const rect=canvas.getBoundingClientRect();const pos=GodotInput.computePosition(evt,rect);
  const modifiers=GodotInput.getModifiers(evt);
  if(p_pressed){held.set(evt.button,modifiers);GodotConfig.canvas.focus();}
  else held.delete(evt.button);
  if(func(p_pressed,evt.button,pos[0],pos[1],modifiers))evt.preventDefault();
 }
 canvas.__livehouseCancelMouse=function(){
  const buttons=Array.from(held);held.clear();
  for(const pair of buttons){suppressed.add(pair[0]);func(0,pair[0],-1000000,-1000000,pair[1]);}
  return buttons.length;
 };
 canvas.__livehouseCancelInput=function(){
  let count=canvas.__livehouseCancelMouse();
  if(typeof canvas.__livehouseCancelTouches==="function")count+=canvas.__livehouseCancelTouches();
  if(typeof GodotInput.cancelLivehouseKeys==="function")count+=GodotInput.cancelLivehouseKeys();
  return count;
 };
 GodotEventListeners.add(canvas,"mousedown",button_cb.bind(null,1),false);
 GodotEventListeners.add(window,"mouseup",button_cb.bind(null,0),false);
}'''

NEW_MOVE = '''function _godot_js_input_mouse_move_cb(callback){
 const func=GodotRuntime.get_func(callback);const canvas=GodotConfig.canvas;
 function move_cb(evt){
  const rect=canvas.getBoundingClientRect();const pos=GodotInput.computePosition(evt,rect);
  let relative=[evt.movementX*canvas.width/rect.width,evt.movementY*canvas.height/rect.height];
  const adapter=globalThis.LivehouseCanvasInput;
  if(adapter&&typeof adapter.movement==="function"){
   try{const pair=adapter.movement(canvas,evt,rect);
    if(Array.isArray(pair)&&pair.length===2&&pair.every(Number.isFinite))relative=pair;
   }catch(_){}
  }
  const modifiers=GodotInput.getModifiers(evt);
  func(pos[0],pos[1],relative[0],relative[1],modifiers,evt.pressure);
 }
 GodotEventListeners.add(window,"pointermove",move_cb,false);
}'''

NEW_TOUCH = '''function _godot_js_input_touch_cb(callback,ids,coords){
 const func=GodotRuntime.get_func(callback);const canvas=GodotConfig.canvas;
 const held=new Map();const suppressed=new Set();
 function writeTouch(i,id,pos){
  GodotRuntime.setHeapValue(coords+i*2*8,pos[0],"double");
  GodotRuntime.setHeapValue(coords+(i*2+1)*8,pos[1],"double");
  GodotRuntime.setHeapValue(ids+i*4,id,"i32");
 }
 function touch_cb(type,evt){
  if(type===0)GodotConfig.canvas.focus();
  const rect=canvas.getBoundingClientRect();const touches=evt.changedTouches;
  let count=0;
  for(let i=0;i<touches.length;i++){
   const touch=touches[i];const id=touch.identifier;
   if(type===0)suppressed.delete(id);
   else if(suppressed.has(id)){if(type===1)suppressed.delete(id);continue;}
   const pos=evt.type==="touchcancel"?[-1000000,-1000000]:GodotInput.computePosition(touch,rect);
   if(type===1)held.delete(id);else held.set(id,pos);
   writeTouch(count++,id,pos);
  }
  if(count)func(type,count);
  if(evt.cancelable)evt.preventDefault();
 }
 canvas.__livehouseCancelTouches=function(){
  const contacts=Array.from(held.keys());held.clear();
  // Deliver one release at a time, respecting the engine's fixed touch buffer.
  // Outside coordinates avoid treating cancellation as a menu button click:
  // Godot 4.6 maps touchcancel to release without setting InputEvent.canceled.
  for(const id of contacts){suppressed.add(id);writeTouch(0,id,[-1000000,-1000000]);func(1,1);}
  return contacts.length;
 };
 GodotEventListeners.add(canvas,"touchstart",touch_cb.bind(null,0),false);
 GodotEventListeners.add(canvas,"touchend",touch_cb.bind(null,1),false);
 GodotEventListeners.add(canvas,"touchcancel",touch_cb.bind(null,1),false);
 GodotEventListeners.add(canvas,"touchmove",touch_cb.bind(null,2),false);
}'''

NEW_KEYS = '''livehouseHeldKeys:new Map(),livehouseSuppressedKeys:new Set(),
cancelLivehouseKeys:function(){
 const keys=Array.from(GodotInput.livehouseHeldKeys.values());GodotInput.livehouseHeldKeys.clear();
 if(!GodotInput.inputKeyCallback||!GodotInput.setInputKeyData)return 0;
 for(const entry of keys){
  GodotInput.livehouseSuppressedKeys.add(entry.identity);
  GodotInput.setInputKeyData(entry.code,entry.key);
  GodotInput.inputKeyCallback(0,0,entry.modifiers);
 }
 return keys.length;
},onKeyEvent:function(pIsPressed,pEvent){
 if(GodotInput.inputKeyCallback==null)throw new TypeError("GodotInput.onKeyEvent(): GodotInput.inputKeyCallback is null, cannot process key event.");
 if(GodotInput.setInputKeyData==null)throw new TypeError("GodotInput.onKeyEvent(): GodotInput.setInputKeyData is null, cannot process key event.");
 const identity=pEvent.code||pEvent.key;
 if(GodotInput.livehouseSuppressedKeys.has(identity)){
  if(!pIsPressed){GodotInput.livehouseSuppressedKeys.delete(identity);pEvent.preventDefault();return;}
  if(pEvent.repeat){pEvent.preventDefault();return;}
  GodotInput.livehouseSuppressedKeys.delete(identity);
 }
 const modifiers=GodotInput.getModifiers(pEvent);
 if(pIsPressed)GodotInput.livehouseHeldKeys.set(identity,{identity:identity,code:pEvent.code,key:pEvent.key,modifiers:modifiers});
 else GodotInput.livehouseHeldKeys.delete(identity);
 GodotInput.setInputKeyData(pEvent.code,pEvent.key);
 GodotInput.inputKeyCallback(pIsPressed?1:0,pEvent.repeat,modifiers);
 pEvent.preventDefault();
}'''

PATCHES = ((OLD_COMPUTE, NEW_COMPUTE), (OLD_BUTTONS, NEW_BUTTONS),
           (OLD_MOVE, NEW_MOVE), (OLD_TOUCH, NEW_TOUCH), (OLD_KEYS, NEW_KEYS))


def patch_javascript(source: str) -> str:
    if MARKER in source:
        if source.count(MARKER) != 1 or any(source.count(new) != 1 for _, new in PATCHES):
            raise ValueError("Input patch marker exists, but its verified implementation differs.")
        return source
    for old, _ in PATCHES:
        if source.count(old) != 1:
            raise ValueError("Unsupported Godot export: expected exactly one " + old[:70])
    for old, new in PATCHES:
        source = source.replace(old, new, 1)
    return MARKER + "\n" + source


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="?", type=Path, default=ROOT / "dist/index.js")
    parser.add_argument("--output", type=Path, help="Write a separate file instead of replacing target.")
    args = parser.parse_args()
    original = args.target.read_text()
    result = patch_javascript(original)
    destination = args.output or args.target
    if result != original or args.output:
        destination.write_text(result)
    print("Verified Godot rotated-input hooks:", destination)


if __name__ == "__main__":
    main()
