extends SceneTree
## Real AudioStreamPlayer/AudioServer tests. Dummy driver is not auditory QA.
## Run: godot --headless --path . --script tests/combat_audio_test.gd
const CombatAudio = preload("res://scripts/combat_audio.gd")
var audio
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		printerr("FAIL: ", label)

func reset_pool() -> void:
	audio.clear()
	audio.suspend(false)
	audio.configure(1.0, 1.0, 1.0, false)
	audio.tick(1.0)

func asset_tests() -> void:
	check(audio.assets_ready and audio.missing_assets.is_empty(), "all 43 real WAV assets are preloaded")
	check(audio.players.size() == 10 and audio.get_child_count() == 10, "exactly ten players exist after initialization")
	check(audio.cue_streams.size() == 22, "twenty-two cue categories include original meow and rifle")
	var streams_ok := true
	var authored_lossless := true
	var authored_peak := 0.0
	var layout := {"combat": 0, "voice": 0, "ui": 0}
	for slot: Dictionary in audio.slots:
		layout[slot.group] += 1
	for cue: String in audio.cue_streams:
		var streams: Array = audio.cue_streams[cue]
		streams_ok = streams_ok and streams.size() == (1 if cue == "meow" else 2)
		for stream in streams:
			streams_ok = streams_ok and stream is AudioStreamWAV and stream.get_length() > 0.0 and stream.get_length() < 3.0 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED
			if cue != "meow" and stream is AudioStreamWAV:
				authored_lossless = authored_lossless and stream.format == AudioStreamWAV.FORMAT_16_BITS
				if stream.format == AudioStreamWAV.FORMAT_16_BITS:
					var pcm: PackedByteArray = stream.data
					for offset in range(0, pcm.size(), 2):
						authored_peak = maxf(authored_peak, absf(float(pcm.decode_s16(offset))) / 32768.0)
	check(streams_ok, "every cue references finite non-looping WAV variants, not synthetic placeholder tones")
	check(authored_lossless, "all forty-two authored variants preserve uncompressed PCM")
	check(authored_peak > 0.1 and authored_peak <= 0.299, "actual imported PCM peak satisfies the runtime mix bound")
	check(layout == {"combat": 6, "voice": 2, "ui": 2}, "six combat, two voice and two UI players are permanently reserved")
	var fixed_players := true
	for player: AudioStreamPlayer in audio.players:
		fixed_players = fixed_players and player.max_polyphony == 1 and is_equal_approx(player.pitch_scale, 1.0)
	check(fixed_players, "each fixed player has one voice and original playback pitch")

func gate_tests() -> void:
	check(not audio.is_unlocked and not audio.play_cue("hit_light", "locked-event"), "audio stays locked before first user gesture")
	check(audio.counts.locked == 1 and audio.played_log.is_empty(), "locked request is dropped, not dispatched")
	audio.unlock()
	check(audio.diagnostics().active_count == 0, "unlock never replays an old cue")
	check(not audio.play_cue("hit_light", "locked-event") and audio.counts.duplicate == 1, "a previously locked event cannot replay when repeated after unlock")
	check(audio.play_cue("hit_light", "fresh-after-unlock"), "new user-authorized cue starts on its real player")
	var log: Dictionary = audio.played_log.back()
	check(audio.players[log.voice].playing and audio.players[log.voice].stream != null, "accepted dispatch creates actual playback, not a timer placeholder")
	check(log.request_usec <= log.dispatched_usec and log.dispatch_latency_ms >= 0.0 and log.estimated_output_latency_ms >= 0.0, "dispatch records monotonic timestamps and technical AudioServer latency estimate")
	check(not audio.play_cue("meow", "bad-routing", "combat") and audio.counts.invalid_group == 1, "a caller cannot route meow into the combat pool")
	check(not audio.play_cue("missing", "unknown-cue") and audio.counts.unknown_cue == 1, "unknown cue rejects cleanly")
	check(not audio.play_cue("hit_light", "") and audio.counts.invalid_event == 1, "empty dedup identifier rejects cleanly")

func dedup_and_variant_tests() -> void:
	reset_pool()
	check(audio.play_cue("hit_straight", "variant-a"), "first straight hit starts")
	var first_variant := int(audio.played_log.back().variant)
	check(not audio.play_cue("hit_straight", "variant-a"), "identical cue and event identifier deduplicates")
	check(not audio.play_cue("hit_straight", "variant-b"), "different event during same-cue cooldown drops immediately")
	audio.tick(0.030)
	check(audio.play_cue("hit_straight", "variant-c"), "next event after short presentation-time cooldown starts")
	check(int(audio.played_log.back().variant) == 3 - first_variant, "only accepted playback deterministically advances variant cycling")
	audio.tick(0.030)
	check(not audio.play_cue("hit_straight", "variant-cap") and audio.counts.cue_cap >= 1, "same straight-hit cue has a two-voice cap")
	audio.clear()
	audio.tick(0.030)
	check(audio.play_cue("hit_straight", "variant-d") and int(audio.played_log.back().variant) == first_variant, "variant cycle is stable across clears without random pitch")
	reset_pool()
	for i in range(3):
		check(audio.play_cue("hit_light", "light-cap-%d" % i), "light hit accepts bounded overlap %d" % (i + 1))
		audio.tick(0.020)
	check(not audio.play_cue("hit_light", "light-cap-overflow"), "light-hit cap is exactly three, not unlimited polyphony")
	check(not audio.play_cue("hit_straight", "variant-b"), "a cooldown-dropped event is consumed rather than replayed later")

