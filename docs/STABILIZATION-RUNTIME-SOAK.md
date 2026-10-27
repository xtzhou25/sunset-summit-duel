# v11 180-second native stability check

PASS: 180.019 actual wall seconds; 10580 physics steps. All six ordered distinct-character pairings covered by ordinary HUD callbacks. Runtime source and Qi/rifle assets unchanged throughout; exact SHA-256 values in SUMMARY.json.

6 rounds, 0 natural full-match restarts, 6 pause/resume cycles, 6 synthetic focus-out/resume cycles, 6 menu/pair transitions. All transitions and final menu confirm zero projectile/view/depth/effect residues and hidden rifles. 4 actual rifle projectiles emitted, with 240 physics steps of correctly state-bound rifle visibility.

Audio player nodes stay exactly 10; model cache checked every frame for at most 3 characters. One-second sampled resource maximum 323.0; effect maximum 2.0. Feedback and audio histories remain within declared caps. No functional assertion failures.

Warm 60–90s static-memory mean 88.142 MiB; late 150–180s 89.153 MiB. RSS means 140.064 → 141.378 MiB. These include test sampling dictionaries/arrays and allocator caching. This finite test is not proof of zero leaks and does not compare startup against steady state.

Actual HEADLESS native scene execution only. It is not graphical garment inspection, browser/iPhone/Safari verification, hardware multitouch, GPU performance or subjective audio acceptance. Physics timing telemetry is not rendered FPS. No production code or graphical/permission routes were used. Separate native graphical review belongs to the main engineering task.
