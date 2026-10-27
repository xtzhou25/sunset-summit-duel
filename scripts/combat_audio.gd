extends Node
## Fixed-capacity, presentation-only combat audio. Call unlock() in a real user
## input callback, tick() outside hitstop, and suspend(false) only on resume.
## No timers, replay queue, runtime synthesis, pitch randomization, or bus edits.

const PLAYER_LIMIT := 10
const EVENT_HISTORY_LIMIT := 256
const LOG_LIMIT := 64
const EVENT_ID_LIMIT := 240
const GROUP_LAYOUT := ["combat", "combat", "combat", "combat", "combat", "combat", "voice", "voice", "ui", "ui"]
## Multiplied by the user's 0..1 sliders. Authored WAV peaks <= 0.299; original
## meow peak <= 0.795. All ten voices together have a peak bound below 0.679.
const GROUP_GAIN_CAPS := {"combat": 0.24, "voice": 0.11, "ui": 0.12}
const CUE_GAINS := {
	"cake_land": 0.21,
	"cake_drop": 0.12,
	"cake_warn": 0.12,
	"peach_hit": 0.19,
	"peach_emit": 0.14,
	"heart_hit": 0.17,
	"swing_punch": 0.12, "swing_kick": 0.14, "hit_light": 0.20,
	"hit_straight": 0.22, "hit_heavy": 0.24, "hit_kick": 0.23,
	"block": 0.18, "guard_break": 0.22, "jump": 0.10, "land": 0.12,
	"down_land": 0.20, "ko": 0.22, "heart_emit": 0.14,
	"ui_confirm": 0.12, "meow": 0.11, "rifle_emit":0.17,
}
const REFINED_CUES := ["rifle_emit", "heart_hit", "peach_emit", "peach_hit", "cake_warn", "cake_drop", "cake_land"]
const CUE_SPECS := {
	"cake_land": {"group":"combat","cap":2,"cooldown":0.08,"priority":70},
	"cake_drop": {"group":"combat","cap":2,"cooldown":0.12,"priority":40},
	"cake_warn": {"group":"combat","cap":2,"cooldown":0.12,"priority":45},
	"peach_hit": {"group":"combat","cap":2,"cooldown":0.06,"priority":60},
	"peach_emit": {"group":"combat","cap":2,"cooldown":0.08,"priority":55},
	"heart_hit": {"group":"combat","cap":2,"cooldown":0.06,"priority":60},
	"rifle_emit": {"group":"combat","cap":2,"cooldown":0.08,"priority":60},
	"swing_punch": {"group": "combat", "cap": 2, "cooldown": 0.025, "priority": 10},
	"swing_kick": {"group": "combat", "cap": 2, "cooldown": 0.025, "priority": 12},
	"hit_light": {"group": "combat", "cap": 3, "cooldown": 0.018, "priority": 50},
	"hit_straight": {"group": "combat", "cap": 2, "cooldown": 0.025, "priority": 60},
	"hit_heavy": {"group": "combat", "cap": 2, "cooldown": 0.035, "priority": 70},
	"hit_kick": {"group": "combat", "cap": 2, "cooldown": 0.035, "priority": 70},
	"block": {"group": "combat", "cap": 2, "cooldown": 0.025, "priority": 40},
	"guard_break": {"group": "combat", "cap": 2, "cooldown": 0.050, "priority": 80},
	"jump": {"group": "combat", "cap": 2, "cooldown": 0.030, "priority": 15},
	"land": {"group": "combat", "cap": 2, "cooldown": 0.030, "priority": 20},
	"down_land": {"group": "combat", "cap": 2, "cooldown": 0.045, "priority": 65},
	"ko": {"group": "combat", "cap": 2, "cooldown": 0.100, "priority": 95},
	"heart_emit": {"group": "combat", "cap": 2, "cooldown": 0.040, "priority": 55},
	"ui_confirm": {"group": "ui", "cap": 2, "cooldown": 0.060, "priority": 50},
	"meow": {"group": "voice", "cap": 2, "cooldown": 0.090, "priority": 100},
}

