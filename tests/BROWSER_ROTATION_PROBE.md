# v7 browser directional rotation probe

This is a production-shell / input-bridge regression, not gameplay verification.
The shell, stylesheet and extracted callback functions are unchanged RC6 code.
The continuous-pad hit targets and HUD source/ownership sink are explicit mocks;
`directional_hud_test.gd` covers the actual Godot HUD separately.

1. Run `python3 tests/build_browser_runtime_probe.py` after patching `dist/index.js`. It verifies and extracts the exact mouse, move, touch, key and coordinate code, with source SHA-256. Only the recording wrapper adds a mock-sink callback.
2. Serve the project root over localhost, then open `/tests/browser_rotation_probe.html` in an ordinary browser. It uses no browser flags or impersonated user agent.
3. Enable 页面内横屏. Click left/right, up/down, all four diagonals, center, and the five attack targets. Drag across the top edge, and out of the pad toward an attack. Trusted pointer counts and exact-runtime counts should agree; all releases should clear held sets. The continuous pad uses v7 normalized .1/.5/.9 positions and .38/.62 thresholds.
4. Run the explicitly SYNTHETIC regression. Its 19 assertions cover diagonal updates without repeating held jump, crouch, neutral, pad ownership outside/re-entry, independent attack touch, shared direction counts, keyboard/touch aggregation, sentinel cancellation and all five attacks. These are constructed untrusted DOM events, not physical multi-touch.
5. Arm the SYNTHETIC cancel test, then click the real page-mode button. The production shell must release both touches and the key, and discard their stale move/end/repeat tails. The event log preserves the released sentinel coordinates.
6. Repeat at 390×844, 390×680, 320×568, and simulated 844×390 landscape. Test return/re-entry and unavailable system fullscreen. The 320×568 rotated fixture has a 568×267 canvas.

Unit checks: `node tests/rotated_input_test.cjs` (15 exact input-contract tests),
`node tests/fullscreen_ui_test.cjs` (30 shell mock tests), and
`node tests/browser_directional_fixture_test.cjs` (8 explicit mock-fixture tests).

The outer iframe simulates viewport changes. It does not impersonate an iPhone,
alter device settings, grant fullscreen permission, or execute Godot WASM.
Actual game WebGL rendering, fighter movement/air control, cooldown logic,
real iPhone Safari, hardware multi-touch, and safe-area cutouts must be tested
separately. Ordinary cloud Chrome's prior WebGL2 limitation is not bypassed.

Evidence lives under `exports/qa-v7/browser/`. Browser checks must be rerun after
changing shell code, exported callbacks, or the probe's tested behavior.
