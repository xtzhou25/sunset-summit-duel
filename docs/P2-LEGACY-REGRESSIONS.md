# P2 legacy regression migration

This pass preserves the existing real-main physics, input-edge, animation-clock,
damage, guard, invulnerability, knockdown, recovery, local-effect geometry and
camera/skin bounds assertions. It does not modify production scripts or assets.

## Intentional contract changes

- P2 replaces the single runtime-synthesized sine waveform with named, preloaded
  WAV cues in the fixed ten-player pool. Contact assertions now verify exactly
  one expected cue for the real event ID, its combat reservation, packaged stream,
  accepted variant, real player playback state and unchanged pitch.
- Misses may play their attack swing, jump and landing sounds. They still cannot
  play a hit, block, guard-break or KO cue, or create damage/hitstop/contact FX.
- Mute fixtures use the public toggle and initialize known pool gains. Checking
  a single legacy player is no longer enough to prove the entire pool is silent.
- The original meow asset is read from `audio_pool.cue_streams["meow"][0]`, since
  an idle pooled player need not retain a stream. All source hashes, 48 kHz mono
  duration/channel checks, fresh playback, mute and no-autoplay assertions remain.
- Heavy presentation hitstop changes from 85 ms to the approved P2 value, 95 ms
  (within the requested 85–110 ms range). No other timing expectation changed.

The initial legacy run had obsolete waveform/silent-whiff failures and a null
idle-meow-stream assertion. The signature fixture also directly changed the
game's mute field without updating the actual audio pool; its public-toggle
migration preserves the original fresh-meow playback check rather than removing
or weakening it.

## Reproduction

From the project root:

```sh
python3 tests/run_p2_regression_contracts.py
```

The runner creates separate writable XDG config/data/cache directories under
`/tmp` for each suite, runs strict paired-asset flags, retains complete logs in
`exports/qa-p2/final`, and writes `legacy-regressions.json` with commands, outcomes,
check counts, diagnostics and SHA-256 hashes of the source snapshot. Unexpected
script/runtime errors or source changes during the run fail the aggregate.

## Coverage

Final isolated run on 2026-10-25: all 11 suites and 1,801 assertions passed,
with zero failed suites and no source changes during the run. The recorded
production/test source hashes still matched at final handoff, including the
monotonic feedback watermark. Shutdown diagnostics are disclosed below.

| Suite | Checks |
|---|---:|
| Existing feedback, strict strong recoil | 153 |
| Punch feedback, strict paired assets | 429 |
| Roundhouse feedback, strict paired assets | 300 |
| Signature scene, strict paired assets and measured markers | 375 |
| Spacing scene and source-combined controls | 190 |
| Spacing weighted-skin bounds, 96 sampled poses | 6 |
| Signature weighted-skin bounds, 86 sampled poses | 12 |
| Legacy knockdown/recovery presentation and camera | 311 |
| Match/menu/pause/rematch integration | 11 |
| Camera viewport fixtures | 4 |
| Projectile visual ownership/reset | 10 |
| **Total** | **1,801** |

The strict roundhouse suite verifies 1,182 paired-pose samples with zero fallback.
The strict signature suite verifies 753 paired-pose and 12 independently measured
emitter samples with zero fallback. Damage, hitstop freezes, exact emitted
projectile origin, source hashes and all baseline clip-preservation checks remain.

The obsolete standalone P1 HUD inventory suites are intentionally not included;
P2 directional/settings UI suites are tested separately. The dedicated 72-case
P2 impact suite and audio-pool/event tests are also separate from this legacy
regression total. The runner does not edit the combat worker's tests.

## Limits and diagnostics

This is deterministic headless state/dispatch QA, not human listening, audio
hardware, rendered GPU, browser or real iPhone/Safari certification. Native
MovieWriter evidence is a separate P2 deliverable.

Some immediately exiting audio-enabled suites produce Godot shutdown warnings
about retained AudioStreamWAV/AudioStreamPlaybackWAV references. A verbose punch
run confirms these are audio playback resources; the original feedback baseline
also emitted this class of shutdown warning. The aggregate explicitly labels
these runs `pass_with_audio_shutdown_warnings` and retains every diagnostic,
rather than claiming a warning-free run or treating unrelated errors as benign.
Behavior assertions and process exit codes must still pass.
