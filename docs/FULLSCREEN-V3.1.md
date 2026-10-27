# v3.1 全屏横屏：独立网页补丁

This patch starts from frozen RC3. It changes the web shell and packaging only. No game script, character model, audio code, PCK, engine binary, engine JS, credit or permission is changed. The candidate has not been published and does not change owner-private site access.

## UI and API semantics

- “全屏横屏” is in a dedicated toolbar, not an overlay. Normal height is 53 CSS px including a 44px button, padding and border; safe-area top is added. Messages may grow the toolbar on very narrow viewports. The canvas occupies the remaining area; left/right/bottom safe-area insets are reserved separately.
- The button calls the detected standard requestFullscreen method synchronously during its click event, or the real prefixed WebKit method when available. It does not spoof fullscreen or rotate CSS. It never changes browser flags, OS orientation settings or iframe permissions.
- Only confirmed fullscreen entry triggers screen.orientation.lock('landscape'). Fullscreen and orientation failures have separate Chinese messages. A denied lock keeps successful fullscreen; it never claims landscape was locked when the promise rejected.
- Repeated pending clicks are coalesced. The exit control becomes available before the orientation promise completes. Exiting or browser Escape clears this controller’s lock; a late successful lock after exit is explicitly released. Fullscreenchange drives restoration. No layout-only resize steals focus. Entry/exit and failures return focus to the game canvas without touching audio.
- Unsupported element fullscreen, policy-denied fullscreen, rejected request, missing lock, rejected lock, exit rejection and delayed events all leave a usable control and Chinese guidance. There is no new dialog blocking Godot controls.

## Canvas sizing and touch coordinates

Godot’s original canvasResizePolicy 2 overwrites the canvas to window.innerWidth/innerHeight. It would overlap a separate toolbar. The patch instead uses documented policy 0 and ResizeObserver, window/visualViewport resize, orientationchange and DPR media changes. It measures the canvas frame, writes canvas.width/height only when changed, and leaves CSS dimensions at the measured frame size.

The backing-buffer ratio is max(devicePixelRatio, min(2, 300 / CSS-height)). The bounded minimum logical height avoids clipping RC3’s existing 294px result card on tiny landscape windows. It uses one uniform ratio, with only subpixel rounding, not rotation or nonuniform stretching. Hidden zero-size frames are skipped. The original Godot loader’s computePosition converts pointer/touch coordinates using (clientX - canvasRect.x) * canvas.width / canvasRect.width and the corresponding Y formula. Thus the reserved toolbar offset and buffer scale are accounted for by existing input code.

At 568×320 and DPR 1, the canvas is 568×267 CSS px with 638×300 backing pixels. The result card fits, but existing bottom touch targets are approximately 99–102×30 CSS px. This tiny landscape is less comfortable and has not been redesigned. The requested 844×390, 390×844 and 375×667 profiles do not use the minimum-height adjustment at DPR 1.

## Reproduction

To rebuild the exact web-only patch without re-exporting assets:

1. Copy RC3/web into a fresh candidate web folder.
2. Run python3 source/scripts/apply_fullscreen_patch.py path/to/candidate/web/index.html from this source package.
3. Check that the nine non-HTML web files have the RC3 hashes in the candidate manifest.

For a fresh Godot export, scripts/pack_web.py now applies the same UI after its existing loader/credits packaging. No extra JS/CSS web files are needed because the two source modules are inlined. Production web remains exactly ten files. Keep QA harnesses out of the published directory.

Run logic checks with node source/tests/fullscreen_ui_test.cjs. Run native geometry checks with Godot 4.6.3: godot --headless --path source --script tests/fullscreen_hud_layout_test.gd. Use the project’s existing XDG runtime directories. The QA HTML can be copied temporarily beside index.html for browser testing, then removed. It uses ordinary iframe viewports and real API/policy state, without overriding browser APIs.

## Verified capability limits (2026-10-25)

