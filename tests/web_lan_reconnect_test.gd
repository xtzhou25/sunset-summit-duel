extends SceneTree
## 本地验证：对局中大厅断线时，客户端是否静默重连 3 次后才提示“不计入积分榜”。
##
##   node server/lan_signal_server.js            # 先起本地信令服务（127.0.0.1:8899）
##   godot --headless --path . --script tests/web_lan_reconnect_test.gd
##
## 阶段一：服务在线，强制断开信令 → 应自动 rejoin 成功，且不提示丢分。
## 阶段二：把信令地址改成死端口，强制断开 → 3 次静默重试后提示丢分。

const LAN := preload("res://scripts/web_lan_network.gd")

var lan
var failures := 0
var notices: Array[String] = []
var rejoin_ok := false


func _initialize() -> void:
	lan = LAN.new()
	lan.set_signal_url("ws://127.0.0.1:8899")
	root.add_child(lan)
	lan.connection_failed.connect(func(reason: String) -> void: notices.append(reason))
	lan.session_closed.connect(func(reason: String) -> void:
		push_error("对局被意外结束: " + reason)
		failures += 1)
	lan.host_room("重连测试房", 0, "测试房主")
	_run.call_deferred()


func _run() -> void:
	if not await _wait_until(func() -> bool: return lan._room_key != "", 8.0):
		_finish("信令服务未连接成功（请先启动 node server/lan_signal_server.js）")
		return
	print("PASS: 已建房 ", lan._room_key)

	# 模拟对局进行中
	lan._started = true
	lan._rtc_connected = true

	# 阶段一：服务还在，强制断开应当静默重连并回到原席位
	lan._ws.close()
	if not await _wait_until(func() -> bool: return lan._ws_open, 15.0):
		_finish("阶段一：没有重连上信令服务")
		return
	rejoin_ok = await _wait_until(func() -> bool: return lan._room_key != "" and lan._ws_open, 5.0)
	if not rejoin_ok:
		_finish("阶段一：重连后没有回到原房间")
		return
	if not notices.is_empty():
		_finish("阶段一：重连成功却提示了丢分 %s" % [notices])
		return
	print("PASS: 断线后静默重连成功，无丢分提示")

	# 阶段二：信令地址换成死端口，三次重试后必须提示丢分
	lan.set_signal_url("ws://127.0.0.1:9")
	lan._ws.close()
	if not await _wait_until(func() -> bool:
			for n in notices:
				if n.contains("不记入积分榜"):
					return true
			return false, 30.0):
		_finish("阶段二：三次重试后没有提示丢分")
		return
	print("PASS: 三次静默重试后提示：", notices[-1])
	_finish("")


func _wait_until(check: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if check.call():
			return true
		await process_frame
	return false


func _finish(message: String) -> void:
	if message != "":
		print("FAIL: ", message)
		failures += 1
	print("reconnect tests failures: ", failures)
	quit(0 if failures == 0 else 1)