var players: Array[AudioStreamPlayer] = []
var slots: Array[Dictionary] = []
var cue_streams: Dictionary = {}
var missing_assets: PackedStringArray = []
var group_gains := {"combat": 1.0, "voice": 1.0, "ui": 1.0}
var master_muted := false
var is_unlocked := false
var is_suspended := false
var assets_ready := false
var played_log: Array[Dictionary] = []
var rejected_log: Array[Dictionary] = []
var counts := {
	"requested": 0, "played": 0, "rejected": 0, "preempted": 0,
	"duplicate": 0, "cooldown": 0, "cue_cap": 0, "pool_full": 0,
	"locked": 0, "muted": 0, "suspended": 0, "unknown_cue": 0,
	"invalid_group": 0, "missing_asset": 0, "invalid_event": 0,
	"not_ready": 0, "cleared": 0, "peak_active": 0,
}

var _initialized := false
var _start_usec := Time.get_ticks_usec()
var _clock_seconds := 0.0
var _last_played: Dictionary = {}
var _variant_next: Dictionary = {}
var _seen: Dictionary = {}
var _event_ring: Array[String] = []
var _event_cursor := 0
var _sequence := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_initialize_once()

func _initialize_once() -> void:
	if _initialized:
		return
	_initialized = true
	_event_ring.resize(EVENT_HISTORY_LIMIT)
	for index in range(PLAYER_LIMIT):
		var player := AudioStreamPlayer.new()
		player.name = "CombatAudio%d" % index
		player.max_polyphony = 1
		player.pitch_scale = 1.0
		player.bus = "Master"
		# Web sample playback avoids the mixed-stream latency of the compatibility
		# renderer; all bookkeeping still uses the real player/server clocks.
		player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if OS.has_feature("web") else AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		players.append(player)
		slots.append({"group": GROUP_LAYOUT[index], "active": false,
			"cue": "", "event_id": "", "priority": -1, "sequence": -1,
			"started_usec": 0, "playhead": 0.0})
	for cue: String in CUE_SPECS:
		var streams: Array[AudioStream] = []
		var paths: PackedStringArray = PackedStringArray(["res://assets/audio/meow.wav"]) if cue == "meow" else PackedStringArray([
			"res://assets/audio/%s/%s_1.wav" % ["refined" if cue in REFINED_CUES else "p2", cue],
			"res://assets/audio/%s/%s_2.wav" % ["refined" if cue in REFINED_CUES else "p2", cue],
		])
		for path in paths:
			if ResourceLoader.exists(path):
				var stream := load(path) as AudioStream
				if stream != null and stream.get_length() > 0.0:
					streams.append(stream)
				else:
					missing_assets.append(path)
			else:
				missing_assets.append(path)
		cue_streams[cue] = streams
		_variant_next[cue] = 0
	assets_ready = missing_assets.is_empty()

func configure(combat_gain: float, voice_gain: float, ui_gain: float, muted: bool) -> void:
	group_gains.combat = _safe_gain(combat_gain)
	group_gains.voice = _safe_gain(voice_gain)
	group_gains.ui = _safe_gain(ui_gain)
	master_muted = muted
	if muted:
		clear()
	else:
		for index in range(players.size()):
			_apply_gain(index)

func _safe_gain(value: float) -> float:
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0

func unlock() -> void:
	# Call only from a user gesture. This does not play anything or replay drops.
	is_unlocked = true

func suspend(value: bool) -> void:
	is_suspended = value
	if value:
		clear()

func clear() -> void:
	# Keep the bounded consumed-event history. A dropped or interrupted event
	# cannot be replayed by a stale event batch after resume/unmute/unlock.
	for index in range(players.size()):
		_stop_slot(index)
	_last_played.clear()
	counts.cleared += 1

