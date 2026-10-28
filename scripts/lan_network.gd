extends Node
## LAN-only direct play. The host machine is the authoritative server and the
## guest connects straight to its ENet port; nothing is forwarded by us.
## Rooms are announced with UDP broadcast so every machine on the same subnet
## can see them without a central lobby service.

signal lobby_ready(is_host: bool)
signal rooms_changed(rooms: Array)
signal selections_changed(host_kind: int, guest_kind: int)
signal choice_rejected(reason: String)
signal match_started(host_kind: int, guest_kind: int)
signal snapshot_received(state: Dictionary)
signal session_closed(reason: String)
signal connection_failed(reason: String)
signal discovery_failed(reason: String)
signal discovery_ready
signal leaderboard_changed(entries: Array)
signal auth_question(name: String, question: String)
signal auth_ok(name: String, question: String, wins: int, losses: int)
signal auth_error(message: String)
signal pause_requested
signal rematch_requested

const GAME_PORT := 7777
const DISCOVERY_PORT := 7778
const DISCOVERY_INTERVAL := 1.0
const ROOM_TTL := 3.5
const PROTOCOL := "sunset-summit-lan-v1"
const MAX_CLIENTS := 1
const TAP_KEYS := ["jump", "punch", "kick", "heavy", "roundhouse", "special"]

var active := false
var is_host := false
var room_name := ""
var game_port := GAME_PORT
var host_kind := -1
var guest_kind := -1
var local_selection := -1
var remote_selection := -1
var local_name := "玩家"
var host_name := ""
var guest_name := ""

var _peer: ENetMultiplayerPeer
var _discovery: PacketPeerUDP
var _rooms: Dictionary = {}
var _broadcast_accum := 0.0
var _advertising := false
var _started := false
var _lobby_announced := false
var _closing := false
var _pending_move := 0.0
var _pending_crouch := false
var _pending_taps: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	if _advertising and active and is_host:
		_broadcast_accum += delta
		if _broadcast_accum >= DISCOVERY_INTERVAL:
			_broadcast_accum = 0.0
			_advertise_room()
	if _discovery != null:
		_poll_discovery()

func remote_name() -> String:
	return guest_name if is_host else host_name

func _clean_name(value: String, fallback: String = "玩家") -> String:
	var result := value.strip_edges()
	if result.is_empty():
		result = fallback
	return result.substr(0, 16)

func local_ipv4() -> String:
	for address in IP.get_local_addresses():
		if address.count(".") != 3:
			continue
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		return address
	return "127.0.0.1"

func start_discovery() -> void:
	if _discovery != null:
		return
	_discovery = PacketPeerUDP.new()
	_discovery.set_broadcast_enabled(true)
	var err := _discovery.bind(DISCOVERY_PORT, "*")
	if err != OK:
		_discovery = null
		discovery_failed.emit("自动发现不可用 · 可手动输入对方 IP")
		return
	_rooms.clear()
	rooms_changed.emit([])
	discovery_ready.emit()

func stop_discovery() -> void:
	if _discovery != null:
		_discovery.close()
		_discovery = null
	if not _rooms.is_empty():
		_rooms.clear()
		rooms_changed.emit([])

func host_room(selected_name: String, port: int = GAME_PORT, username: String = "玩家") -> bool:
	close_room()
	local_name = _clean_name(username)
	room_name = selected_name.strip_edges()
	if room_name.is_empty():
		room_name = "决斗房间"
	game_port = clampi(port, 1, 65535)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(game_port, MAX_CLIENTS)
	if err != OK:
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = true
	_reset_lobby()
	_advertising = true
	_broadcast_accum = 0.0
	_advertise_room()
	return true

func join_room(address: String, port: int = GAME_PORT, username: String = "玩家") -> bool:
	close_room()
	var target := address.strip_edges()
	if target.is_empty():
		return false
	local_name = _clean_name(username)
	game_port = clampi(port, 1, 65535)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(target, game_port)
	if err != OK:
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	active = true
	is_host = false
	_reset_lobby()
	return true

