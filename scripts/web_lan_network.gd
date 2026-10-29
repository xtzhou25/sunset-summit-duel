extends Node
## Browser-only lobby. A tiny WebSocket service only exchanges room lists and
## WebRTC SDP/ICE; all gameplay packets flow directly between the two browsers.

signal lobby_ready(is_host: bool)
signal rooms_changed(rooms: Array)
signal selections_changed(host_kind: int, guest_kind: int)
signal choice_rejected(reason: String)
signal match_started(host_kind: int, guest_kind: int)
signal snapshot_received(state: Dictionary)
signal session_closed(reason: String)
signal connection_failed(reason: String)
signal status_changed(message: String)
signal discovery_failed(reason: String)
signal discovery_ready
signal leaderboard_changed(entries: Array)
signal auth_question(name: String, question: String)
signal auth_ok(name: String, question: String, wins: int, losses: int)
signal auth_error(message: String)
signal pause_requested
signal rematch_requested

const SIGNAL_URL := "wss://mirugumi.space/duel-signal"
const TAP_KEYS := ["jump", "punch", "kick", "heavy", "roundhouse", "special"]
const PING_INTERVAL := 20.0
## 对局中大厅断线：静默重连的次数与间隔，全部失败后才提示本局不计入积分榜。
const RECONNECT_ATTEMPTS := 3
const RECONNECT_DELAY := 2.0

var active := false
var is_host := false
var room_name := ""
var game_port := 0
var host_kind := -1
var guest_kind := -1
var local_selection := -1
var remote_selection := -1
var local_name := "玩家"
var host_name := ""
var guest_name := ""

var _ws: WebSocketPeer
var _ws_open := false
var _pending_action: Dictionary = {}
var _rooms: Dictionary = {}
var _ping_accum := 0.0
var _rtc_pc: WebRTCPeerConnection
var _rtc_peer: WebRTCMultiplayerPeer
var _rtc_connected := false
var _rtc_desc_set := false
var _pending_ice: Array = []
var _hello_sent := false
var _welcome_sent := false
var _lobby_announced := false
var _closing := false
var _started := false
var _pending_move := 0.0
var _pending_crouch := false
var _pending_taps: Dictionary = {}
var _room_key := ""
var _signal_url := SIGNAL_URL
var _reconnect_left := 0
var _reconnect_timer := 0.0
var _peer_offline := false
var _rtc_wait := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_multiplayer_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if OS.has_feature("web"):
		# 本地联调：页面可以带 ?signal=ws://<地址>:8899 指向自己的信令服务
		var override := str(JavaScriptBridge.eval(
			"(new URLSearchParams(location.search)).get('signal')||''", true))
		if override.begins_with("ws://") or override.begins_with("wss://"):
			_signal_url = override

func _process(delta: float) -> void:
	_poll_signal(delta)
	_tick_reconnect(delta)
	if _rtc_pc != null:
		var state := _rtc_pc.get_connection_state()
		if _rtc_pc != null and not _rtc_connected and active:
			_rtc_wait += delta
			if _rtc_wait > 12.0 and _rtc_wait < 12.5:
				status_changed.emit("连接超时 · 开热点的手机无法参战；请让两台设备连同一个 Wi-Fi")
		if state == WebRTCPeerConnection.STATE_FAILED and active and not _rtc_connected:
			_fail("连接失败 · 请确认两台设备在同一网络后重试")
		elif state == WebRTCPeerConnection.STATE_CLOSED and active and _rtc_connected:
			_close_all()
			session_closed.emit("和对手的连接已断开")
		elif state == WebRTCPeerConnection.STATE_CONNECTED:
			if not _rtc_connected:
				_rtc_connected = true
				_rtc_wait = 0.0
				status_changed.emit("已连上对手")
			if is_host and not _welcome_sent:
				_welcome_sent = true
				_rpc_welcome.rpc_id(2, local_name, room_name)
			elif not is_host and not _hello_sent:
				_hello_sent = true
				_rpc_hello.rpc_id(1, local_name)

func remote_name() -> String:
	return guest_name if is_host else host_name


## 仅本地测试用：把信令地址指向本机的信令服务。
func set_signal_url(url: String) -> void:
	_signal_url = url

