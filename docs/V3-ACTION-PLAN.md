# V3 action quality plan

Scope: camera-facing three-quarter combat presentation and a full responsive knockdown/recovery cycle. Live v2 remains frozen until an exact candidate is approved. Do not change damage, attack distance, cooldowns, stage, fixed-camera rules or access permissions without a demonstrated need.

## Findings
V2 only selected Knockdown after lethal KO; Recover had no gameplay path. Heavy nonlethal kicks therefore could never show a complete fall/rise response. The result delay also stopped simulation entirely, preventing an airborne KO from physically settling if a future down state were introduced.

## State contract
Unblocked flying kick: impact → airborne loss if above floor → grounded loss/catch → supported settled hold → brace/rise → FightIdle. Normal punch stays short HitReactStrong. Knockdown is .80s with airborne-safe loss ending .20; air hit holds that pose until real ground contact, then continues at .20. Grounded hit starts at0. Hold .25s, Recover1.00s, protection after rise .35s. Down/rise cannot attack, guard, jump or receive additional damage; stale held actions must be released before a new wake-up action. KO settles and holds, never recovers. Timeout preserves HP results but finishes already-started recovery safely. Pause freezes all of this; rematch resets it.

## Presentation contract
Actor root remains face ×90° around Y, uniform model scale1.2 and physical Z=0. Camera stays fixed. Paired _R/_L clips open chest/shoulders and head toward camera, while feet and strike peaks remain aligned toward the opponent. No runtime torso twist is layered over baked variants. Foot planting, reach, garment clearance, both directions and camera containment are measured against actual imported meshes. Preserve all21 prior clips and v2 rollback sources.

## Acceptance
- Complete normal-input state tests for both characters and both directions, including air/wall/cross-up, KO and double KO, timeout while down, pause/background, repeated inputs and rematch.
- Actual native longer gameplay captures using the real AI and normal control commands, without teleporting fighters, replacing AI, changing HP, or injecting combat-state fixtures. Separate deterministic state fixtures remain valid for edge QA and are labelled accordingly.
- Inspect idle→movement→attack, impact→loss→catch→hold→rise→ready transitions. No result overlay before settle, no root/visual displacement hiding offstage models.
- Run existing combat, input, HUD, camera and full-match regressions; update only intentional kick-down expectations.
- Persist exact source/web/QA candidate and verify downloaded SHA256/CRC; publish only after candidate approval. Browser/mobile/audio LIMITED-QA remains until genuinely tested.

## Earlier implementation checkpoint (2026-10-25, superseded below)
- Recoverable-down simulation and render clocks implemented; 211 dedicated knockdown assertions pass, including release-during-recovery and first-ready-frame input.
- Both 40-second normal-control / original-AI simulations naturally cover facing changes, recovery and KO followed by the next round. Purple trace ends at 0–1 rounds, yellow at 1–0. These traces are not yet visual approval: working runtime assets still use the frozen v2 poses.
- Early three-quarter stance and punch visual probes approved; final compact hand/knee catch and rise still undergoing garment/planting QA. No final v3 runtime asset or candidate is declared ready.
- Candidate packager now requires explicit new candidate and QA directory, and refuses to overwrite an existing frozen candidate/archive. RC1 and RC2 are retained unchanged.

## Final bounded acceptance (2026-10-25)
Candidate3 assets (51 clips each) passed the frozen309presentation and153feedback suites. Both40-second actual native original-AI gameplay captures completed with facing changes, normal down/rise and KO/next-round sequences; eight native layout fixtures cover both characters at both walls across four viewports. The visible yellow shoulder gap discovered during candidate2 playback is fixed in candidate3 at the identical game frame. Purple direct brace/release is accepted; concealed local cape contacts remain documented rather than labeled collision-free. No further visual redesign is required.

Godot source, static web and final QA are being frozen as RC3 with exact manifest, Library roundtrip SHA/CRC and clean-import validation before publication approval. RC2 remains the live rollback baseline. Next-version varied punches are separately planned, not implemented in this candidate.