func close_room() -> void:
	if _closing:
		return
	_closing = true
	active = false
	is_host = false
	_advertising = false
	_broadcast_accum = 0.0
	_started = false
	host_kind = -1
	guest_kind = -1
	local_selection = -1
	remote_selection = -1
	host_name = ""
	guest_name = ""
	_lobby_announced = false
	_reset_input()
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	_closing = false

func leave(reason: String = "已退出局域网对战") -> void:
	if not active:
		return
	var was_host := is_host
	var connected := _has_remote()
	if was_host and connected:
		_rpc_closed.rpc(reason)
	elif not was_host and connected:
		_rpc_leave.rpc_id(1)
	close_room()
	session_closed.emit(reason)

func choose_character(kind: int) -> void:
	if not active:
		return
	if is_host:
		if guest_kind >= 0 and guest_kind == kind:
			choice_rejected.emit("该角色已被对手选择 · 请重新选择")
			return
		host_kind = kind
		local_selection = kind
		remote_selection = guest_kind
		if _has_remote():
			_rpc_selection.rpc(host_kind, guest_kind)
		selections_changed.emit(host_kind, guest_kind)
		_maybe_start()
	elif _has_remote():
		_rpc_choose.rpc_id(1, kind)

func host_rematch() -> void:
	if not active or not is_host:
		return
	_reset_input()
	_rpc_begin.rpc(host_kind, guest_kind)
	match_started.emit(host_kind, guest_kind)

func request_rematch() -> void:
	if active and not is_host and _has_remote():
		_rpc_request_rematch.rpc_id(1)

func request_pause() -> void:
	if active and not is_host and _has_remote():
		_rpc_request_pause.rpc_id(1)

func report_result(_winner_role: String) -> void:
	pass

func auth_register(_username: String, _question: String, _answer: String) -> void:
	pass

func auth_login_begin(_username: String) -> void:
	pass

func auth_login_answer(_username: String, _answer: String) -> void:
	pass

func send_input(command: Dictionary) -> void:
	if active and not is_host and _has_remote():
		_rpc_input.rpc_id(1, command)

func send_snapshot(state: Dictionary) -> void:
	if active and is_host and _has_remote():
		_rpc_snapshot.rpc(state)

func consume_guest_command() -> Dictionary:
	var command := {"move": _pending_move, "crouch": _pending_crouch}
	for key in TAP_KEYS:
		command[key] = bool(_pending_taps.get(key, false))
		_pending_taps[key] = false
	return command

func discard_guest_input() -> void:
	_reset_input()

func _reset_lobby() -> void:
	host_kind = -1
	guest_kind = -1
	local_selection = -1
	remote_selection = -1
	_started = false
	_lobby_announced = false
	host_name = local_name if is_host else ""
	guest_name = "" if is_host else local_name
	_reset_input()

func _reset_input() -> void:
	_pending_move = 0.0
	_pending_crouch = false
	for key in TAP_KEYS:
		_pending_taps[key] = false

func _has_remote() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.get_peers().size() > 0

func _maybe_start() -> void:
	if not active or not is_host or _started:
		return
	if host_kind < 0 or guest_kind < 0 or host_kind == guest_kind:
		return
	_started = true
	_reset_input()
	_rpc_begin.rpc(host_kind, guest_kind)
	match_started.emit(host_kind, guest_kind)

func _broadcast_room() -> void:
	if not _advertising or not active or not is_host:
		return
	var sender := PacketPeerUDP.new()
	sender.set_broadcast_enabled(true)
	sender.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	var payload := {
		"protocol": PROTOCOL,
		"type": "room",
		"name": room_name,
		"host": local_name,
		"port": game_port,
		"players": 1,
		"max": 2,
	}
	sender.put_packet(JSON.stringify(payload).to_utf8_buffer())
	sender.close()

func _advertise_room() -> void:
	_broadcast_room()