func local_ipv4() -> String:
	return "同一网络"

func _clean_name(value: String, fallback: String = "玩家") -> String:
	var result := value.strip_edges()
	if result.is_empty():
		result = fallback
	return result.substr(0, 16)

func start_discovery() -> void:
	_connect_signal()

func stop_discovery() -> void:
	if active:
		return
	_close_signal()
	if not _rooms.is_empty():
		_rooms.clear()
		rooms_changed.emit([])

func host_room(selected_name: String, port: int = 0, username: String = "玩家") -> bool:
	_close_all()
	local_name = _clean_name(username)
	room_name = selected_name.strip_edges()
	if room_name.is_empty():
		room_name = "决斗房间"
	active = true
	is_host = true
	_reset_lobby()
	_pending_action = {"type": "create", "room": room_name, "name": local_name}
	_connect_signal()
	return true

func join_room(address: String, port: int = 0, username: String = "玩家") -> bool:
	var key := address.strip_edges()
	if key.is_empty():
		return false
	_close_all()
	local_name = _clean_name(username)
	room_name = key
	active = true
	is_host = false
	_reset_lobby()
	_pending_action = {"type": "join", "room": key, "name": local_name}
	_connect_signal()
	return true

func close_room() -> void:
	_close_all()

func leave(reason: String = "已退出局域网对战") -> void:
	if not active and not _ws_open:
		return
	var was_active := active
	if _ws_open:
		_send_signal({"type": "leave"})
	_close_all()
	if was_active:
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

func report_result(winner_role: String) -> void:
	if active and is_host and _ws_open:
		_send_signal({"type": "result", "winner_role": winner_role})

func auth_register(username: String, question: String, answer: String) -> void:
	_connect_signal()
	_send_signal({"type": "register", "name": username, "question": question, "answer": answer})

func auth_login_begin(username: String) -> void:
	_connect_signal()
	_send_signal({"type": "login_begin", "name": username})

func auth_login_answer(username: String, answer: String) -> void:
	_connect_signal()
	_send_signal({"type": "login_answer", "name": username, "answer": answer})

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

func _connect_signal() -> void:
	if _ws != null:
		var state := _ws.get_ready_state()
		if state == WebSocketPeer.STATE_CONNECTING or state == WebSocketPeer.STATE_OPEN:
			return
	_ws = WebSocketPeer.new()
	_ws_open = false
	var err := _ws.connect_to_url(_signal_url)
	if err != OK:
		_ws = null
		if _reconnect_left > 0 or _reconnect_timer > 0.0:
			return
		discovery_failed.emit("无法连接联机大厅 · 请检查网络")
		if active:
			_fail("无法连接联机大厅 · 请检查网络")

func _close_signal() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	_ws_open = false
	_ping_accum = 0.0

func _send_signal(message: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(message))