func play_cue(cue: String, event_id: Variant, group: String = "") -> bool:
	counts.requested += 1
	var request_usec := Time.get_ticks_usec()
	var id := str(event_id)
	if not _initialized or not is_inside_tree():
		return _reject("not_ready", cue, id, group, request_usec)
	if not CUE_SPECS.has(cue):
		return _reject("unknown_cue", cue, id, group, request_usec)
	var spec: Dictionary = CUE_SPECS[cue]
	var cue_group := str(spec.group)
	if not group.is_empty() and group != cue_group:
		return _reject("invalid_group", cue, id, group, request_usec)
	if id.is_empty() or id.length() > EVENT_ID_LIMIT:
		return _reject("invalid_event", cue, id.left(EVENT_ID_LIMIT), cue_group, request_usec)
	var key := cue + "|" + id
	if _seen.has(key):
		return _reject("duplicate", cue, id, cue_group, request_usec)
	_remember(key)
	if is_suspended:
		return _reject("suspended", cue, id, cue_group, request_usec)
	if not is_unlocked:
		return _reject("locked", cue, id, cue_group, request_usec)
	if master_muted or float(group_gains[cue_group]) <= 0.0:
		return _reject("muted", cue, id, cue_group, request_usec)
	var streams: Array = cue_streams[cue]
	if streams.is_empty():
		return _reject("missing_asset", cue, id, cue_group, request_usec)
	_reap_finished()
	var now := _now()
	if now - float(_last_played.get(cue, -1000.0)) < float(spec.cooldown):
		return _reject("cooldown", cue, id, cue_group, request_usec)
	var active_cue := 0
	for slot: Dictionary in slots:
		if slot.active and slot.cue == cue:
			active_cue += 1
	if active_cue >= int(spec.cap):
		return _reject("cue_cap", cue, id, cue_group, request_usec)
	var slot_index := _choose_slot(cue_group, int(spec.priority))
	if slot_index < 0:
		return _reject("pool_full", cue, id, cue_group, request_usec)
	if slots[slot_index].active:
		counts.preempted += 1
		_stop_slot(slot_index)
	var variant := int(_variant_next[cue]) % streams.size()
	_variant_next[cue] = (variant + 1) % streams.size()
	var player := players[slot_index]
	player.stream = streams[variant]
	player.pitch_scale = 1.0
	slots[slot_index].cue = cue
	_apply_gain(slot_index)
	player.play()
	var dispatched_usec := Time.get_ticks_usec()
	_sequence += 1
	var slot: Dictionary = slots[slot_index]
	slot.active = true
	slot.cue = cue
	slot.event_id = id
	slot.priority = int(spec.priority)
	slot.sequence = _sequence
	slot.started_usec = dispatched_usec
	slot.playhead = 0.0
	_last_played[cue] = now
	counts.played += 1
	counts.peak_active = maxi(int(counts.peak_active), _active_count())
	_append_bounded(played_log, {"cue": cue, "event_id": id, "group": cue_group,
		"time": now, "voice": slot_index, "variant": variant + 1,
		"request_usec": request_usec, "dispatched_usec": dispatched_usec,
		"dispatch_latency_ms": float(dispatched_usec - request_usec) / 1000.0,
		"estimated_output_latency_ms": _output_latency_ms(),
		"gain": player.volume_linear, "stream": player.stream.resource_path})
	return true

func tick(delta: float) -> void:
	# Presentation time is deliberately independent of frozen combat time. The
	# wall clock also advances this clock if the application stops ticking.
	if is_finite(delta) and delta > 0.0:
		_clock_seconds += delta
	_clock_seconds = maxf(_clock_seconds, float(Time.get_ticks_usec() - _start_usec) / 1000000.0)
	_reap_finished()
	for index in range(players.size()):
		if slots[index].active:
			playback_clock(index)

func playback_clock(slot_index: int) -> float:
	if slot_index < 0 or slot_index >= players.size() or not slots[slot_index].active:
		return 0.0
	var player := players[slot_index]
	# Godot's documented technical playback clock. Never substitute the game
	# simulation clock or a scheduled callback for the player's real position.
	var position := player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	position = maxf(0.0, position)
	if player.stream != null:
		position = minf(position, player.stream.get_length())
	slots[slot_index].playhead = maxf(float(slots[slot_index].playhead), position)
	return float(slots[slot_index].playhead)