func _poll_discovery() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	while _discovery.get_available_packet_count() > 0:
		var packet := _discovery.get_packet()
		var sender_ip := _discovery.get_packet_ip()
		var data: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if str(data.get("protocol", "")) != PROTOCOL or str(data.get("type", "")) != "room":
			continue
		var port := int(data.get("port", GAME_PORT))
		var key := "%s:%d" % [sender_ip, port]
		var entry := {
			"key": key,
			"name": str(data.get("name", "决斗房间")),
			"host": str(data.get("host", "")),
			"ip": sender_ip,
			"port": port,
			"updated": now,
		}
		var old: Dictionary = _rooms.get(key, {})
		if old.is_empty() or str(old.get("name", "")) != str(entry.name):
			changed = true
		elif str(old.get("host", "")) != str(entry.host):
			changed = true
		_rooms[key] = entry
	for key in _rooms.keys():
		if now - float(_rooms[key].get("updated", 0.0)) > ROOM_TTL:
			_rooms.erase(key)
			changed = true
	if changed:
		rooms_changed.emit(_room_list())

func _room_list() -> Array:
	var rooms: Array = []
	for key in _rooms:
		rooms.append(_rooms[key].duplicate())
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return rooms

func _on_peer_connected(id: int) -> void:
	if _closing or not active or not is_host:
		return
	_advertising = false
	_rpc_welcome.rpc_id(id, local_name, room_name)

func _on_peer_disconnected(_id: int) -> void:
	if _closing or not active or not is_host:
		return
	close_room()
	session_closed.emit("对手已离开房间")

func _on_connected_to_server() -> void:
	if _closing or not active or is_host:
		return
	_rpc_hello.rpc_id(1, local_name)

func _on_connection_failed() -> void:
	if _closing or not active or is_host:
		return
	close_room()
	connection_failed.emit("连接失败 · 请检查房间 IP、端口和防火墙")

func _on_server_disconnected() -> void:
	if _closing or not active or is_host:
		return
	close_room()
	session_closed.emit("房主已关闭房间")

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(username: String) -> void:
	if not is_host or _closing:
		return
	guest_name = _clean_name(username)
	if not _lobby_announced:
		_lobby_announced = true
		lobby_ready.emit(true)

@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(host_username: String, selected_room: String) -> void:
	if is_host or _closing:
		return
	host_name = _clean_name(host_username, "房主")
	room_name = selected_room
	if not _lobby_announced:
		_lobby_announced = true
		lobby_ready.emit(false)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_choose(kind: int) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if host_kind >= 0 and kind == host_kind:
		_rpc_rejected.rpc_id(sender, "该角色已被房主选择 · 请重新选择")
		return
	guest_kind = kind
	remote_selection = kind
	_rpc_selection.rpc(host_kind, guest_kind)
	selections_changed.emit(host_kind, guest_kind)
	_maybe_start()

@rpc("authority", "call_remote", "reliable")
func _rpc_selection(host_choice: int, guest_choice: int) -> void:
	if is_host:
		return
	host_kind = host_choice
	guest_kind = guest_choice
	local_selection = guest_choice
	remote_selection = host_choice
	selections_changed.emit(host_kind, guest_kind)

@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	if is_host:
		return
	choice_rejected.emit(reason)

@rpc("authority", "call_remote", "reliable")
func _rpc_begin(host_choice: int, guest_choice: int) -> void:
	if is_host:
		return
	host_kind = host_choice
	guest_kind = guest_choice
	local_selection = guest_choice
	remote_selection = host_choice
	_started = true
	_reset_input()
	match_started.emit(host_kind, guest_kind)

@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(state: Dictionary) -> void:
	if is_host:
		return
	snapshot_received.emit(state)

@rpc("authority", "call_remote", "reliable")
func _rpc_closed(reason: String) -> void:
	if is_host or not active:
		return
	close_room()
	session_closed.emit(reason)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_input(command: Dictionary) -> void:
	if not is_host:
		return
	_pending_move = float(command.get("move", 0.0))
	_pending_crouch = bool(command.get("crouch", false))
	for key in TAP_KEYS:
		if bool(command.get(key, false)):
			_pending_taps[key] = true

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pause() -> void:
	if is_host:
		pause_requested.emit()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_rematch() -> void:
	if is_host:
		rematch_requested.emit()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_leave() -> void:
	if not is_host or not active:
		return
	close_room()
	session_closed.emit("对手已离开房间")
