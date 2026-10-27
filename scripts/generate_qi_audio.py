"""Original arcade single-shot pop. Numeric synthesis only; no external samples."""
from pathlib import Path
import numpy as np,wave,hashlib,json
r=Path(__file__).resolve().parents[1];out=r/'assets/audio/p2';meta=[]
for i in [1,2]:
 rate=48000;t=np.arange(int(rate*.16))/rate;rng=np.random.default_rng(17020+i)
 noise=rng.uniform(-1,1,t.size);noise=np.convolve(noise,np.ones(5)/5,'same')
 sound=.65*noise*np.exp(-t*85)+.38*np.sin(2*np.pi*(260+i*12)*t)*np.exp(-t*38)+.12*np.sin(2*np.pi*900*t)*np.exp(-t*70)
 sound*=np.minimum(1,t/.0005)*np.minimum(1,(.16-t)/.01);sound-=sound.mean();sound*=np.sin(np.pi*np.clip(t/.16,0,1))**.15
 sound*=.28/max(abs(sound));sound[0]=sound[-1]=0
 pcm=np.rint(sound*32767).astype('<i2');p=out/f'rifle_emit_{i}.wav'
 with wave.open(str(p),'wb') as f:f.setparams((1,2,rate,0,'NONE','not compressed'));f.writeframes(pcm.tobytes())
 meta.append({'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'peak':max(abs(pcm.astype(float)))/32768,'seconds':len(pcm)/rate,'source':'Original numeric synthesis, no external samples','gain':.18})
(out/'qi-audio-manifest.json').write_text(json.dumps(meta,indent=2))
