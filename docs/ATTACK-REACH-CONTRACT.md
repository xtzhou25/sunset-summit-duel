# Measured punch reach contract

The three v4 punches use the actual imported final 57-clip GLB hand-surface measurements, not a guessed constant full-length hitbox. `CONSERVATIVE-ACTIVE-REACH-CURVES.json` is an exact copy of the measured source report from `animation/output/v5/CONSERVATIVE-ACTIVE-REACH-CURVES.json` in the animation-authoring project. Its SHA256 is `9a3820df05e8e8f046cc2547a83524f373b02458ab7e20aff372e8a77c65cdb4`.

## Provenance and attribution

The paired Jab, Straight and HeavyPunch clips are original game-specific keyframed additions, not newly captured motion. Existing source motion attribution is retained in `ANIMATION-ATTRIBUTION.txt`, including Open Motion Project / ACCAD, The Ohio State University, CC BY 3.0. Character geometry ownership is not changed by that motion license. These measurements make no new finger-rig, full-fist or collision-free-animation claim.

The approved animation contract identifies the measured runtime inputs:

- Lavender: `57a41e6c3ee31391359cc61e565f45cb8caed178424b79052de1bef037b494b6`
- YellowWhite: `5584f3b25c4120797a3e99630889aed7d48e32d42f5749cde20e145b417144ea`

Hand surfaces were measured on actual imported GLB skin at 120 Hz, then linearly interpolated to 10 ms report samples. Each sample conservatively takes the smaller of the paired R/L reaches. Distances are game metres at uniform model scale 1.2. Both world facings use the same conservative curve. The report excludes the 0.04 m contact allowance.

## Runtime and debug API

`Combat.effective_reach(fighter, attack_kind, attack_time = -1.0)` is the single shared calculation for contact checks and any renderer/debug reach display. Attack names are `punch`, `straight`, `heavy`, and unchanged `kick`.

- `attack_time` is absolute seconds since this attack started, not normalized animation time. The default negative value uses `fighter.clock`.
- The 70 compact curve samples in `combat.gd` exactly match the measured JSON. The runtime linearly interpolates adjacent 10 ms samples.
- Punch result: `min(configured_reach, interpolated_measured_reach + 0.04)`.
- Configured purple caps: jab 0.55 m, straight 0.60 m, heavy 0.63 m. Yellow caps: 0.59 / 0.64 / 0.67 m. A cap is not necessarily attained if the measured curve plus allowance remains lower.
- The result excludes the separate unchanged `HURT_X = 0.26` m defender half-width. Contact adds it once.
- Queries outside a curve clamp to its first/last sample. They do not activate a hitbox. Callers must still apply the existing startup/active/recovery gate and all other contact eligibility rules.
- Active windows remain jab [0.14, 0.24), straight [0.18, 0.28), heavy [0.34, 0.46). Authoring peaks are 0.19 / 0.23 / 0.40 seconds.
- Kick remains static at its original configured reach. Damage, timing, stun, knockback, two-hit cap and recovery protection are unchanged by this measurement update.

A retreating fighter can genuinely leave jab reach before extension. Guard fixtures therefore pin the defender at a wall when testing blocking rather than spacing. Immunity-expiry contact fixtures sample the actual jab extension peak rather than assuming maximum reach at active onset. Exact spatial boundary, interpolation, onset-versus-peak, and real 60 Hz long-range heavy checks live in `tests/punch_variation_test.gd`.
