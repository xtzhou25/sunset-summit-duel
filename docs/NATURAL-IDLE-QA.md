# Natural combat idle v16 / RC17

User request: replace rigid standing with open-licensed skeletal motion.

## Change boundary

Five roles 因 / 鱼 / 七 / 桃 / 哈; only `FightIdle`, `FightIdle_R`, `FightIdle_L` tracks change. Functional asset comparison against verified RC16 changes exactly five GLBs: `assets/{purple,yellow,qi,tao,ha}.glb`. A delivery-only `export_presets.cfg` adjustment excludes three unused measurement JSONs from the web pack; their source files remain intact. All gameplay, attack/hit timings, damage, input/joystick, camera and skills remain byte-identical. GLB preservation proof retains original geometry, nodes, skin, materials and all non-idle animations, including the recent shin-strip removal and Ha glasses.

## Real open-motion provenance

ACCAD / Ohio State Open Motion Project, Male2_E8_Bounce.bvh, frames30–210, CC BY3.0. Included source capture and official-page evidence, provenance, `OPEN-MOTION-LICENSE.txt`. Real measured joint trajectories are retargeted; foot IK, reduced amplitudes, smoothing and loop correction adapt capture for combat. Handguard pickup/settle is authored and explicitly distinguished from capture. Source overlay Library identity: `[private-archive-reference-omitted]`, v1. The five editable Blender files are imported runtime rigs, not original Rigify control rigs. Old original modeling sources remain rollback history.

## Diagnosis and fix

Baseline loops worked: all10 role/facing cases advanced480/480 frames, four2s wraps over8s, root/feet stationary. Old head/hands/spine moved almost rigidly by only1.39–2.45cm. No runtime freeze/reset defect; runtime code unchanged.

New6s loops articulate hips, torso, head and arms with soles planted. Initial candidate raised the guard at phase0 and broke original landing/recovery settle contract by9.2cm. This was rejected before publication. Final0.8s quintic pickup/settle restores original entry/exit poses; no other animation changed.

## Verified numerical/runtime results

- Final10 role/facing idle cases: continuous advance, correct6s loops, actor root and footbone origins stationary, pause exact.
-100 first-tick jab/hit checks across5idle phases ×5roles ×2facings: immediate correct clip, return to idle, no added response delay.
-20 ordered pairs load.
-30 landing/recovery settle cases acrossall5roles ×2facings ×3clips: pass1mm contract; worst0.284mm.
-Existing presentation suite311checks/0failures after fix.
-Original broad regression39suites:36passed firstcandidate; directional_hud and signature_hud are baseline-equivalent obsolete D-pad expectations (238assertions and removed `left` dictionary key). The third failure was initial idle settle and passes on final. Joystick/combat/skill regression passes; Ha HUD1109checks/0failures.
-Weighted sole vertices are stationary to floatingpoint precision; mesh loop seam0. Footbone constraints do not mean calf/boot uppervertices never move.

## Native rendered evidence

Actual Godot4.6.3 llvmpipe/OpenGL game-camera frames:600baseline +600final, five roles/bothfacings/sixseconds at10fps. Fullcamera before/after60s video plus provisional magnified preview. Exact native SubViewport phone layouts568×267 and375×614:12captures including menus andall5roles, dimensions match. These are desktop native render fixtures, not physical-device/browser certification.

Native transitions: 350 valid captures of jab/hit/crouch/backstepguard/run/sideflip/jump, bothfacings/allfive; recovery separately verified. Final bounded native graphical soak passes:180.036749wall seconds,4247 renderedframes,10783physicsticks,20orderedpairs,6pause/6focuscallbacks, rifle7/peach2/cake3emissions, zeroerrors. Detailed reports are packaged with QA. Frame steps/render fixtures are not performance benchmarks. Scripted focus callbacks are not OS switch tests. No iOS, hosted-browser, low-power, or audible audio certification is claimed.

## Preservation and deployment

Existing verified Godot4.6.3 engine retained; only PCK rebuilt and credits/license added. Audience must remain owner-private. Native deployment success is distinct from hosted-byte verification; previous hosted byte probes were401 and no unsupported retry path is used.

## Delivery-only pack optimization

The initial verified web PCK was21,476,212bytes. Native source push twice failed with server `artifacts_git_receive_pack_failed`; a20MiB limit is only an unconfirmed hypothesis. To reduce transport size without changing motion or gameplay, the web export excludes only `qi_surface_curves.json`, `tao_surface_curves.json`, `ha_surface_curves.json`, which are offline measurement evidence and not loaded by runtime. Source/Library retain allthree. Exact pack-entry comparison and cold packed-runtime results are included in QA. RC17 Library v1 supersedes v0 only for this delivery optimization; runtime GLBs remain byte-identical.

Final delivery PCK13,595,372bytes, SHA256`e329b08415c8ef545c99b451403c6b39c58bcad0ab9bfd59eaf1ba31ed305203`. Exactly3JSON entries removed; all106retained payloads byte-identical including original UIDcache. Cold isolated `--main-pack`20pairs/idlewraps/all5signatureclips+projectileemissions/markercontracts pass with0errors.
