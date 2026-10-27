/* Explicit MOCK of the RC12 fixed joystick ownership and source aggregation.
 * Browser input callbacks are exact exported code; this model is NOT Godot/WASM.
 * Native tests/joystick_native_test.gd verifies the actual GDScript separately. */
(function(root){'use strict';
const directions=['left','right','crouch','jump'];
const attacks=['punch','kick','heavy','roundhouse','special'];
const keys={ArrowLeft:'left',KeyA:'left',ArrowRight:'right',KeyD:'right',ArrowUp:'jump',KeyW:'jump',Space:'jump',ArrowDown:'crouch',KeyS:'crouch',KeyJ:'punch',KeyK:'kick',KeyL:'heavy',KeyI:'roundhouse',KeyO:'special'};
function create(layout){
 const contacts=new Map(),keyboard=new Map(),edges=[];let mouse=null,held=[];
 const same=(a,b)=>a.length===b.length&&a.every((v,i)=>v===b[i]);
 function inside(p,r){return p[0]>=r.x&&p[1]>=r.y&&p[0]<r.x+r.w&&p[1]<r.y+r.h;}
 function padActions(p,previous=[]){const pad=layout().pad,r=Math.max(1,Math.min(pad.w,pad.h)/2);let x=(p[0]-pad.x-pad.w/2)/r,y=(p[1]-pad.y-pad.h/2)/r;const length=Math.hypot(x,y),out=[];if(length<(previous.length?.18:.26))return out;if(length>1){x/=length;y/=length;}if(x<-(previous.includes('left')?.26:.38))out.push('left');else if(x>(previous.includes('right')?.26:.38))out.push('right');if(y>(previous.includes('crouch')?.26:.38))out.push('crouch');else if(y<-(previous.includes('jump')?.26:.38))out.push('jump');return out;}
 function hit(p){if(inside(p,layout().pad))return padActions(p).join('+')||'neutral';return layout().attacks.find(r=>inside(p,r))?.name||null;}
 function start(p){if(inside(p,layout().pad)){if([...contacts.values(),mouse].some(c=>c?.kind==='direction'))return null;return {kind:'direction',actions:padActions(p)};}const name=hit(p);return name?{kind:'attack',actions:[name]}:null;}
 function move(c,p){if(!c)return null;if(c.kind==='direction')return {kind:'direction',actions:padActions(p,c.actions)};return hit(p)===c.actions[0]?c:null;}
 function sync(){const values=[...contacts.values(),mouse].filter(Boolean).flatMap(c=>c.actions).concat([...keyboard.values()]);const next=directions.concat(attacks).filter(a=>values.includes(a));for(const action of directions.concat(attacks))if(next.includes(action)!==held.includes(action))edges.push({action,pressed:next.includes(action)});held=next;}
 function input(e){
  if(e.kind==='touch')for(const t of e.values){if(e.type===0){contacts.delete(t.id);const c=start([t.x,t.y]);if(c)contacts.set(t.id,c);else contacts.delete(t.id);}else if(e.type===1)contacts.delete(t.id);else if(contacts.has(t.id)){const c=move(contacts.get(t.id),[t.x,t.y]);if(c)contacts.set(t.id,c);else contacts.delete(t.id);}sync();}
  else if(e.kind==='mouse'&&e.button===0){mouse=e.pressed?start([e.x,e.y]):null;sync();}
  else if(e.kind==='move'&&mouse){mouse=move(mouse,[e.x,e.y]);sync();}
  else if(e.kind==='key'){if(e.pressed&&keys[e.code])keyboard.set(e.code,keys[e.code]);else keyboard.delete(e.code);sync();}
 }
 return {input,hit,padActions,report:()=>({label:'MOCK HUD ownership/source model, not actual GDScript',held:held.slice(),contacts:[...contacts].map(([id,c])=>({id,...c})),mouse,keyboard:[...keyboard],edges:edges.slice(-80)}),reset:()=>{contacts.clear();keyboard.clear();mouse=null;held=[];edges.length=0;},same};
}
const api={create,directions,attacks};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.LivehouseDirectionalFixture=api;
}(typeof window!=='undefined'?window:this));
