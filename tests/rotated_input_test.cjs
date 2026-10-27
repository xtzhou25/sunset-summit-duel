/* Test the exact JavaScript inserted into the Godot export, without loading WASM. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {execFileSync} = require('node:child_process');
const root = path.resolve(__dirname, '..');
const enginePath = fs.existsSync(path.join(root, 'dist/index.js')) ? path.join(root, 'dist/index.js') : path.join(root, '../web/index.js');
const patch = JSON.parse(execFileSync('python3', ['-c', `
import json,sys
sys.path.insert(0,sys.argv[1])
import patch_rotated_input as p
from pathlib import Path
original=Path(sys.argv[2]).read_text()
patched=p.patch_javascript(original)
assert p.patch_javascript(patched)==patched
assert patched.count(p.MARKER)==1
try:p.patch_javascript('unknown engine')
except ValueError:pass
else:raise AssertionError('Unknown engines must fail closed')
print(json.dumps(dict(compute=p.NEW_COMPUTE,buttons=p.NEW_BUTTONS,move=p.NEW_MOVE,touch=p.NEW_TOUCH,keys=p.NEW_KEYS)))
`, path.join(root, 'scripts'), enginePath], {encoding:'utf8'}));

function harness() {
  let rect = {x:20, y:35, left:20, top:35, right:380, bottom:675, width:360, height:640};
  const canvas = {width:1280,height:720,focusCount:0,focus(){this.focusCount++},getBoundingClientRect(){return rect}};
  const window = {};
  const listeners = [];
  const heap = new Map();
  const mouse = [], moves = [], touches = [], keys = [];
  const ids = 128, coords = 1024;
  const context = {console,canvas,window,Array,Map,Set,Number,
    GodotConfig:{canvas},
    GodotRuntime:{get_func:f=>f,setHeapValue:(address,value,type)=>heap.set(address,value)},
    GodotEventListeners:{add:(target,name,callback,capture)=>listeners.push({target,name,callback,capture})}
  };
  vm.createContext(context);
  vm.runInContext('var GodotInput={getModifiers:function(e){return (e.shiftKey?1:0)+(e.altKey?2:0)+(e.ctrlKey?4:0)+(e.metaKey?8:0)},'+patch.compute+','+patch.keys+'};'+patch.buttons+patch.move+patch.touch, context);
  let keyData=[];
  context.GodotInput.setInputKeyData=(code,key)=>{keyData=[code,key]};
  context.GodotInput.inputKeyCallback=(pressed,repeat,modifiers)=>keys.push([...keyData,pressed,repeat,modifiers]);
  context._godot_js_input_mouse_button_cb((...v)=>{mouse.push(v);return true});
  context._godot_js_input_mouse_move_cb((...v)=>moves.push(v));
  context._godot_js_input_touch_cb((type,count)=>{
    const values=[];
    for(let i=0;i<count;i++)values.push({id:heap.get(ids+i*4),x:heap.get(coords+i*16),y:heap.get(coords+i*16+8)});
    touches.push({type,values});
  },ids,coords);
  function fire(target,type,properties={}) {
    const e={type,button:0,clientX:200,clientY:355,movementX:0,movementY:0,pressure:0.5,
      cancelable:true,prevented:0,preventDefault(){this.prevented++},...properties};
    for(const l of listeners)if(l.target===target&&l.name===type)l.callback(e);
    return e;
  }
  function installRotation() {
    context.LivehouseCanvasInput={
      position(c,e,r){return [(e.clientY-r.top)*c.width/r.height,(r.right-e.clientX)*c.height/r.width]},
      movement(c,e,r){return [e.movementY*c.width/r.height,-e.movementX*c.height/r.width]}
    };
  }
  function key(pressed,code,value,extra={}){
    const event={code,key:value,repeat:false,prevented:0,preventDefault(){this.prevented++},...extra};
    context.GodotInput.onKeyEvent(pressed,event);return event;
  }
  return {canvas,window,context,mouse,moves,touches,keys,key,listeners,fire,installRotation,setRect:r=>rect=r,rect:()=>rect};
}

let checks=0;
function check(name,fn){fn();checks++;console.log('PASS '+name)}
function pairEqual(actual,expected){assert.deepEqual(Array.from(actual),expected)}
function touch(id,clientX,clientY){return {identifier:id,clientX,clientY}}

check('Native listener targets and registrations remain unchanged',()=>{
  const h=harness();
  assert.deepEqual(h.listeners.map(l=>[l.target===h.canvas?'canvas':'window',l.name,l.capture]),[
    ['canvas','mousedown',false],['window','mouseup',false],['window','pointermove',false],
    ['canvas','touchstart',false],['canvas','touchend',false],['canvas','touchcancel',false],['canvas','touchmove',false]
  ]);
});

check('No adapter preserves native coordinates, modifiers, focus and default prevention',()=>{
  const h=harness();
  const e=h.fire(h.canvas,'mousedown',{clientX:110,clientY:195,shiftKey:true,ctrlKey:true});
  assert.deepEqual(h.mouse[0],[1,0,320,180,5]);
  assert.equal(e.prevented,1);assert.equal(h.canvas.focusCount,1);
  h.fire(h.window,'mouseup',{clientX:110,clientY:195});
  assert.deepEqual(h.mouse[1],[0,0,320,180,0]);
  assert.equal(h.canvas.__livehouseCancelInput(),0);
});

check('Clockwise rotation maps all corners, center and outside drag without clamping',()=>{
  const h=harness();h.installRotation();
  const cases=[[[380,35],[0,0]],[[380,675],[1280,0]],[[20,675],[1280,720]],
    [[20,35],[0,720]],[[200,355],[640,360]],[[398,3],[-64,-36]]];
  for(const [input,expected] of cases){
    h.fire(h.canvas,'mousedown',{clientX:input[0],clientY:input[1]});
    assert.deepEqual(h.mouse.at(-1).slice(2,4),expected);
    h.fire(h.window,'mouseup',{clientX:input[0],clientY:input[1]});
  }
});

check('Pointer motion inverse-rotates both axes and retains pressure/modifiers',()=>{
  const h=harness();h.installRotation();
  h.fire(h.window,'pointermove',{clientX:200,clientY:355,movementX:12,movementY:-6,pressure:0.8,altKey:true});
  assert.deepEqual(h.moves[0],[640,360,-12,-24,2,0.8]);
});

check('Missing, invalid, or throwing adapter falls back to unchanged engine behavior',()=>{
  const h=harness();
  for(const position of [null,()=>null,()=>[NaN,5],()=>[1],()=>{throw Error('bad hook')}]){
    h.context.LivehouseCanvasInput={position,movement:()=>[Infinity,2]};
    h.fire(h.window,'pointermove',{clientX:110,clientY:195,movementX:9,movementY:8});
    assert.deepEqual(h.moves.at(-1),[320,180,32,9,0,0.5]);
  }
});

check('Real non-sequential touch IDs and changedTouches reordering survive mapping',()=>{
  const h=harness();h.installRotation();
  const a=touch(91,380,35),b=touch(4,20,675);
  h.fire(h.canvas,'touchstart',{changedTouches:[a,b]});
  assert.deepEqual(h.touches[0],{type:0,values:[{id:91,x:0,y:0},{id:4,x:1280,y:720}]});
  h.fire(h.canvas,'touchmove',{changedTouches:[touch(4,200,355)]});
  assert.deepEqual(h.touches[1],{type:2,values:[{id:4,x:640,y:360}]});
  h.fire(h.canvas,'touchend',{changedTouches:[a]});
  assert.equal(h.canvas.__livehouseCancelInput(),1);
  assert.deepEqual(h.touches.at(-1),{type:1,values:[{id:4,x:-1000000,y:-1000000}]});
});

check('Layout cancellation releases every contact/button once without menu activation',()=>{
  const h=harness();h.installRotation();
  h.fire(h.canvas,'mousedown',{button:0,shiftKey:true});
  h.fire(h.canvas,'mousedown',{button:2});
  h.fire(h.canvas,'touchstart',{changedTouches:[touch(12,200,355),touch(103,250,300)]});
  assert.equal(h.canvas.__livehouseCancelInput(),4);
  assert.equal(h.canvas.__livehouseCancelInput(),0);
  assert.deepEqual(h.mouse.slice(-2),[[0,0,-1000000,-1000000,1],[0,2,-1000000,-1000000,0]]);
  assert.deepEqual(h.touches.slice(-2).map(e=>e.values[0].id),[12,103]);
  assert(h.touches.slice(-2).every(e=>e.type===1&&e.values[0].x<0&&e.values[0].y<0));
});

check('Canceled native sequences cannot regain holds until new input starts',()=>{
  const h=harness();
  h.fire(h.canvas,'mousedown',{button:0});
  h.fire(h.canvas,'touchstart',{changedTouches:[touch(42,200,355)]});
  h.canvas.__livehouseCancelInput();
  const mouseCount=h.mouse.length,touchCount=h.touches.length;
  h.fire(h.canvas,'touchmove',{changedTouches:[touch(42,210,355)]});
  h.fire(h.canvas,'touchend',{changedTouches:[touch(42,210,355)]});
  h.fire(h.window,'mouseup',{button:0});
  assert.equal(h.mouse.length,mouseCount);assert.equal(h.touches.length,touchCount);
  h.fire(h.canvas,'mousedown',{button:0});
  h.fire(h.canvas,'touchstart',{changedTouches:[touch(42,210,355)]});
  assert.equal(h.mouse.length,mouseCount+1);assert.equal(h.touches.length,touchCount+1);
  assert.equal(h.canvas.__livehouseCancelInput(),2);
});

check('Cancellation of one old finger does not suppress a different fresh finger',()=>{
  const h=harness();
  h.fire(h.canvas,'touchstart',{changedTouches:[touch(8,200,355)]});
  h.canvas.__livehouseCancelInput();
  h.fire(h.canvas,'touchstart',{changedTouches:[touch(60,210,355)]});
  h.fire(h.canvas,'touchmove',{changedTouches:[touch(8,205,355),touch(60,215,355)]});
  assert.equal(h.touches.at(-1).values.length,1);assert.equal(h.touches.at(-1).values[0].id,60);
});

check('Browser touchcancel releases outside the button rather than clicking it',()=>{
  const h=harness();
  h.fire(h.canvas,'touchstart',{changedTouches:[touch(7,200,355)]});
  const e=h.fire(h.canvas,'touchcancel',{changedTouches:[touch(7,200,355)],cancelable:false});
  assert.deepEqual(h.touches.at(-1),{type:1,values:[{id:7,x:-1000000,y:-1000000}]});
  assert.equal(e.prevented,0);assert.equal(h.canvas.__livehouseCancelInput(),0);
});

check('Mode change cancellation is safe before touch initialization',()=>{
  const h=harness();delete h.canvas.__livehouseCancelTouches;
  assert.equal(h.canvas.__livehouseCancelInput(),0);
});

check('Offset viewport and nonuniform backing scale use the measured canvas rect',()=>{
  const h=harness();h.installRotation();
  h.canvas.width=1920;h.canvas.height=1080;
  h.setRect({x:37,y:82,left:37,top:82,right:467,bottom:946,width:430,height:864});
  h.fire(h.canvas,'mousedown',{clientX:252,clientY:514});
  assert.deepEqual(h.mouse.at(-1).slice(2,4),[960,540]);
});

check('Keyboard callback preserves real physical codes, repeats, modifiers and releases',()=>{
  const h=harness();
  const e=h.key(true,'KeyA','a',{shiftKey:true});
  assert.equal(e.prevented,1);
  h.key(true,'KeyA','a',{shiftKey:true,repeat:true});
  h.key(false,'KeyA','a');
  assert.deepEqual(h.keys,[['KeyA','a',1,false,1],['KeyA','a',1,true,1],['KeyA','a',0,false,0]]);
  assert.equal(h.canvas.__livehouseCancelInput(),0);
});

check('Mode cancellation releases held keyboard inputs and suppresses stale repeats',()=>{
  const h=harness();
  h.key(true,'KeyA','a');h.key(true,'Space',' ');
  assert.equal(h.canvas.__livehouseCancelInput(),2);
  assert.deepEqual(h.keys.slice(-2),[['KeyA','a',0,0,0],['Space',' ',0,0,0]]);
  const before=h.keys.length;
  const repeat=h.key(true,'KeyA','a',{repeat:true});
  h.key(false,'KeyA','a');h.key(false,'Space',' ');
  assert.equal(repeat.prevented,1);assert.equal(h.keys.length,before);
  h.key(true,'KeyA','a');assert.equal(h.keys.length,before+1);
  assert.equal(h.canvas.__livehouseCancelInput(),1);
});

check('Fresh keyboard input is accepted after a release occurred outside canvas',()=>{
  const h=harness();
  h.key(true,'ArrowLeft','ArrowLeft');h.canvas.__livehouseCancelInput();
  h.key(true,'ArrowLeft','ArrowLeft',{repeat:false});
  assert.equal(h.keys.at(-1)[2],1);assert.equal(h.canvas.__livehouseCancelInput(),1);
});

console.log(`PASS ${checks} rotated-input contract tests; exact export patch guard and idempotence verified.`);
