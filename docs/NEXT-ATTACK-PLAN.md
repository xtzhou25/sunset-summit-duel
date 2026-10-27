# Next version: varied punches (not part of v3)

Authorized 2026-10-25 after the user requested additional attacks and varied consecutive punches. Root approved implementation controls: preserve immediate punch-on-press; a separate fresh second press during the last 120ms of the first punch recovery queues one rear straight, at most two punches. Holding never auto-repeats. Separate heavy action: L keyboard, mobile portrait four-action 2×2 grid (jump, punch, kick, heavy), short landscape and desktop compact four-action row, in the existing bottom region. Heavy anticipation is authored startup, not a hold-to-charge mechanic.

Sequence: finish v3 down/camera-facing continuity, native testing and freeze first. RC3 was published and verified separately. Do not combine unfinished batches or modify the live site before exact candidate approval. New attack work is a separate next-version branch/checkpoint.

Implemented timing, awaiting final native visual approval: existing jab duration .48/.52 for purple/yellow; rear straight .56/.60 with .18 startup/.10 active; heavy .88/.94 with .34 startup/.12 active. Active peaks must agree with actual hand reach. Keep paired R/L upper-body display, fixed actor roots and strike plane. No random recycling as a substitute for distinct actions. Heavy uses modest differentiated damage/knockback and ordinary reaction, not an endless knockdown chain. Preserve two-hit cap and punishable recovery. No new special/energy/network systems.

Before implementation: finalize measured animation timing/reach and damage/hitstun contract, then add actual UI/input/AI/tests. Any buffer cancels on pause/background/KO/rematch/character switch; no stale buffered input after recovery. Test both characters/facings, hit/block/miss, buffered second press vs hold/repeat, heavy startup interrupt/recovery and phone hit targets.

## Current verification

57-clip imported runtime candidates preserve all 51 accepted baseline clips; strict real-main-loop input/animation/feedback checks pass 361/361 and delayed-observation AI checks pass 16/16 before final measured-reach integration. Actual mesh reach curves now bound attack fronts over the active interval, with .04m effect allowance and conservative identical left/right collision ranges. Final regressions and native combat captures remain pending. Fullscreen v3.1 is a separate web-only candidate; it is not mixed into this branch yet.
