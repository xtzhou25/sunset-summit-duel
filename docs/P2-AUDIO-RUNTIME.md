# P2 bounded combat audio runtime

`scripts/combat_audio.gd` owns exactly ten reusable `AudioStreamPlayer` nodes:
six combat, two reserved voice, and two UI. Every player has `max_polyphony=1`.
No background music, procedural beeps, delayed playback queue, playback timers,
per-frame player creation, pitch changes, or global AudioServer bus changes exist.

## Integration API

- Add the node to the scene tree before using its players. `_ready()` loads all
  29 WAV files once. Missing resources are reported in `missing_assets` and
  `diagnostics().assets_ready`; cue dispatch never loads a resource.
- `configure(combat_gain, voice_gain, ui_gain, muted)` accepts linear 0..1 user
  values, safely clamps malformed values, and updates existing voices. Master
  mute immediately stops and clears all players. The owner persists settings.
- `unlock()` must be called from an actual user gesture. It does not itself play
  a cue or claim the browser granted audio permission.
- `play_cue(cue, event_id, group="") -> bool` dispatches or drops immediately.
  Cue groups are authoritative: a caller cannot reroute voice into combat.
- `tick(delta)` belongs to presentation time and must continue outside hitstop.
  Cooldown time also accounts for monotonic wall time after backgrounding.
- `suspend(true)` stops and clears all players. `suspend(false)` permits only new
  events; it does not replay anything. Call it on pause, focus loss, and resume.
  Focus loss and application suspension also have an internal fail-safe stop.
- `clear()` stops all players and clears their stream references and cooldowns.
  It intentionally keeps the bounded consumed-event history, so interrupted
  events cannot replay immediately when a stale batch is resubmitted.
- `players[0..5]` are combat, `players[6..7]` voice, and `players[8..9]` UI. Legacy
  test aliases may reference these players; no additional players are needed.

## Event identity and priority

Deduplication uses cue plus event identifier. The caller should supply a unique
round/attack/target/event key, at most 240 characters. Up to 256 consumed keys are
retained in a fixed ring. Events rejected due to lock, mute, suspension, cooldown,
or pool pressure are consumed, not deferred. The bounded ring is not permanent
storage; the owner must not resubmit an arbitrarily old event batch.

Same-cue limits are two, except light-hit overlap may use three. Cooldowns range
from 18 to 100 ms. Variants cycle 1, 2, 1, 2 only on accepted dispatch; no random
pitch or speed is applied. A strictly higher-priority combat cue can replace the
oldest lowest-priority combat sound. Equal/lower priority drops. Meows cannot be
stolen by combat or UI, and a third meow drops rather than truncating either one.

## Gain and clipping bound

Maximum per-player gains are combat 0.24, voice 0.11, UI 0.12, multiplied by the
user's group sliders. Authored PCM peaks are at most 0.299 linear; unchanged
original `assets/audio/meow.wav` peaks at approximately 0.794739. Therefore even
all ten voices at phase-aligned individual peaks are bounded by:

`6 × .299 × .24 + 2 × .795 × .11 + 2 × .299 × .12 = .67722`

This leaves more than 3.3 dB headroom before the untouched Master bus. No limiter
or compression changes the original meow. This mathematical bound requires the
reviewed PCM files and gain caps to remain unchanged. External system gain,
effects added later, or another unrelated audio source are outside this bound.

The original meow import remains QOA and unchanged. The focused test also
captures its actual Godot-decoded software output at unity on a temporary owned
test bus: measured peak 0.793619275 over 32,768 captured frames, below the 0.795
bound. New authored P2 imports use uncompressed PCM so their reviewed source
peak budget is preserved. This software decode check is not a listening test.

Cue-relative gains further soften movement and swings: punch swing .12, kick
swing .14, light hit .20, straight hit .22, heavy hit .24, kick hit .23, block .18,
guard break .22, jump .10, land .12, down-land .20, KO .22, heart emission .14,
UI .12, original meow .11. All values are absolute per-player linear gains before
the user slider. This establishes contrast without changing the original voice.

## Diagnostics and verification limits

`diagnostics()` returns fixed player/active group counts, finite request/drop
counters, a maximum 64-entry accepted log, a maximum 64-entry rejected log,
bounded event-history size, asset status, and technical driver/latency data.
Accepted entries include the cue, event, group, player, deterministic variant,
resource path, linear gain, monotonic request/dispatch timestamps, dispatch
latency, and AudioServer's mix/output latency estimate.

`playback_clock(index)` uses the real player's playback position plus time since
the last audio mix minus output latency, clamped monotonically for that active
voice. It is not the combat clock. The estimate is not an end-to-end audible
latency measurement, especially with the headless Dummy driver. Web sample
playback is requested, subject to actual platform support and gesture unlock.
Native/Dummy drivers use regular stream playback instead of requesting an
unsupported sample path; Web uses sample playback.

Run `godot --headless --path . --script tests/combat_audio_test.gd`. The tests
inspect real imported WAV resources, actual AudioStreamPlayer dispatch, overlap,
reservations, priorities, cue caps, deduplication, deterministic variants, all
stop/resume paths, independent gains, bounded memory, and technical clocks.
Headless/Dummy checks cannot establish subjective sound quality, speaker output,
iPhone/Safari unlock behavior, or hardware end-to-end latency.
