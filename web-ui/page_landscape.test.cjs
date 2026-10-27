/* Deterministic shell/input math checks, not browser or phone certification. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const code = fs.readFileSync(path.join(__dirname, 'fullscreen.js'), 'utf8');
class Target {
 constructor() { this.events={};this.attrs={};this.style={};this.disabled=false;this.textContent=''; }
 addEventListener(n,f){(this.events[n] ||= []).push(f)}
 emit(n,e={}){for(const f of this.events[n]||[])f(e)}
 setAttribute(k,v){this.attrs[k]=v}
 focus(){this.focusCount=(this.focusCount||0)+1}
}
const flush=async()=>{for(let i=0;i<6;i++)await Promise.resolve()};
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return{promise,resolve,reject}};
function fixture(options={}) {
 const doc=new Target(),win=new Target(),shell=new Target(),frame=new Target(),canvas=new Target(),button=new Target(),pageButton=new Target(),status=new Target();
 const nodes={'game-shell':shell,'canvas-frame':frame,canvas,'fullscreen-button':button,'page-landscape-button':pageButton,'display-status':status};
 doc.getElementById=id=>nodes[id];doc.fullscreenElement=null;doc.fullscreenEnabled=options.enabled!==false;
 win.innerWidth=options.width||390;win.innerHeight=options.height||844;win.devicePixelRatio=options.dpr||1;
 const vv=new Target();Object.assign(vv,{width:win.innerWidth,height:win.innerHeight,offsetLeft:0,offsetTop:0});if(!options.noVisualViewport)win.visualViewport=vv;
 const calls={request:0,exit:0,lock:0,cancel:[]};win.screen={orientation:{lock(){calls.lock++;throw Error('must never lock')}}};
 let toolbar=53, zero=false;
 Object.defineProperty(frame,'clientWidth',{get:()=>zero?0:parseInt(shell.style.width||'390')});
 Object.defineProperty(frame,'clientHeight',{get:()=>zero?0:Math.max(0,parseInt(shell.style.height||'844')-toolbar)});
 frame.getBoundingClientRect=()=>{throw Error('fitCanvas must not use transformed bounds')};
 canvas.getBoundingClientRect=()=>{
  const rotated=win.LivehouseDisplay.rotated,w=frame.clientWidth,h=frame.clientHeight,l=parseFloat(shell.style.left||0),t=parseFloat(shell.style.top||0);
  return rotated ? {left:l,top:t,right:l+h,bottom:t+w,width:h,height:w} : {left:l,top:t+toolbar,right:l+w,bottom:t+toolbar+h,width:w,height:h};
 };
 canvas.__livehouseCancelInput=()=>calls.cancel.push({mode:win.LivehouseDisplay?.mode,rotated:win.LivehouseDisplay?.rotated,transform:shell.style.transform,width:canvas.width,height:canvas.height});
 const frames=[],timers=new Map();let timer=0;
 win.requestAnimationFrame=f=>{frames.push(f);return frames.length};win.setTimeout=f=>{timers.set(++timer,f);return timer};win.clearTimeout=id=>timers.delete(id);
 shell.requestFullscreen=()=>{calls.request++;return options.request?options.request({doc,shell}):Promise.resolve().then(()=>{doc.fullscreenElement=shell;doc.emit('fullscreenchange')})};
 doc.exitFullscreen=()=>{calls.exit++;return options.exit?options.exit():Promise.resolve().then(()=>{doc.fullscreenElement=null;doc.emit('fullscreenchange')})};
 if(options.noFullscreen)delete shell.requestFullscreen;
 if(options.prefixed){shell.webkitRequestFullscreen=shell.requestFullscreen;delete shell.requestFullscreen;doc.webkitExitFullscreen=doc.exitFullscreen;delete doc.exitFullscreen}
 let observe;class ResizeObserver{constructor(f){observe=f}observe(){}}
 vm.runInNewContext(code,{window:win,document:doc,ResizeObserver,Promise,Error,Math,Number,String,Object});
 calls.cancel=[];
 return {doc,win,vv,shell,frame,canvas,button,pageButton,status,calls,timers,
  toggle:()=>pageButton.emit('click'),full:()=>button.emit('click'),
  runFrames:()=>{let n=0;while(frames.length){assert(n++<20,'no resize loop');frames.shift()()}},
  setToolbar:n=>{toolbar=n;observe()},setHidden:n=>{zero=n;observe()},
  browserExit:()=>{doc.fullscreenElement=null;doc.emit('fullscreenchange')}
 };
}
const results=[];async function test(name,fn){await fn();results.push(name);console.log('PASS:',name)}
(async()=>{
 await test('normal page is unrotated and delegates original coordinates',()=>{const f=fixture();assert.equal(f.win.LivehouseDisplay.mode,'normal');assert.equal(f.shell.style.transform,'none');assert.equal(f.canvas.width,390);assert.equal(f.canvas.height,791);assert.equal(f.win.LivehouseCanvasInput.position(f.canvas,{clientX:1,clientY:1},f.canvas.getBoundingClientRect()),null)});
 await test('page landscape works with missing fullscreen API without calling lock',()=>{const f=fixture({noFullscreen:true});f.toggle();assert.equal(f.calls.request,0);assert.equal(f.calls.lock,0);assert.equal(f.win.LivehouseDisplay.rotated,true);assert.equal(f.pageButton.textContent,'返回竖屏');assert.match(f.status.textContent,/不是系统全屏/);assert.match(f.status.textContent,/地址栏会保留/)});
 await test('portrait swaps logical shell size and uses untransformed client dimensions',()=>{const f=fixture();f.toggle();assert.equal(f.shell.style.width,'844px');assert.equal(f.shell.style.height,'390px');assert.equal(f.shell.style.transform,'translateX(390px) rotate(90deg)');assert.equal(f.canvas.width,844);assert.equal(f.canvas.height,337)});
 await test('375x667 page landscape leaves 667x322 logical canvas',()=>{const f=fixture({width:375,height:667});f.toggle();assert.equal(f.canvas.width,667);assert.equal(f.canvas.height,322)});
 await test('return is reversible, available, and cancels inputs before mutation',()=>{const f=fixture();f.toggle();assert.equal(f.calls.cancel[0].rotated,false);assert.equal(f.calls.cancel[0].transform,'none');f.toggle();assert.equal(f.calls.cancel[1].rotated,true);assert.equal(f.win.LivehouseDisplay.rotated,false);assert.equal(f.pageButton.textContent,'页面内横屏');assert.equal(f.canvas.width,390);assert.equal(f.canvas.height,791);assert(!f.pageButton.disabled)});
 await test('physical landscape does not rotate or depend on orientation API',()=>{const f=fixture({width:844,height:390});f.toggle();assert.equal(f.win.LivehouseDisplay.mode,'page-landscape');assert.equal(f.win.LivehouseDisplay.rotated,false);assert.equal(f.shell.style.transform,'none');assert.equal(f.pageButton.textContent,'退出页面横屏');assert.equal(f.calls.lock,0)});
 await test('physical rotation disables page transform but retains selected mode',()=>{const f=fixture();f.toggle();f.vv.width=844;f.vv.height=390;f.vv.emit('resize');f.runFrames();assert.equal(f.win.LivehouseDisplay.rotated,false);assert.equal(f.win.LivehouseDisplay.mode,'page-landscape');assert.equal(f.pageButton.textContent,'退出页面横屏');assert.equal(f.calls.cancel.at(-1).rotated,true)});
 await test('addressbar resize exchanges the new visual viewport dimensions',()=>{const f=fixture();f.toggle();f.vv.height=730;f.vv.emit('resize');f.runFrames();assert.equal(f.shell.style.width,'730px');assert.equal(f.canvas.width,730);assert.equal(f.canvas.height,337)});
 await test('visual viewport scroll moves shell and cancels old inputs once',()=>{const f=fixture();f.toggle();const before=f.calls.cancel.length;f.vv.offsetLeft=12;f.vv.offsetTop=24;f.vv.emit('scroll');f.runFrames();assert.equal(f.shell.style.left,'12px');assert.equal(f.shell.style.top,'24px');assert.equal(f.calls.cancel.length,before+1)});
 await test('clockwise input corners and center map once with toolbar offset',()=>{const f=fixture();f.toggle();const r=f.canvas.getBoundingClientRect(),p=f.win.LivehouseCanvasInput.position;for(const [cx,cy,x,y]of [[r.right,r.top,0,0],[r.right,r.bottom,844,0],[r.left,r.top,0,337],[r.left,r.bottom,844,337],[(r.left+r.right)/2,(r.top+r.bottom)/2,422,168.5]]){const out=p(f.canvas,{clientX:cx,clientY:cy},r);assert.equal(out[0],x);assert.equal(out[1],y)}});
 await test('visual viewport offsets are not added twice to client coordinates',()=>{const f=fixture();f.toggle();f.vv.offsetTop=31;f.vv.offsetLeft=7;f.vv.emit('scroll');f.runFrames();const r=f.canvas.getBoundingClientRect(),out=f.win.LivehouseCanvasInput.position(f.canvas,{clientX:r.right,clientY:r.top},r);assert.equal(out[0],0);assert.equal(out[1],0)});
 await test('mouse relative movement rotates axes with correct signs',()=>{const f=fixture();f.toggle();const out=f.win.LivehouseCanvasInput.movement(f.canvas,{movementX:5,movementY:8},f.canvas.getBoundingClientRect());assert.equal(out[0],8);assert.equal(out[1],-5)});
 await test('unrelated canvas and zero-area input use engine fallback',()=>{const f=fixture();f.toggle();assert.equal(f.win.LivehouseCanvasInput.position({}, {}, f.canvas.getBoundingClientRect()),null);assert.equal(f.win.LivehouseCanvasInput.position(f.canvas, {}, {width:0,height:0}),null)});
 await test('DPR2 and DPR3 retain one logical CSS pixel per render pixel',()=>{for(const dpr of [2,3]){const f=fixture({dpr});f.toggle();assert.equal(f.canvas.width,844);assert.equal(f.canvas.height,337)}});
 await test('toolbar height/safe-inset-equivalent changes cancel before buffer resize',()=>{const f=fixture();f.toggle();f.setToolbar(70);f.runFrames();assert.equal(f.calls.cancel.at(-1).height,337);assert.equal(f.canvas.height,320)});
 await test('unchanged resize does not cancel inputs, rewrite canvas or steal focus',()=>{const f=fixture();f.toggle();const c=f.calls.cancel.length,focus=f.canvas.focusCount;f.vv.emit('resize');f.runFrames();assert.equal(f.calls.cancel.length,c);assert.equal(f.canvas.focusCount,focus)});
 await test('hidden zero-size frame retains bounded previous backing size',()=>{const f=fixture();f.setHidden(true);f.runFrames();assert.equal(f.canvas.width,390);assert.equal(f.canvas.height,791)});
 await test('rapid repeated page toggles do not get stuck',()=>{const f=fixture();for(let i=0;i<20;i++)f.toggle();assert.equal(f.win.LivehouseDisplay.mode,'normal');assert(!f.pageButton.disabled);assert.equal(f.calls.cancel.length,20)});
 await test('missing system fullscreen offers independent page mode',()=>{const f=fixture({noFullscreen:true});f.full();assert.match(f.status.textContent,/不支持系统全屏/);f.toggle();assert(f.win.LivehouseDisplay.rotated);assert(!f.pageButton.disabled)});
 await test('system permission denial does not invoke blocked API or block page mode',()=>{const f=fixture({enabled:false});f.full();assert.equal(f.calls.request,0);assert.match(f.status.textContent,/未获系统全屏权限/);f.toggle();assert(f.win.LivehouseDisplay.rotated)});
 await test('system fullscreen request remains synchronous gesture and never locks',async()=>{const f=fixture();f.full();assert.equal(f.calls.request,1);assert(f.button.disabled);await flush();assert.equal(f.button.textContent,'退出系统全屏');assert.equal(f.calls.lock,0);assert(!f.button.disabled)});
 await test('page return remains available while system request is pending',async()=>{const d=deferred(),f=fixture({request:()=>d.promise});f.full();f.full();assert.equal(f.calls.request,1);f.toggle();assert(f.win.LivehouseDisplay.rotated);assert(!f.pageButton.disabled);f.toggle();assert(!f.win.LivehouseDisplay.rotated);d.reject(Error('denied'));await flush();assert(!f.button.disabled)});
 await test('fullscreen failure preserves selected page mode and usable toolbar',async()=>{const f=fixture({request:()=>Promise.reject(Error('denied'))});f.toggle();f.full();await flush();assert(f.win.LivehouseDisplay.rotated);assert.match(f.status.textContent,/未能进入系统全屏/);assert(!f.button.disabled);assert(!f.pageButton.disabled)});
 await test('native fullscreen exit retains page mode and independent return control',async()=>{const f=fixture();f.toggle();f.full();await flush();f.browserExit();assert(f.win.LivehouseDisplay.rotated);assert.equal(f.button.textContent,'系统全屏');assert.equal(f.pageButton.textContent,'返回竖屏');assert.match(f.status.textContent,/页面内横屏仍开启/)});
 await test('page toggle inside real fullscreen never claims browser chrome is retained',async()=>{const f=fixture();f.full();await flush();f.toggle();assert.match(f.status.textContent,/系统全屏/);assert.doesNotMatch(f.status.textContent,/地址栏会保留/);f.toggle();assert.match(f.status.textContent,/当前处于系统全屏/)});
 await test('explicit system exit works without disabling independent page control',async()=>{const f=fixture();f.full();await flush();f.full();await flush();assert.equal(f.calls.exit,1);assert.equal(f.button.textContent,'系统全屏');assert(!f.pageButton.disabled)});
 await test('prefixed void-return API is confirmed through real change event',async()=>{const f=fixture({prefixed:true,request:()=>undefined});f.full();f.doc.webkitFullscreenElement=f.shell;f.doc.emit('webkitfullscreenchange');await flush();assert.equal(f.button.textContent,'退出系统全屏');assert.equal(f.calls.lock,0)});
 await test('fallback without visualViewport uses window dimensions',()=>{const f=fixture({noVisualViewport:true,width:375,height:667});f.toggle();assert.equal(f.canvas.width,667);assert.equal(f.canvas.height,322)});
 await test('blur/pagehide/hidden visibility cancel active inputs',()=>{const f=fixture();f.win.emit('blur');f.win.emit('pagehide');f.doc.hidden=true;f.doc.emit('visibilitychange');assert.equal(f.calls.cancel.length,3)});
 await test('Escape stays with browser/game while toolbar activation keys do not leak',()=>{const f=fixture();let stopped=0;for(const b of [f.button,f.pageButton]){b.emit('keydown',{key:'Escape',stopPropagation:()=>stopped++});assert.equal(stopped,0)}f.pageButton.emit('keydown',{key:' ',stopPropagation:()=>stopped++});assert.equal(stopped,1)});
 console.log(JSON.stringify({passed:results.length,failed:0,kind:'controller mocks and coordinate math, not browser certification'},null,2));
})().catch(e=>{console.error(e);process.exit(1)});
