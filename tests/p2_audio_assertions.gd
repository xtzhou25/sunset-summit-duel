extends RefCounted
## Audio-only bridge for legacy scene suites. P2 replaces one synthesized tone
## with a fixed pool of typed WAV cues; swing/jump/land cues are valid on misses.
## This helper never modifies combat, animation, hitstop or visual effects.
const CONTACT_CUES := ["hit_light", "hit_straight", "hit_heavy", "hit_kick", "block", "guard_break", "ko"]
const HIT_CUES := {"punch":"hit_light", "straight":"hit_straight", "heavy":"hit_heavy", "kick":"hit_kick", "roundhouse":"hit_kick", "meow":"hit_straight", "heart":"hit_straight"}

static func reset(game) -> void:
	# Give audio-only fixtures known gains while respecting the public mute state.
	game.audio_pool.configure(1.0, 1.0, 0.5, game.muted)
	game.audio_pool.unlock()
	game.audio_pool.suspend(false)
	clear_observation(game)

static func clear_observation(game) -> void:
	game.audio_pool.clear()
	game.audio_pool.played_log.clear()
	game.audio_pool.rejected_log.clear()

static func contact_matches(game, event: Dictionary) -> bool:
	var cue: String = "block" if event.type == "block" else ("guard_break" if event.type == "break" else HIT_CUES.get(str(event.get("kind", "")), ""))
	var matches := 0
	for record: Dictionary in game.audio_pool.played_log:
		if str(record.event_id) != str(event.get("event_id", "")) or record.cue != cue: continue
		matches += 1
		var voice := int(record.voice)
		var variant := int(record.variant) - 1
		if record.group != "combat" or voice < 0 or voice >= 6: return false
		var streams: Array = game.audio_pool.cue_streams.get(cue, [])
		if variant < 0 or variant >= streams.size(): return false
		var wav: AudioStreamWAV = streams[variant]
		var player: AudioStreamPlayer = game.audio_pool.players[voice]
		if wav == null or record.stream != wav.resource_path or not record.stream.begins_with("res://assets/audio/p2/"): return false
		if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED or wav.get_length() <= 0.0: return false
		if player.stream != wav or not player.playing or not is_equal_approx(player.pitch_scale, 1.0): return false
	return matches == 1 and game.audio_pool.players.size() == 10

static func no_contact_audio(game) -> bool:
	for record: Dictionary in game.audio_pool.played_log:
		if record.cue in CONTACT_CUES: return false
	return true

static func silent(game) -> bool:
	return game.audio_pool.played_log.is_empty() and game.audio_pool.diagnostics().active_count == 0
