/* Exact production shell adapter + exact export hooks; synthetic events, not a browser test. */
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const shellSource=fs.readFileSync(path.join(root,'web-ui/page_landscape.test.cjs'),'utf8').split('(async()=>{')[0];
const shellContext={require,__dirname:path.join(root,'web-ui'),console};vm.createContext(shellContext);vm.runInContext(shellSource+'\nthis.fixtureFactory=fixture;',shellContext);
const bridgeSource=fs.readFileSync(path.join(root,'tests/rotated_input_test.cjs'),'utf8').split('let checks=0;')[0];
const bridgeContext={require,__dirname:path.join(root,'tests'),console};vm.createContext(bridgeContext);vm.runInContext(bridgeSource+'\nthis.bridgeFactory=harness;',bridgeContext);
let checks=0;function near(actual,expected){checks++;assert.ok(Math.abs(actual-expected)<1e-7,`${actual} vs ${expected}`)}
function emitTouch(h,type,id,x,y){h.fire(h.canvas,type,{changedTouches:[{identifier:id,clientX:x,clientY:y}]})}
const layouts=[[390,844],[375,667],[844,390],[568,320]];
for(const [width,height]of layouts){
 const f=shellContext.fixtureFactory({width,height,dpr:3}),h=bridgeContext.bridgeFactory();
 f.canvas.__livehouseCancelInput=h.canvas.__livehouseCancelInput;
 f.toggle();f.vv.offsetLeft=11;f.vv.offsetTop=23;f.vv.emit('scroll');f.runFrames();
 h.canvas.width=f.canvas.width;h.canvas.height=f.canvas.height;let rect=f.canvas.getBoundingClientRect();h.setRect({...rect,x:rect.left,y:rect.top});
 // Both helpers represent one production canvas; preserve the production adapter unchanged.
 h.context.LivehouseCanvasInput={position:(c,e,r)=>f.win.LivehouseCanvasInput.position(f.canvas,e,r),movement:(c,e,r)=>f.win.LivehouseCanvasInput.movement(f.canvas,e,r)};
 const screen=(x,y)=>f.win.LivehouseDisplay.rotated?[rect.right-y*rect.width/h.canvas.height,rect.top+x*rect.height/h.canvas.width]:[rect.left+x*rect.width/h.canvas.width,rect.top+y*rect.height/h.canvas.height];
 const center=[60,h.canvas.height-60];
 const points=[center,[center[0]+20,center[1]],[center[0]+20,center[1]-20],[center[0]-20,center[1]-20],[-40,h.canvas.height+50],center];
 let first=true;
 for(const logical of points){
  const [sx,sy]=screen(...logical);emitTouch(h,first?'touchstart':'touchmove',91,sx,sy);first=false;
  const v=h.touches.at(-1).values[0];checks++;assert.equal(v.id,91);near(v.x,logical[0]);near(v.y,logical[1]);
 }
 // A second attack finger and its reordered event keep an independent identifier.
 let p=screen(h.canvas.width-35,h.canvas.height-35);emitTouch(h,'touchstart',4,...p);
 p=screen(center[0]+30,center[1]);emitTouch(h,'touchmove',91,...p);checks++;assert.equal(h.touches.at(-1).values[0].id,91);
 // Mode transition releases BOTH before resizing/rotating, with no accidental menu click.
 const count=h.touches.length;f.toggle();const releases=h.touches.slice(count);checks++;assert.deepEqual(Array.from(releases,x=>x.values[0].id),[91,4]);
 for(const e of releases){checks++;assert.equal(e.type,1);checks++;assert.equal(e.values[0].x,-1000000);checks++;assert.equal(e.values[0].y,-1000000)}
 const after=h.touches.length;emitTouch(h,'touchmove',91,...p);emitTouch(h,'touchend',91,...p);emitTouch(h,'touchend',4,...p);checks++;assert.equal(h.touches.length,after);
 // Same id is valid again only with a new start; native cancel is a release outside controls.
 emitTouch(h,'touchstart',91,rect.left+5,rect.top+5);emitTouch(h,'touchcancel',91,rect.left+5,rect.top+5);
 const e=h.touches.at(-1);checks++;assert.equal(e.type,1);checks++;assert.equal(e.values[0].id,91);checks++;assert.equal(e.values[0].x,-1000000);checks++;assert.equal(h.canvas.__livehouseCancelInput(),0);
}
console.log(JSON.stringify({passed:checks,failed:0,layouts,scope:'production adapter + exact Godot JS hooks, synthetic drag/id/cancel sequences; not physical browser/iPhone'},null,2));