func _poll_signal(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_open:
			_ws_open = true
			_reconnect_left = 0
			_reconnect_timer = 0.0
			_send_signal({"type": "hello", "name": local_name})
			discovery_ready.emit()
			if not _pending_action.is_empty():
				_send_signal(_pending_action)
				_pending_action = {}
		_ping_accum += delta
		if _ping_accum >= PING_INTERVAL:
			_ping_accum = 0.0
			_send_signal({"type": "ping"})
		while _ws != null and _ws.get_available_packet_count() > 0:
			var packet := _ws.get_packet()
			_handle_signal(packet.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_open := _ws_open
		_ws = null
		_ws_open = false
		if active and _started and _rtc_connected:
			# 对局中掉大厅：先静默重连，战斗本身不受影响。
			_begin_reconnect()
		elif active:
			_close_all()
			session_closed.emit("联机大厅连接已断开")
		elif was_open:
			connection_failed.emit("联机大厅连接已断开")


func _begin_reconnect() -> void:
	if _reconnect_left > 0 or _reconnect_timer > 0.0:
		return
	_reconnect_left = RECONNECT_ATTEMPTS
	_arm_reconnect()


func _arm_reconnect() -> void:
	if _reconnect_left <= 0:
		_reconnect_exhausted()
		return
	_reconnect_timer = RECONNECT_DELAY


func _reconnect_exhausted() -> void:
	_reconnect_timer = 0.0
	connection_failed.emit("联机大厅已断开，本局继续（胜负不记入积分榜）")


func _tick_reconnect(delta: float) -> void:
	if _reconnect_timer <= 0.0:
		return
	if _ws != null:
		_reconnect_timer = 0.0
		return
	_reconnect_timer -= delta
	if _reconnect_timer > 0.0:
		return
	_reconnect_timer = 0.0
	_reconnect_left -= 1
	_pending_action = _room_action()
	_connect_signal()
	if _ws == null:
		_arm_reconnect()


func _room_action() -> Dictionary:
	# 重连时按原房间号回到原来的席位，服务端保留一段宽限期
	return {"type": "rejoin", "room": _room_key, "role": "host" if is_host else "guest", "name": local_name}

func _handle_signal(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if typeof(message) != TYPE_DICTIONARY:
		return
	match str(message.get("type", "")):
		"rooms":
			_set_rooms(message.get("rooms", []))
		"leaderboard":
			var entries: Variant = message.get("entries", [])
			if entries is Array:
				leaderboard_changed.emit(entries)
		"auth_question":
			auth_question.emit(str(message.get("name", "")), str(message.get("question", "")))
		"auth_ok":
			auth_ok.emit(str(message.get("name", "")), str(message.get("question", "")), int(message.get("wins", 0)), int(message.get("losses", 0)))
		"auth_error":
			auth_error.emit(str(message.get("message", "账号操作失败")))
		"created":
			room_name = str(message.get("room", room_name))
			_room_key = str(message.get("room", room_name))
		"joined":
			_room_key = str(message.get("room", _room_key))
			host_name = _clean_name(str(message.get("host", "房主")), "房主")
			guest_name = local_name
			_setup_rtc(false)
		"rejoined":
			# 大厅重连成功，席位恢复，积分照常记录
			_room_key = str(message.get("room", _room_key))
			_peer_offline = false
		"peer_offline":
			_peer_offline = true
			connection_failed.emit("对手大厅连接掉线，正在等待重连…")
		"peer_back":
			_peer_offline = false
			connection_failed.emit("对手已重新连上大厅")
		"peer_joined":
			guest_name = _clean_name(str(message.get("name", "玩家")))
			_setup_rtc(true)
			if _rtc_pc != null:
				_rtc_pc.create_offer()
		"offer":
			if _rtc_pc == null:
				_setup_rtc(false)
			if _rtc_pc != null:
				_rtc_desc_set = true
				_rtc_pc.set_remote_description("offer", str(message.get("sdp", "")))
				_flush_ice()
		"answer":
			if _rtc_pc != null:
				_rtc_desc_set = true
				_rtc_pc.set_remote_description("answer", str(message.get("sdp", "")))
				_flush_ice()
		"ice":
			var candidate: Variant = message.get("candidate", [])
			if candidate is Array and candidate.size() >= 3:
				if _rtc_desc_set and _rtc_pc != null:
					_rtc_pc.add_ice_candidate(str(candidate[0]), int(candidate[1]), str(candidate[2]))
				else:
					_pending_ice.append(candidate)
		"error":
			var reason := str(message.get("message", "大厅操作失败"))
			if _reconnect_left > 0 or _reconnect_timer > 0.0:
				# 重连期间大厅报错：静默当作这次尝试失败，继续下一次
				_close_signal()
				_arm_reconnect()
				return
			_fail(reason)
		"session_closed":
			var reason := str(message.get("reason", "对手已离开房间"))
			_close_all()
			session_closed.emit(reason)

func _set_rooms(list: Variant) -> void:
	_rooms.clear()
	if list is Array:
		for entry: Variant in list:
			if entry is Dictionary:
				var key := str(entry.get("key", entry.get("name", "")))
				if key.is_empty():
					continue
				_rooms[key] = {
					"key": key,
					"name": str(entry.get("name", key)),
					"host": str(entry.get("host", "")),
					"ip": key,
					"port": 0,
					"mine": bool(entry.get("mine", false)),
				}
	rooms_changed.emit(_room_list())

func _room_list() -> Array:
	var rooms: Array = []
	for key in _rooms:
		rooms.append(_rooms[key].duplicate())
	rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return rooms

func _setup_rtc(host_side: bool) -> void:
	_close_rtc()
	_rtc_pc = WebRTCPeerConnection.new()
	var err := _rtc_pc.initialize({"iceServers": []})
	if err != OK:
		_fail("当前浏览器无法建立连接 · 请换用新版 Safari、Chrome 或 Edge")
		return
	_rtc_peer = WebRTCMultiplayerPeer.new()
	if host_side:
		_rtc_peer.create_server()
		_rtc_peer.add_peer(_rtc_pc, 2, 1)
	else:
		_rtc_peer.create_client(2)
		_rtc_peer.add_peer(_rtc_pc, 1, 1)
	multiplayer.multiplayer_peer = _rtc_peer
	_rtc_pc.session_description_created.connect(_on_rtc_session)
	_rtc_pc.ice_candidate_created.connect(_on_rtc_ice)
	_rtc_connected = false
	_rtc_desc_set = false
	_pending_ice.clear()
	_hello_sent = false
	_welcome_sent = false
	_lobby_announced = false
	_started = false
	_rtc_wait = 0.0
	status_changed.emit("正在连接对手…")

func _on_rtc_session(type: String, sdp: String) -> void:
	if _rtc_pc == null:
		return
	_rtc_pc.set_local_description(type, sdp)
	_send_signal({"type": type, "sdp": sdp})

func _on_rtc_ice(media: String, index: int, name: String) -> void:
	_send_signal({"type": "ice", "candidate": [media, index, name]})

func _flush_ice() -> void:
	if _rtc_pc == null:
		return
	for candidate: Array in _pending_ice:
		_rtc_pc.add_ice_candidate(str(candidate[0]), int(candidate[1]), str(candidate[2]))
	_pending_ice.clear()

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
	return _rtc_connected and multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0

func _maybe_start() -> void:
	if not active or not is_host or _started:
		return
	if host_kind < 0 or guest_kind < 0 or host_kind == guest_kind:
		return
	_started = true
	_reset_input()
	_rpc_begin.rpc(host_kind, guest_kind)
	match_started.emit(host_kind, guest_kind)

func _on_peer_connected(_id: int) -> void:
	if _closing or not active or not is_host:
		return
	_rtc_connected = true
	_welcome_sent = true
	_rpc_welcome.rpc_id(_id, local_name, room_name)

func _on_peer_disconnected(_id: int) -> void:
	if _closing or not active or not is_host:
		return
	_close_all()
	session_closed.emit("对手已离开房间")

func _on_connected_to_server() -> void:
	if _closing or not active or is_host:
		return
	_rtc_connected = true
	_hello_sent = true
	_rpc_hello.rpc_id(1, local_name)

func _on_multiplayer_failed() -> void:
	if _closing or not active:
		return
	_fail("连接失败 · 请重试")

func _on_server_disconnected() -> void:
	if _closing or not active or is_host:
		return
	_close_all()
	session_closed.emit("房主已关闭房间")

func _fail(reason: String) -> void:
	var was_live := _lobby_announced or _rtc_connected or _started
	_close_all()
	active = false
	if was_live:
		session_closed.emit(reason)
	else:
		connection_failed.emit(reason)

func _close_rtc() -> void:
	if _rtc_peer != null:
		multiplayer.multiplayer_peer = null
		_rtc_peer.close()
		_rtc_peer = null
	elif multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	if _rtc_pc != null:
		_rtc_pc.close()
		_rtc_pc = null
	_rtc_connected = false
	_rtc_desc_set = false
	_pending_ice.clear()
	_hello_sent = false
	_welcome_sent = false

func _close_all() -> void:
	_closing = true
	active = false
	is_host = false
	_started = false
	host_kind = -1
	guest_kind = -1
	local_selection = -1
	remote_selection = -1
	host_name = ""
	guest_name = ""
	_lobby_announced = false
	_reset_input()
	_pending_action = {}
	_room_key = ""
	_reconnect_left = 0
	_reconnect_timer = 0.0
	_peer_offline = false
	_close_rtc()
	_close_signal()
	_closing = false

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
