# Windows desktop build verification — 2026-10-27

## Identity and preservation
- Baseline: functional v18 / RC19, expected Sites20, commit `b959271430231e7b2b33d87324e42e67605bdd78`.
- Original ZIP SHA256 verified: `2fec7b7160f5504e76ab3d8f1bd5bc4ac7fb8f785d5715b88d3a9c353dcc91ed`.
- All 673 original manifest files verified. Original restored archive/source remains unchanged.
- Only four existing files differ in desktop source: project.godot, export_presets.cfg, scripts/main.gd, scripts/hud.gd. All assets, stage scripts, combat/AI/audio code and provenance documents unchanged.
- No website publication or online deployment performed.

## Binary/export
- Official Godot 4.6.3, matching official standard export templates; SHA512 matched official release checksum.
- Release PE32+ Windows x86_64 GUI executable. EXE bytes exactly match official unmodified release template (custom resource modification disabled).
- External PCK, Compatibility renderer, no code signing. No third-party executable downloaded.
- Windows imports are OS DLLs; both EXE and PCK must remain together.
- Final export and final packed-runtime 300-frame startup exited 0.
- Final exported PCK loaded independently in Linux Godot headless: all five roles, all 20 ordered manual pairs, random-role selection, 22 cues / 43 audio streams / 10 audio voices passed. This is resource/logic validation, not Windows execution.

## Automated results
- Desktop UI: 36 assertions, 0 failures, repeated successfully against the final exported PCK (clean exit0). Keyboard move/release/jump/punch/Esc, fullscreen routing avoiding debug cheat, all five role cooldown labels, hidden touch UI, 52px help strip fit at 960×600/1280×800/1920×1080, minimum window size.
- Desktop weighted skin camera projection: 18,020 assertions, 0 failures at those three desktop resolutions.
- Shared fight window: 1,278 assertions, 0 failures.
- Stage world bounds: 556,652 assertions, 0 failures; 20 ordered pairs, repeated.
- Random selection unit: 202,072 assertions, 0 failures; integration: 301 assertions, 0 failures.
- Refined audio: 42 assertions, 0 failures. Historical harness teardown reports two resources still in use; no clean-teardown claim for that harness. Final packed smoke exits cleanly.
- Ha cake rules: 367,444 assertions, 0 failures.
- Qi combat adapted to five-role registry: 513 assertions, 0 failures.
- Tao combat adapted to five-role registry: 711,040 assertions, 0 failures; 48 pair stress rounds repeated.
- Core combat, complete live match, knockdown (211), projectiles (247), and spacing (224) passed.

## Harness adjustments / unsuccessful attempts retained
- Original historical Qi/Tao harnesses expected three/four total roles and clamped invalid roles to index2/3. Each failed only those two obsolete registry assertions. Copies named desktop_qi/tao_combat_test.gd change only expected current count to5 and final clamp index to4; original tests retained.
- Original broad multi-device camera harness reached a90-second timeout. Desktop copy tests current supported window sizes with600-second allowance and passed; no claim that the old mobile-resolution harness passed.
- Initial random unit harness lacked its output directory and timed out after a write error. Directory created; final rerun passed cleanly.
- An initial packed smoke raced the exporter and saw a partially written PCK. After export completed, final independent PCK smoke passed cleanly. Only the completed final PCK is packaged.
- First import wrote warnings about sandboxed editor cache/settings paths. Subsequent CLI checks used writable XDG directories.

## Limits
No Windows computer or Wine runtime was available. Windows actual launch, hardware/GPU performance, Windows fullscreen transitions and subjective audio quality are not certified. Native Linux UI results are recorded separately below. Do not disable antivirus/security checks for this unsigned build. No visual-quality or FPS uplift is claimed merely from native export.

## Native Linux graphical smoke (independent reviewer)
- Standalone unembedded Godot source render passed: five-role/random menu, Qi vs Fish and Ha vs Yin, character models, scrolling stage, HUD and AI movement visible; Esc pause shown in both.
- Touch overlays absent; keyboard/special labels visible; no blocking visual defect found.
- F11 changed the native window to borderless1364×1024; Alt+Enter restored1280×800. This validates Linux native window behavior, not Windows OS behavior.
- Initial embedded editor emitted expected fullscreen limitation plus cloud VSync unsupported, audio device unavailable/Dummy fallback, and existing variable-shadow warning; standalone mode was used for actual fullscreen verification.
- Audio backend Dummy; no subjective listening performed. Windows EXE remains unexecuted.
