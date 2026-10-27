#!/usr/bin/env python3
"""Deterministic original sound design, numeric synthesis; no sampled audio input.
Run --baseline PATH for measurements/montage with unchanged baseline sounds.
"""
import argparse,hashlib,io,json,math,wave
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]; RATE=48000
SPECS={
 'rifle_emit':(.150,.17,'Single rounded arcade pop, no repeated shots or piercing crack'),
 'heart_hit':(.220,.17,'Warm hollow bubble and brief harmonic shimmer'),
 'peach_emit':(.230,.14,'Soft elastic fruit pluck with leafy air'),
 'peach_hit':(.190,.19,'Cushioned fruit pop, not a punch or gunshot'),
 'cake_warn':(.240,.12,'Two soft confectionery chimes at cast lock'),
 'cake_drop':(.320,.12,'Descending filtered air and rounded falling whistle'),
 'cake_land':(.260,.21,'Two-stage sponge thud with soft crumb rustle'),
}
def db(x): return round(20*math.log10(max(float(x),1e-15)),6)
def wavbytes(x):
 p=np.rint(x*32767).astype('<i2'); b=io.BytesIO()
 with wave.open(b,'wb') as w:w.setparams((1,2,RATE,0,'NONE','not compressed'));w.writeframes(p.tobytes())
 return b.getvalue()
def read(p):
 with wave.open(str(p)) as w:
  assert w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==RATE
  return np.frombuffer(w.readframes(w.getnframes()),'<i2').astype(float)/32768

def make(c,v):
 dur,gain,intent=SPECS[c];dur+=.004*(v-1);n=round(RATE*dur);t=np.arange(n)/RATE;x=np.zeros(n)
 rng=np.random.Generator(np.random.PCG64(int.from_bytes(hashlib.sha256(f'refined-v1/{c}/{v}'.encode()).digest()[:8],'little')))
 def env(offset,attack,decay):
  z=np.maximum(t-offset,0);return (1-np.exp(-z/attack))*np.exp(-z/decay)*(t>=offset)
 def noise(g,lo,hi,off=0,attack=.004,decay=.03):
  nonlocal x
  z=rng.uniform(-1,1,n);f=np.fft.rfftfreq(n,1/RATE);a=np.fft.rfft(z)
  a*=np.exp(-(f/hi)**4)*(1-np.exp(-(f/lo)**4));z=np.fft.irfft(a,n);z/=max(np.sqrt(np.mean(z*z)),1e-8)
  x+=g*z*env(off,attack,decay)
 def tone(g,f,off=0,attack=.004,decay=.04,end=None):
  nonlocal x
  z=np.maximum(t-off,0);f*=1-.018*(v-1);end=f if end is None else end*(1-.018*(v-1))
  phase=2*np.pi*(f*z+(end-f)*(.055*z-.055**2*(1-np.exp(-z/.055)))/.055)
  x+=g*np.sin(phase)*env(off,attack,decay)
 if c=='rifle_emit':
  noise(.30,450,3100,attack=.0015,decay=.009);tone(.7,330,attack=.0015,decay=.023,end=230);tone(.12,650,decay=.015)
 elif c=='heart_hit':
  tone(.6,620,attack=.004,decay=.035,end=390);tone(.18,930,off=.018,decay=.041);noise(.08,500,2400,decay=.03)
 elif c=='peach_emit':
  tone(.65,350,attack=.008,decay=.032,end=590);tone(.20,710,off=.018,decay=.03);noise(.12,700,3300,attack=.015,decay=.041)
 elif c=='peach_hit':
  tone(.7,430,attack=.0025,decay=.029,end=230);tone(.14,760,off=.010,decay=.018);noise(.19,450,2400,attack=.003,decay=.02)
 elif c=='cake_warn':
  tone(.43,660,attack=.005,decay=.04);tone(.34,830,off=.065,attack=.006,decay=.042);tone(.07,1320,decay=.025)
 elif c=='cake_drop':
  noise(.18,350,2200,attack=.05,decay=.05);tone(.34,680,attack=.035,decay=.055,end=270)
 elif c=='cake_land':
  tone(.7,260,attack=.003,decay=.043,end=180);tone(.24,380,off=.027,attack=.006,decay=.037);noise(.18,280,1900,attack=.005,decay=.032);noise(.07,1300,3400,off=.03,attack=.01,decay=.028)
 x*=np.minimum(t/.002,1)*np.minimum((dur-t)/.025,1);x-=x.mean();x*=np.sin(np.pi*np.clip(t/dur,0,1))**.2
 x*=.28/max(abs(x));x[0]=x[-1]=0
 return wavbytes(x)
