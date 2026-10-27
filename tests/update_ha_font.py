from pathlib import Path
from fontTools.ttLib import TTFont,TTCollection
from fontTools import subset
root=Path(__file__).resolve().parents[1];path=root/'assets/ui_font.otf'
old=TTFont(path);unicodes=set(old.getBestCmap())|{ord(c) for c in '哈蛋糕召唤落点'}
collection=TTCollection('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
font=next(f for f in collection.fonts if f['name'].getDebugName(1)=='Noto Sans CJK SC')
options=subset.Options();options.name_IDs=['*'];options.name_legacy=True;options.name_languages=['*'];options.notdef_glyph=True;options.notdef_outline=True;options.recommended_glyphs=True
worker=subset.Subsetter(options=options);worker.populate(unicodes=unicodes);worker.subset(font);font.save(path)
new=TTFont(path);assert unicodes<=set(new.getBestCmap());print('glyph repertoire',len(new.getBestCmap()))