func reservation_and_pressure_tests() -> void:
	reset_pool()
	for cue in ["swing_punch", "swing_kick", "jump", "land", "block", "hit_light"]:
		check(audio.play_cue(cue, "pressure-" + cue), "combat reservation accepts " + cue)
	check(audio.play_cue("meow", "pressure-voice-1"), "first original meow starts even with full combat pool")
	audio.tick(0.100)
	check(audio.play_cue("meow", "pressure-voice-2"), "second meow overlaps on separate reserved player")
	check(audio.play_cue("ui_confirm", "pressure-ui-1"), "UI uses its own reservation under combat and voice pressure")
	audio.tick(0.070)
	check(audio.play_cue("ui_confirm", "pressure-ui-2"), "second UI voice fills last fixed slot")
	var snapshot: Dictionary = audio.diagnostics()
	check(snapshot.active_count == 10 and snapshot.active_groups == {"combat": 6, "voice": 2, "ui": 2}, "all ten fixed voices can coexist with no player growth")
	var voice_ids := [audio.slots[6].event_id, audio.slots[7].event_id]
	var voice_streams := [audio.players[6].stream, audio.players[7].stream]
	check(audio.play_cue("ko", "pressure-ko"), "high-priority KO preempts a lower-priority combat voice")
	check(audio.counts.preempted >= 1 and audio.diagnostics().active_count == 10, "priority replacement does not allocate another player")
	check(voice_ids == [audio.slots[6].event_id, audio.slots[7].event_id] and voice_streams == [audio.players[6].stream, audio.players[7].stream], "combat pressure and KO never interrupt either original meow")
	check(not audio.play_cue("swing_punch", "pressure-low-priority") and audio.counts.pool_full >= 1, "low-priority effect drops rather than displacing important sounds")
	audio.tick(0.100)
	check(not audio.play_cue("meow", "pressure-voice-overflow"), "third meow drops without cutting off the first two")
	check(audio.players[6].stream.resource_path == "res://assets/audio/meow.wav" and audio.players[7].pitch_scale == 1.0, "original meow resource, pitch and speed are preserved")
	check(audio.players.size() == 10 and audio.get_child_count() == 10, "pressure never creates additional AudioStreamPlayer objects")

func gain_tests() -> void:
	audio.configure(0.5, 0.25, 0.75, false)
	var expected_combat := float(CombatAudio.CUE_GAINS[audio.slots[0].cue]) * 0.5
	check(is_equal_approx(audio.players[0].volume_linear, expected_combat) and is_equal_approx(audio.players[6].volume_linear, 0.0275) and is_equal_approx(audio.players[8].volume_linear, 0.09), "combat, voice and UI gains independently affect existing players")
	check(CombatAudio.CUE_GAINS.swing_punch < CombatAudio.CUE_GAINS.hit_light and CombatAudio.CUE_GAINS.hit_light < CombatAudio.CUE_GAINS.hit_heavy, "swing, light-hit and heavy-hit gains preserve intended impact hierarchy")
	audio.configure(99.0, -2.0, NAN, false)
	check(audio.group_gains == {"combat": 1.0, "voice": 0.0, "ui": 0.0}, "out-of-range and non-finite gains clamp safely")
	audio.configure(1.0, 1.0, 1.0, false)
	var peak_bound := 6.0 * 0.299 * 0.24 + 2.0 * 0.795 * 0.11 + 2.0 * 0.299 * 0.12
	check(peak_bound < 0.679 and linear_to_db(peak_bound) < -3.3, "asset peak contract plus group caps leaves more than 3.3 dB worst-case headroom")
	audio.configure(0.0, 1.0, 1.0, false)
	check(not audio.play_cue("hit_heavy", "zero-gain-drop"), "zero combat gain consumes and drops new combat events")
	audio.configure(1.0, 1.0, 1.0, false)
	check(not audio.play_cue("hit_heavy", "zero-gain-drop"), "raising a slider cannot replay its previously dropped event")

