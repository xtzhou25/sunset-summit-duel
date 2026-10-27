/* Generated exact Godot input callback probe. MOCK sink, NOT WASM gameplay. */
(function(){'use strict';
window.installLivehouseExactRuntimeProbe=function(options){
 const canvas=options.canvas,heap=new Map(),events=[],heldMouse=new Set(),heldTouch=new Map(),heldKeys=new Set(),counts={};
 let currentEvent=null,keyData=null;
 const GodotConfig={canvas};
 const GodotRuntime={get_func:f=>f,setHeapValue:(address,value)=>heap.set(address,value)};
 const GodotEventListeners={add:(target,name,fn,capture)=>target.addEventListener(name,function(e){currentEvent=e;try{fn(e);}finally{currentEvent=null;}},capture)};
 function record(data){const event={kind:data.kind,sourceEvent:currentEvent?.type||'direct cancellation',trusted:currentEvent?.isTrusted||false,...data};events.push(event);if(events.length>160)events.shift();if(options.oninput)options.oninput(event);options.onchange();}
const GodotInput={getModifiers:function(evt){return evt.shiftKey+0+(evt.altKey+0<<1)+(evt.ctrlKey+0<<2)+(evt.metaKey+0<<3)},computePosition:function(evt,rect){
 const canvas=GodotConfig.canvas;
 const adapter=globalThis.LivehouseCanvasInput;
 if(adapter&&typeof adapter.position==="function"){
  try{const pair=adapter.position(canvas,evt,rect);
   if(Array.isArray(pair)&&pair.length===2&&pair.every(Number.isFinite))return pair;
  }catch(_){}
 }
 const rw=canvas.width/rect.width;const rh=canvas.height/rect.height;
 return[(evt.clientX-rect.x)*rw,(evt.clientY-rect.y)*rh];
},livehouseHeldKeys:new Map(),livehouseSuppressedKeys:new Set(),
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
}};
function _godot_js_input_mouse_button_cb(callback){
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
}
function _godot_js_input_mouse_move_cb(callback){
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
}
function _godot_js_input_touch_cb(callback,ids,coords){
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
}
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
 return {report:()=>({label:'Exact dist/index.js input callbacks with mock sinks; no WASM/gameplay',sourceSha256:'a2fdf1de9c45d54c2fa9a9a5ed7d3a81bb310a3706619227a45a6e9c1fb8c581',trustedMouseDownHits:{...counts},heldMouse:[...heldMouse],heldTouch:[...heldTouch],heldKeys:[...heldKeys],events:events.slice()}),reset:()=>{canvas.__livehouseCancelInput();events.length=0;for(const n in counts)delete counts[n];}};
};
}());
