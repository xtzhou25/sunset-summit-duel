"""Reproducible v5.1 display shell; fresh export or exact restored RC5 shell upgrade.

This changes HTML only. PCK, loader/config contents other than resize policy,
engine JavaScript and all gameplay assets are left to their separate owners.
"""
from pathlib import Path
import hashlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MARKER = '<!-- livehouse-display-v5.1 -->'
OLD_MARKER = '<!-- livehouse-fullscreen-v3.1 -->'
OLD_CSS_SHA256 = 'e5ad46d477827cf876c6312789c41caff27390dd2d11dad25771460523dcf1db'
OLD_JS_SHA256 = '17c8d701ec3e52b81f39157394bfd67fe9299fa7be4ddd3119eb32850c13f001'
OLD_HEADER = '''<body>
<div id="game-shell">
  <header id="display-toolbar" aria-label="显示设置">
    <p id="display-status" role="status" aria-live="polite" aria-atomic="true">横屏体验更舒展，竖屏也可游玩。</p>
    <button id="fullscreen-button" type="button" aria-controls="game-shell" aria-pressed="false" aria-describedby="display-status">全屏横屏</button>
  </header>
  <main id="game-stage"><div id="canvas-frame">'''
HEADER = '''<body>
<div id="game-shell">
  <header id="display-toolbar" aria-label="显示设置">
    <p id="display-status" role="status" aria-live="polite" aria-atomic="true">页面内横屏不会隐藏浏览器地址栏。</p>
    <button id="page-landscape-button" type="button" aria-controls="game-shell" aria-pressed="false" aria-describedby="display-status">页面内横屏</button>
    <button id="fullscreen-button" type="button" aria-controls="game-shell" aria-pressed="false" aria-describedby="display-status">系统全屏</button>
  </header>
  <main id="game-stage"><div id="canvas-frame">'''
ENGINE_SCRIPT = '<script src="index.js"></script>'
OLD_SCRIPT_START = '</div></main>\n</div>\n<script>\n'


def only_once(html: str, text: str) -> None:
    if html.count(text) != 1:
        raise ValueError('Expected exactly one known shell boundary: ' + text[:70])


def strip_known_rc5_shell(html: str) -> str:
    """Fail closed instead of guessing boundaries of an unknown packed loader."""
    only_once(html, OLD_MARKER)
    start = OLD_MARKER + '\n<style>\n'
    only_once(html, start)
    css = html.split(start, 1)[1].split('</style>', 1)[0]
    if hashlib.sha256(css.encode()).hexdigest() != OLD_CSS_SHA256:
        raise ValueError('Legacy CSS does not match the frozen RC5 shell.')
    only_once(html, OLD_HEADER)
    only_once(html, OLD_SCRIPT_START)
    script_end = '</script>\n' + ENGINE_SCRIPT
    js = html.split(OLD_SCRIPT_START, 1)[1].split(script_end, 1)[0]
    if hashlib.sha256(js.encode()).hexdigest() != OLD_JS_SHA256:
        raise ValueError('Legacy controller does not match the frozen RC5 shell.')
    only_once(html, '"canvasResizePolicy":0')
    html = html.replace(start + css + '</style>\n', '', 1)
    html = html.replace(OLD_HEADER, '<body>', 1)
    html = html.replace(OLD_SCRIPT_START + js + script_end, ENGINE_SCRIPT, 1)
    html = html.replace('<canvas id="canvas" tabindex="0">', '<canvas id="canvas">', 1)
    return html.replace('"canvasResizePolicy":0', '"canvasResizePolicy":2', 1)


def patch_html(html: str) -> str:
    css = (ROOT / 'web-ui/fullscreen.css').read_text()
    js = (ROOT / 'web-ui/fullscreen.js').read_text()
    css_tag = '<style id="livehouse-display-style">\n' + css + '</style>'
    js_tag = '<script id="livehouse-display-controller">\n' + js + '</script>'
    if MARKER in html:
        only_once(html, MARKER)
        only_once(html, HEADER)
        only_once(html, '"canvasResizePolicy":0')
        for tag_id, tag, replacement in [('livehouse-display-style', 'style', css_tag),
                                        ('livehouse-display-controller', 'script', js_tag)]:
            pattern = r'<' + tag + r' id="' + tag_id + r'">\n[\s\S]*?</' + tag + '>'
            matches = list(re.finditer(pattern, html))
            if len(matches) != 1:
                raise ValueError('Expected one v5.1 owned block: ' + tag_id)
            html = html[:matches[0].start()] + replacement + html[matches[0].end():]
        return html
    if OLD_MARKER in html:
        html = strip_known_rc5_shell(html)
    only_once(html, '"canvasResizePolicy":2')
    for boundary in ['</head>', '<body>', '<canvas id="canvas">', ENGINE_SCRIPT]:
        only_once(html, boundary)
    if 'id="game-shell"' in html or 'id="display-toolbar"' in html:
        raise ValueError('Unknown display wrapper; refusing to guess its structure.')
    html = html.replace('</head>', MARKER + '\n' + css_tag + '\n</head>', 1)
    html = html.replace('<body>', HEADER, 1)
    html = html.replace('<canvas id="canvas">', '<canvas id="canvas" tabindex="0">', 1)
    html = html.replace(ENGINE_SCRIPT, '</div></main>\n</div>\n' + js_tag + '\n' + ENGINE_SCRIPT, 1)
    return html.replace('"canvasResizePolicy":2', '"canvasResizePolicy":0', 1)


if __name__ == '__main__':
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'dist/index.html'
    patched = patch_html(target.read_text())
    target.write_text(patched)
    print('Applied v5.1 page-landscape UI:', target)