func suspension_tests() -> void:
	reset_pool()
	check(audio.play_cue("meow", "suspend-running") and audio.play_cue("hit_heavy", "suspend-running"), "voice and effect can share an event ID because dedup is cue-specific")
	audio.suspend(true)
	check(audio.diagnostics().active_count == 0 and audio.diagnostics().queued_count == 0, "pause immediately stops every pool and has no queued replay")
	check(not audio.play_cue("hit_heavy", "suspend-dropped"), "events while suspended are rejected")
	audio.suspend(false)
	audio.tick(5.0)
	check(audio.diagnostics().active_count == 0 and not audio.play_cue("hit_heavy", "suspend-dropped"), "resume does not replay suspended events even after long elapsed time")
	check(not audio.play_cue("meow", "suspend-running"), "interrupted event stays consumed across clear and resume")
	check(audio.play_cue("meow", "resume-fresh"), "a fresh event can play after resume")
	audio.configure(1.0, 1.0, 1.0, true)
	check(audio.diagnostics().active_count == 0, "master mute stops existing original voice immediately")
	check(not audio.play_cue("ui_confirm", "mute-dropped"), "master mute suppresses UI as well as combat and voice")
	audio.configure(1.0, 1.0, 1.0, false)
	audio.tick(5.0)
	check(audio.diagnostics().active_count == 0 and not audio.play_cue("ui_confirm", "mute-dropped"), "unmute has no stale UI replay")
	check(audio.play_cue("hit_kick", "background-fresh"), "fresh impact plays before backgrounding")
	audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(audio.is_suspended and audio.diagnostics().active_count == 0, "focus loss is a fail-safe stop and suspend")
	audio.suspend(false)
	check(audio.play_cue("hit_kick", "background-pause-fresh"), "explicit resume permits only new cues")
	audio._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(audio.is_suspended and audio.diagnostics().active_count == 0, "application background suspend stops and clears every player")
	var clean := true
	for player: AudioStreamPlayer in audio.players:
		clean = clean and not player.playing and player.stream == null
	check(clean, "cleared players retain no active stream that could resume later")

func bounded_history_tests() -> void:
	reset_pool()
	audio.configure(1.0, 1.0, 1.0, true)
	for i in range(5000):
		audio.play_cue("hit_light", "bounded-muted-%d" % i)
	var snapshot: Dictionary = audio.diagnostics()
	check(snapshot.seen_event_count == 256 and snapshot.rejected_log.size() == 64 and snapshot.queued_count == 0, "five thousand muted inputs retain only bounded history and diagnostic logs")
	audio.configure(1.0, 1.0, 1.0, false)
	for i in range(200):
		audio.clear()
		audio.tick(0.100)
		audio.play_cue("ui_confirm", "bounded-accepted-%d" % i)
	snapshot = audio.diagnostics()
	check(snapshot.played_log.size() == 64 and snapshot.seen_event_count == 256, "accepted-playback log is independently bounded at sixty-four entries")
	check(audio.players.size() == 10 and audio.get_child_count() == 10 and snapshot.counts.peak_active <= 10, "long repeated input creates no extra audio nodes or polyphony")

func clock_test() -> void:
	reset_pool()
	audio.play_cue("meow", "clock-probe")
	var index := int(audio.played_log.back().voice)
	var previous := 0.0
	var monotonic := true
	for i in range(5):
		await create_timer(0.020).timeout
		audio.tick(0.020)
		var current: float = audio.playback_clock(index)
		monotonic = monotonic and current >= previous and is_finite(current)
		previous = current
	check(monotonic, "technical AudioServer playback clock never moves backwards while active")
	print("AUDIO_DRIVER=", AudioServer.get_driver_name(), " PLAYHEAD_SECONDS=", previous, " OUTPUT_LATENCY_MS=", audio.diagnostics().output_latency_ms)

func decoded_meow_peak_test() -> void:
	# The original imported voice uses QOA, so verify its decoded peak rather
	# than assuming the source PCM peak survives lossy import exactly.
	reset_pool()
	var bus_index := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus_index, "CombatAudioP2PeakProbe")
	AudioServer.set_bus_volume_db(bus_index, -80.0)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(bus_index, capture)
	var voice: AudioStreamPlayer = audio.players[6]
	voice.bus = "CombatAudioP2PeakProbe"
	audio.play_cue("meow", "decoded-peak-probe")
	voice.volume_linear = 1.0
	await create_timer(0.700).timeout
	var buffer := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample: Vector2 in buffer:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	check(buffer.size() > 16000 and peak > 0.5, "test-only software capture observes actual decoded original meow, not silent Dummy output")
	check(peak <= 0.795, "decoded original QOA meow remains within reviewed 0.795 peak bound")
	print("DECODED_MEOW_PEAK=", peak, " CAPTURED_FRAMES=", buffer.size())
	audio.clear()
	voice.bus = "Master"
	AudioServer.remove_bus(bus_index)

func run_tests() -> void:
	audio = CombatAudio.new()
	root.add_child(audio)
	asset_tests()
	if not audio.assets_ready:
		printerr("Missing assets: ", audio.missing_assets)
		audio.free()
		quit(1)
		return
	gate_tests()
	dedup_and_variant_tests()
	reservation_and_pressure_tests()
	gain_tests()
	suspension_tests()
	bounded_history_tests()
	await clock_test()
	await decoded_meow_peak_test()
	audio.clear()
	# Let the real audio thread release the final stopped playback before exit.
	await create_timer(0.100).timeout
	audio.free()
	print("COMBAT_AUDIO_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
