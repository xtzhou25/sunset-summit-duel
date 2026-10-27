# Qi v10 finite runtime regression

Result: pass; 180.016 seconds actual wall time, 10810 fixed native physics steps. All 6 ordered distinct-character pairs were selected through HUD callbacks, 30 seconds each. Runtime source and final assets unchanged throughout. Qi SHA-256 4076d5bfbabc683d32c76ffe95fef038ee5ea16bb77ee4738f36761a78fb3f68.

Completed 4 rounds; 0 natural result/rematches, 6 pause/resume cycles, 6 synthetic focus-loss/resume cycles, 6 menu/pair transitions. Each transition and final menu checks no remaining projectiles, views, depths, impact effects or visible rifles. Rifle actually spawned 5 projectiles and its state-bound prop was visible for 265 sampled physics steps. No failed assertions.

Audio player nodes remain exactly 10. One-second sampled maximum effects=1.0, projectiles=0.0, resources=323.0. Fixed model cache at most three characters; hidden rifle geometry is reused, not regenerated each shot. Resource and node counts include the additional third cached character and two reusable rifle props.

Warm 60–90s static-memory mean 88.760 MiB, late 150–180s 89.118 MiB. RSS means 141.021 → 141.603 MiB. Sampling arrays/dictionaries and allocator caching contribute to measured growth; this finite window does not prove absence of every leak.

This is actual native HEADLESS scene execution with scripted ordinary inputs and explicit lifecycle callbacks. It is NOT graphical rendering, garment inspection, browser/Safari/iPhone, hardware multitouch, GPU performance, or subjective listening acceptance. Existing dedicated Qi scene and actual runtime contract suites were rerun; see their logs for exact outcomes. No graphical or permission workarounds were used, and no gameplay changes were made.

Initial one-second smoke deliberately could not satisfy all-six-pairs/rifle-usage end conditions, so its logs are excluded from this finite final evidence. The completed final180s run, not that smoke, determines this report.