requestFullscreen requires transient user activation and applicable fullscreen permission. Embedded pages need the host’s allowfullscreen/allow policy. lock('landscape') is separately limited; it commonly requires mobile fullscreen and may reject when the document is inactive/hidden, sandboxed, or the implementation cannot lock.

Current MDN compatibility data lists Safari iOS element fullscreen as iPad-only, not iPhone. Safari 16.4 introduced unprefixed element fullscreen on macOS and iPadOS; iPad has a browser-owned exit overlay/swipe gesture that the app cannot remove. Current MDN data lists Safari lock/unlock unsupported, despite orientation type/angle/change support. This is why neither iPhone real fullscreen nor Safari automatic landscape is promised. No experimental flags are requested.

Primary references:
- https://developer.mozilla.org/en-US/docs/Web/API/Element/requestFullscreen
- https://developer.mozilla.org/en-US/docs/Web/API/ScreenOrientation/lock
- https://fullscreen.spec.whatwg.org/#dom-element-requestfullscreen
- https://w3c.github.io/screen-orientation/#lock-method
- https://webkit.org/blog/13966/webkit-features-in-safari-16-4/#fullscreen-api
- https://raw.githubusercontent.com/mdn/browser-compat-data/main/api/Element.json
- https://raw.githubusercontent.com/mdn/browser-compat-data/main/api/ScreenOrientation.json

## Verification and unverified scope

- 21 deterministic controller checks pass, including synchronous gesture request, repeat clicks, success/failure, prefixed event-based API, real-vs-locked status distinction, exit/late-lock races, DPR sizing, hidden canvas and no Escape interception. Mocks establish logic only, not browser support.
- 178 native Godot geometry/input checks pass across nine reduced/high-DPR/safe-area-equivalent viewport fixtures. They cover menu/result/pause fit, pause/mute containment, individual touch target containment, simultaneous movement and kick, independent release, canceled touches, and pause clearing held input. These are native tests, not browser/iPhone certification.
- Actual ordinary cloud Chrome confirmed: document.fullscreenElement = game-shell after the user-style click; genuine desktop orientation-lock rejection and correct fallback; exit button; native window Escape; repeat clicks; fullscreenchange/layout restoration; actual iframe fullscreen policy denial. The browser QA JSON files record these states.
- Actual DOM iframe viewports 844×390, 390×844, 375×667 and 568×320 all confirm no toolbar/canvas overlap, the 100×44px fullscreen control inside the toolbar, correct backing sizes, and canvas inside viewport. Insets greater than zero and DPR 2 were logic/native fixtures, not physical browser-device tests.
- This Chrome lacks WebGL 2, and the original honest WebGL error remains visible. Browser-rendered gameplay, touch hardware, physical iPhone/iPad/Android, successful physical landscape locking, notch safe areas and audio output are not certified. The game/audio source and PCK are byte-identical to RC3, but that does not substitute for real-device tests.

## Persistent review package

The combined source/web/QA candidate deliberately excludes the three browser DOM screenshots. They remain available for local inspection only. Packaged QA evidence consists of text logs, JSON measurements and the reproducible browser harness; it does not claim visual gameplay certification. Redundant nested ZIPs and pinned readback files are also excluded.

## Next gameplay v4 integration (not part of published v3.1)

The v4 compact HUD fits actual 568×267 logical dimensions with 48px-high direction/action targets and a 210px-high result card. Therefore v4 removes the historical 300px minimum backing height and uses exactly one backing render pixel per CSS pixel, independent of devicePixelRatio. This consciously avoids Retina supersampling: a modest sharpness/performance tradeoff keeps the Godot UI at the tested 48 CSS px target size rather than halving or thirding it on high-DPR displays. DPR2/3 controller tests confirm unchanged backing/CSS sizes and pointer mapping. The old v3.1 measurements above remain historical, not claims about the v4 shell. Fullscreen API and permission behavior are unchanged.
