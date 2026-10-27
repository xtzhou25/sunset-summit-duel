# P6 livehouse art (original geometry, no external license additions)

Plan authority: `combat_plan/P5-P7_执行契约.txt`, 2026-10-26. P6 remains isolated until P5 passes.

## Integration contract
- Load `res://stage-art/expanded_livehouse.gd` instead of `res://scripts/stage.gd` when P5 is accepted. The former subclasses the latter, retaining signage, equipment, contact shadows and original light setup.
- Keep the instance and call `stage.update_view(camera, viewport_height * hud.gameplay_height_ratio(), reduced_motion)` after every camera/layout update.
- Set `stage.motion_active = false` during pause/background/inactive-menu states and true during play. This freezes both original and new decorative animation without modifying combat.
- `reduced_motion=true` freezes all decorative motion. If mapped to the existing shake preference, document that it also reduces background motion; do not introduce an unsaved setting.
- Floor spans ±12, remote shell ±15. For camera safety require `abs(camera.x)+camera.size/2 <= 12` (floor) and `abs(camera.x*0.75)+camera.size/2 <= 15` (far shell). If camera needs more, widen static surfaces, never move the floor with the camera.
- Far compensation=0.25×cameraX; acoustic/sign=0.12×cameraX; equipment/floor=0. Audience scroll=1.12×projected world motion.
- Foreground uses one CanvasLayer(0), one input-transparent clipped Control; HUD stays layer1. 28 fans, 72 curtain folds in one MultiMesh. No new lights, physics bodies or textures. No per-frame node creation.

## Verification
`HOME=/tmp/stage-art-home XDG_DATA_HOME=/tmp/stage-art-home XDG_CACHE_HOME=/tmp/stage-art-home godot --headless --path . --script res://stage-art/art_contract_test.gd`

This verifies 4 viewport sizes × 3 camera positions, clipping bounds, parallax transform, input transparency, bounded nodes over 600 ticks, pause and reduced-motion freeze. Headless tests are NOT rendered visual QA.

### Native screenshot/recording cases for integration engineer
- 1280×800 center, both near left, both near right; same fighters/static simulation to compare parallax while camera translates.
- 844×390 short landscape center and both ends: thin crowd must fit below feet and above joystick/buttons, cake warning clear.
- 390×844 and 375×667 portrait, both ends with 哈 cake and 桃 projectile; no empty background edge, HUD legible.
- Same camera/fighters at art clock0/2s: subtle fan motion/no flashes; reduced-motion or paused frames remain identical in art layers.
- Verify original Chinese/English venue sign and all five character identities remain unchanged.

Expected limitation: very short landscape has only about 19px audience band. Fans intentionally shrink there instead of covering fighters or controls. Tune only after viewing native frames.
