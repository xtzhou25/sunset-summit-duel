from pathlib import Path
import argparse,hashlib,json,re,shutil,zipfile
parser=argparse.ArgumentParser(description="Freeze a new candidate without overwriting a previous release.")
parser.add_argument("--candidate", required=True, help="New release name, for example RC3")
parser.add_argument("--qa-dir", required=True, help="QA directory relative to project, for example exports/qa-v3")
args=parser.parse_args()
if not re.fullmatch(r"RC[1-9][0-9]*", args.candidate):
 parser.error("candidate must be RC followed by a positive integer")
candidate=args.candidate
root=Path(__file__).resolve().parents[1]
out=root/'release'/candidate
archive=root/'release'/f'Sunset-Summit-Duel-{candidate}.zip'
qa_dir=(root/args.qa_dir).resolve()
if not qa_dir.is_relative_to(root) or not qa_dir.is_dir():
 parser.error('qa-dir must be an existing directory inside project')
if out.exists() or archive.exists():
 parser.error('candidate already exists; frozen releases must not be overwritten')
out.mkdir(parents=True)
source=out/'source';source.mkdir(exist_ok=True)
for name in ['project.godot','main.tscn','export_presets.cfg','README.md']:
 shutil.copyfile(root/name,source/name)
for folder in ['assets','scripts','docs','tests','web-ui']:
 for p in (root/folder).rglob('*'):
  if p.is_file() and '__pycache__' not in p.parts and p.name!='pose_probe.gd':
   dest=source/p.relative_to(root);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
for folder,src in [('web',root/'dist'),('qa',qa_dir)]:
 for p in src.rglob('*'):
  if p.is_file() and p.suffix in ['.mp4','.wav','.gif','.png','.log','.txt','.json','.js','.html','.bin','.pck']:
   dest=out/folder/p.relative_to(src);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,dest)
manifest={str(p.relative_to(out)):{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.rglob('*')) if p.is_file() and p.name!='MANIFEST.json'}
(out/'MANIFEST.json').write_text(json.dumps({'candidate':f'Sunset Summit Duel {candidate}','title':'决战日不落之巅','qa':'LIMITED-QA browser/mobile; native and automated pass','files':manifest},ensure_ascii=False,indent=2))
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in sorted(out.rglob('*')):
  if p.is_file():
   info=zipfile.ZipInfo(f'Sunset-Summit-Duel-{candidate}/'+str(p.relative_to(out)),(2026,10,26,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,p.read_bytes())
with zipfile.ZipFile(archive) as z: assert z.testzip() is None
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'file_count':len(manifest)+1},indent=2))