func diagnostics() -> Dictionary:
	_reap_finished()
	var active_groups := {"combat": 0, "voice": 0, "ui": 0}
	for slot: Dictionary in slots:
		if slot.active:
			active_groups[slot.group] += 1
	return {"player_count": players.size(), "player_limit": PLAYER_LIMIT,
		"active_count": _active_count(), "active_groups": active_groups,
		"assets_ready": assets_ready, "missing_assets": missing_assets.duplicate(),
		"unlocked": is_unlocked, "suspended": is_suspended, "muted": master_muted,
		"group_gains": group_gains.duplicate(), "group_gain_caps": GROUP_GAIN_CAPS.duplicate(), "cue_gains": CUE_GAINS.duplicate(),
		"seen_event_count": _seen.size(), "event_history_limit": EVENT_HISTORY_LIMIT,
		"queued_count": 0, "counts": counts.duplicate(),
		"played_log": played_log.duplicate(true), "rejected_log": rejected_log.duplicate(true),
		"driver": AudioServer.get_driver_name(), "output_latency_ms": _output_latency_ms()}

func _now() -> float:
	return maxf(_clock_seconds, float(Time.get_ticks_usec() - _start_usec) / 1000000.0)

func _output_latency_ms() -> float:
	return maxf(0.0, AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()) * 1000.0

func _remember(key: String) -> void:
	var previous := _event_ring[_event_cursor]
	if not previous.is_empty():
		_seen.erase(previous)
	_event_ring[_event_cursor] = key
	_seen[key] = true
	_event_cursor = (_event_cursor + 1) % EVENT_HISTORY_LIMIT

func _reject(reason: String, cue: String, id: String, group: String, requested_usec: int) -> bool:
	counts.rejected += 1
	counts[reason] += 1
	_append_bounded(rejected_log, {"cue": cue.left(64), "event_id": id.left(EVENT_ID_LIMIT),
		"group": group.left(16), "reason": reason, "time": _now(), "request_usec": requested_usec})
	return false

func _append_bounded(log_entries: Array[Dictionary], entry: Dictionary) -> void:
	if log_entries.size() == LOG_LIMIT:
		log_entries.pop_front()
	log_entries.append(entry)

func _choose_slot(group: String, priority: int) -> int:
	var candidate := -1
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		if slot.group != group:
			continue
		if not slot.active:
			return index
		# Only a strictly higher-priority event may replace a voice. Reserved
		# voice/UI players can never be stolen by effects, regardless of priority.
		if int(slot.priority) >= priority:
			continue
		if candidate < 0 or int(slot.priority) < int(slots[candidate].priority) or (int(slot.priority) == int(slots[candidate].priority) and int(slot.sequence) < int(slots[candidate].sequence)):
			candidate = index
	return candidate

func _apply_gain(index: int) -> void:
	var group := str(slots[index].group)
	var cue_gain := float(CUE_GAINS.get(str(slots[index].cue), GROUP_GAIN_CAPS[group]))
	players[index].volume_linear = minf(cue_gain, float(GROUP_GAIN_CAPS[group])) * float(group_gains[group])

func _active_count() -> int:
	var count := 0
	for slot: Dictionary in slots:
		if slot.active:
			count += 1
	return count

func _reap_finished() -> void:
	for index in range(players.size()):
		if slots[index].active and not players[index].playing:
			_stop_slot(index)

func _stop_slot(index: int) -> void:
	players[index].stop()
	players[index].stream = null
	slots[index].active = false
	slots[index].cue = ""
	slots[index].event_id = ""
	slots[index].priority = -1
	slots[index].sequence = -1
	slots[index].started_usec = 0
	slots[index].playhead = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		suspend(true)

func _exit_tree() -> void:
	clear()
