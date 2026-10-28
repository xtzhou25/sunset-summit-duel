"""Extend the bundled subset font with every character used by runtime UI text.

Run this on a machine that has Noto Sans CJK SC installed:

    python3 tests/update_ui_font.py
"""
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTCollection, TTFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "assets/ui_font.otf"
NOTO = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
SOURCE_DIRS = [ROOT / "scripts", ROOT / "stage-art"]


def used_characters() -> set[str]:
    characters: set[str] = set()
    for directory in SOURCE_DIRS:
        for path in directory.glob("*.gd"):
            characters |= set(path.read_text(encoding="utf-8"))
    # GB2312 level 1 (3,755 common hanzi) so player-entered nicknames do not
    # turn into tofu blocks on the web build where system font fallback is not
    # available to the bundled OTF.
    for first in range(0xB0, 0xD8):
        for second in range(0xA1, 0xFF):
            try:
                characters.add(bytes([first, second]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return characters


def main() -> None:
    old = TTFont(FONT)
    kept = set(old.getBestCmap())
    needed = {ord(c) for c in used_characters() if ord(c) >= 0x80 and ord(c) not in kept}
    if not needed:
        print("glyph repertoire already complete", len(kept))
        return

    collection = TTCollection(NOTO)
    font = next(f for f in collection.fonts if f["name"].getDebugName(1) == "Noto Sans CJK SC")
    unicodes = kept | needed
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.notdef_glyph = True
    options.notdef_outline = True
    options.recommended_glyphs = True
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=unicodes)
    worker.subset(font)
    font.save(FONT)

    new = TTFont(FONT)
    cmap = set(new.getBestCmap())
    missing = sorted(c for c in needed if c not in cmap)
    assert not missing, "missing glyphs: " + "".join(chr(c) for c in missing)
    print("added", len(needed), "glyphs; repertoire", len(cmap))


if __name__ == "__main__":
    main()