def stats(x):return {'seconds':len(x)/RATE,'peak':float(max(abs(x))),'peak_dbfs':db(max(abs(x))),'rms_dbfs':db(np.sqrt(np.mean(x*x))),'clipped_samples':int(np.sum(abs(x)>=1)),'endpoints':[float(x[0]),float(x[-1])]}
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--check',action='store_true');args=ap.parse_args();out=ROOT/'assets/audio/refined';out.mkdir(parents=True,exist_ok=True)
 meta=[]
 for c,(dur,gain,intent) in SPECS.items():
  for v in (1,2):
   p=out/f'{c}_{v}.wav';b=make(c,v)
   if args.check:assert p.read_bytes()==b,p
   else:p.write_bytes(b)
   x=read(p);s=stats(x);assert s['peak']<=.281 and s['clipped_samples']==0 and s['endpoints']==[0,0]
   meta.append({'file':p.name,'sha256':hashlib.sha256(b).hexdigest(),'gain':gain,'intent':intent,**s})
 old=args.baseline/'assets/audio'; assert hashlib.sha256((old/'meow.wav').read_bytes()).hexdigest()=='551cc7c8a4c90e6a120de466707ba36670f05dc8e0d96223a8a355b47cfd3eb2'
 seq=[('挥空拳','swing_punch',.12),('挥空踢','swing_kick',.14),('轻拳命中','hit_light',.20),('直拳命中','hit_straight',.22),('重拳命中','hit_heavy',.24),('踢击命中','hit_kick',.23),('格挡','block',.18),('破防','guard_break',.22),('因：真实猫叫','meow',.11),('鱼：爱心发射','heart_emit',.14),('鱼：爱心接触','heart_hit',.17),('七：单发','rifle_emit',.17),('桃：桃子发射','peach_emit',.14),('桃：桃子接触','peach_hit',.19),('哈：预警','cake_warn',.12),('哈：下落','cake_drop',.12),('哈：着地/命中','cake_land',.21)]
 clips=[];timeline=[];cursor=0
 for label,c,g in seq:
  p=out/f'{c}_1.wav' if c in SPECS else old/('meow.wav' if c=='meow' else f'p2/{c}_1.wav');x=read(p)*g
  timeline.append({'start_seconds':cursor/RATE,'label':label,'cue':c,'runtime_gain':g});clips.extend([x,np.zeros(round(.55*RATE))]);cursor+=len(x)+round(.55*RATE)
 mix=np.concatenate(clips);preview=ROOT/'preview';preview.mkdir(exist_ok=True)
 # Preview +12dB ONLY, documented; runtime assets and gains unchanged.
 amplified=mix*4;assert max(abs(amplified))<1
 report={'source':'Original numeric synthesis; no external samples. Existing meow retained with original CC0 provenance.','assets':meta,'voice_limit':10,'group_slots':{'combat':6,'voice':2,'ui':2},'conservative_sample_peak_bound':6*.299*.24+2*max(abs(read(old/'meow.wav')))*.11+2*.299*.12,'preview_gain_db':db(4),'preview':stats(amplified),'runtime_level_preview':stats(mix),'sequence':timeline,'subjective_audition':'Not performed: no confirmed audio-input/listening tool available.'}
 assert report['conservative_sample_peak_bound']<.68
 if not args.check:
  (preview/'audio-selection-preview.wav').write_bytes(wavbytes(amplified));(out/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
  (preview/'试听顺序.txt').write_text('17 段独立音效，片段间隔 0.55 秒。预览统一放大 +12.04 dB 便于试听，游戏内仍使用原始低增益；不是实际对局录音。无 BGM、人声旁白。\n'+'\n'.join(f"{r['start_seconds']:.3f}s　{r['label']}" for r in timeline)+'\n尚未通过真实扬声器/耳机主观试听。\n')
 print(json.dumps({'files':len(meta),'preview':report['preview'],'bound':report['conservative_sample_peak_bound'],'check':args.check}))
if __name__=='__main__':main()
