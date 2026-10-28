extends Node
const Combat=preload("res://scripts/combat.gd")
const Characters=preload("res://scripts/characters.gd")
const AI=preload("res://scripts/ai.gd")
var sim=Combat.new()
var brain=AI.new()
var lan
var network_active:=false
var network_in_match:=false
var network_is_host:=false
var network_match_over:=false
var network_result_reported:=false
var network_result_text:=""
var hud
var camera:Camera3D
var camera_rig=preload("res://scripts/fight_camera.gd").new()
var stage:Node3D
var world:Node3D
var actors:Array=[]
var anims:Array=[]
var current_clips:Array=["",""]
var rendered_attack_ids:Array=[0,0]
var rendered_faces:Array=[1,-1]
var held:Dictionary={}
var keyboard_sources:Dictionary={}
var touch_sources:Dictionary={}
var taps:Dictionary={}
var playing:=false
var paused:=false
var muted:=false
var selected:=0
var loaded_selection:=-1
var opponent_selected:=1
var opponent_selection=preload("res://scripts/opponent_selection.gd").new()
var loaded_pair:=[]
var model_cache:Dictionary={}
var model_storage:Node3D
var rifle_props:Array=[null,null]
var rifle_contract:Dictionary={}
var peach_contract:Dictionary={}
var wins:Array=[0,0]
var round_delay:=0.0
var hitstop:=0.0
var animation_manual:=true
var effects:Array=[]
var landing_remaining:Array=[0.0,0.0]
var previous_height:Array=[0.0,0.0]
var last_feedback:=""
var status_text:="选择角色，开启演出"
var projectile_view: Node3D
var meow_sound: AudioStreamPlayer
var emitter_positions: Dictionary = {}
var projectile_audio_kinds: Dictionary = {}
var marker_config: Dictionary = {}
var sound:AudioStreamPlayer
var sound_enabled:=false
var audio_pool
var combat_audio # Compatibility alias to the same fixed pool, never extra players.
var combat_gain:=0.85
var voice_gain:=1.0
var shake_enabled:=true
var shake_remaining:=0.0
var shake_offset:=Vector2.ZERO
var feedback_history:Array=[]
var feedback_seen:Dictionary={}
var feedback_floor:=0
var feedback_watermark:=0
var ui_serial:=0
const SETTINGS_PATH="user://feedback.cfg"
const WEB_MAX_DPR:=2.0
var screenshot_countdown:=-1.0
var screenshot_path:=""
var auto_demo:=false
var demo_elapsed:=0.0

func _ready() -> void:
	_sync_web_pixel_scale()
	if OS.has_feature("web"): get_window().size_changed.connect(_queue_web_pixel_scale)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		get_window().min_size=Vector2i(960,600)
	world=Node3D.new(); add_child(world)
	var stage_script=load("res://stage-art/expanded_livehouse.gd")
	if stage_script:
		stage=stage_script.new(); world.add_child(stage)
	camera=Camera3D.new(); world.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=6.4
	camera.position=Vector3(0,3.25,11.5)
	camera.look_at(Vector3(0,1.55,0))
	camera.current=true
	for id in range(2):
		var root:=Node3D.new(); world.add_child(root); actors.append(root); anims.append(null)
	model_storage=Node3D.new(); world.add_child(model_storage); model_storage.visible=false
	rifle_contract=JSON.parse_string(FileAccess.get_file_as_string("res://assets/qi_rifle_contract.json"))
	peach_contract=JSON.parse_string(FileAccess.get_file_as_string("res://assets/tao_peach_contract.json"))
	load_characters()
	hud=load("res://scripts/hud.gd").new(); add_child(hud)
	hud.selected.connect(_on_character_selected)
	hud.command.connect(on_command)
	hud.pause_requested.connect(toggle_pause)
	hud.rematch_requested.connect(_on_rematch_requested)
	hud.menu_requested.connect(_on_menu_requested)
	hud.mute_requested.connect(toggle_mute)
	hud.lan_host_requested.connect(_on_lan_host_requested)
	hud.lan_join_requested.connect(_on_lan_join_requested)
	hud.lan_cancel_requested.connect(_on_lan_cancel_requested)
	hud.lan_discovery_requested.connect(_start_lan_discovery)
	hud.lan_discovery_stopped.connect(_stop_lan_discovery)
	lan=load("res://scripts/web_lan_network.gd" if OS.has_feature("web") else "res://scripts/lan_network.gd").new()
	lan.name="LAN"; add_child(lan)
	lan.lobby_ready.connect(_on_lan_lobby_ready)
	lan.rooms_changed.connect(hud.set_lan_rooms)
	lan.selections_changed.connect(_on_lan_selections_changed)
	lan.choice_rejected.connect(_on_lan_choice_rejected)
	lan.match_started.connect(_on_lan_match_started)
	lan.snapshot_received.connect(_on_lan_snapshot)
	lan.session_closed.connect(_on_lan_session_closed)
	lan.connection_failed.connect(_on_lan_connection_failed)
	lan.discovery_failed.connect(_on_lan_discovery_failed)
	lan.discovery_ready.connect(_on_lan_discovery_ready)
	lan.leaderboard_changed.connect(hud.set_lan_leaderboard)
	lan.auth_question.connect(hud.lan_auth_question_received)
	lan.auth_ok.connect(hud.lan_auth_ok)
	lan.auth_error.connect(hud.lan_auth_error)
	hud.lan_auth_register.connect(_on_lan_auth_register)
	hud.lan_auth_login_begin.connect(_on_lan_auth_login_begin)
	hud.lan_auth_login_answer.connect(_on_lan_auth_login_answer)
	lan.pause_requested.connect(_on_lan_pause_requested)
	lan.rematch_requested.connect(_on_lan_rematch_requested)
	audio_pool=preload("res://scripts/combat_audio.gd").new(); add_child(audio_pool)
	combat_audio=audio_pool
	sound=audio_pool.players[0]; meow_sound=audio_pool.players[6]
	load_feedback_preferences()
	hud.feedback_settings_changed.connect(set_feedback_preferences)
	projectile_view=load("res://scripts/projectile_view.gd").new(); world.add_child(projectile_view)
	if FileAccess.file_exists("res://assets/signature_markers.json"):
		marker_config=JSON.parse_string(FileAccess.get_file_as_string("res://assets/signature_markers.json"))
	sim.emitter_provider=signature_emitter
	get_viewport().size_changed.connect(layout_camera)
	layout_camera()
	for arg in OS.get_cmdline_user_args():
		if arg=="--demo": auto_demo=true; hud._choose(0)
		elif arg.begins_with("--screenshot="): screenshot_path=arg.trim_prefix("--screenshot="); screenshot_countdown=2.0
	render_state(0.0)

func _queue_web_pixel_scale() -> void:
	call_deferred("_sync_web_pixel_scale")

func _sync_web_pixel_scale() -> void:
	if not OS.has_feature("web"): return
	var win:=get_window()
	var dpr:=clampf(float(JavaScriptBridge.eval("window.devicePixelRatio||1")),1.0,WEB_MAX_DPR)
	var logical:=Vector2i.ZERO
	var canvas_raw:Variant=JavaScriptBridge.eval("(function(){var c=document.getElementById('canvas');return c?[c.width,c.height]:null;})()")
	if canvas_raw is Array and canvas_raw.size()>=2:
		# Read the backing buffer directly: the HTML shell may resize it in the
		# same frame as a CSS page rotation, before Window.size reports the new
		# value. Using the stale portrait size letterboxes the rotated canvas.
		logical=Vector2i(maxi(1,int(round(float(canvas_raw[0])/dpr))),maxi(1,int(round(float(canvas_raw[1])/dpr))))
	else:
		logical=Vector2i(maxi(1,int(round(win.size.x/dpr))),maxi(1,int(round(win.size.y/dpr))))
	if win.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and win.content_scale_size==logical and win.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_IGNORE: return
	win.content_scale_size=logical
	win.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_IGNORE

func load_characters() -> void:
	var pair:Array=[selected,opponent_selected]
	if loaded_pair!=pair:
		for i in range(2):
			for child in actors[i].get_children():
				if child==rifle_props[i]: continue
				child.reparent(model_storage,false)
		for i in range(2):
			var kind:int=pair[i]
			if not model_cache.has(kind):
				var model=load(Characters.get_character(kind).model).instantiate()
				model.scale=Vector3.ONE*1.2; softlight(model)
				model_storage.add_child(model); model_cache[kind]=model
			var model:Node3D=model_cache[kind]
			model.reparent(actors[i],false); actors[i].move_child(model,0)
			anims[i]=find_animation(model)
			anims[i].callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			for clip in anims[i].get_animation_list():
				if clip.trim_suffix("_R").trim_suffix("_L") in ["Idle","Walk","Run","JumpLoop","Guard","BackstepGuard","FightIdle","CrouchLoop"]: anims[i].get_animation(clip).loop_mode=Animation.LOOP_LINEAR
			if rifle_props[i]==null:
				rifle_props[i]=load("res://assets/qi_rifle.glb").instantiate()
				actors[i].add_child(rifle_props[i]);softlight(rifle_props[i])
		loaded_pair=pair.duplicate()
	loaded_selection=selected
	for i in range(2):
		current_clips[i]="";rendered_attack_ids[i]=0
		if anims[i]: anims[i].stop()
		if rifle_props[i]: rifle_props[i].hide()

func update_rifle(index:int) -> void:
	if not is_instance_valid(rifle_props[index]): return
	var f:Dictionary=sim.fighters[index]
	var visible_now:bool=int(f.kind)==2 and playing and not sim.round_over and f.hp>0 and not f.down and f.stun<=0 and f.attack=="special" and f.clock>=float(rifle_contract.prop_visible_s[0]) and f.clock<=float(rifle_contract.prop_visible_s[1])
	rifle_props[index].visible=visible_now
	if not visible_now: return
	var skeleton:Skeleton3D=find_skeleton(model_cache[2])
	skeleton.force_update_all_bone_transforms()
	var bone:int=skeleton.find_bone(str(rifle_contract.hand_bone))
	var side:String="R" if f.special_face>0 else "L"
	var rows:Array=rifle_contract.facing[side].prop_attachment_matrix_rows
	var basis:=Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2]))
	var local:=Transform3D(basis,Vector3(rows[0][3],rows[1][3],rows[2][3]))
	rifle_props[index].global_transform=skeleton.global_transform*skeleton.get_bone_global_pose(bone)*local

func softlight(node:Node) -> void:
	if DisplayServer.get_name()=="headless": return
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var original=node.get_active_material(surface)
			if original is StandardMaterial3D:
				var material:=ShaderMaterial.new()
				material.shader=load("res://assets/character_softlight.gdshader")
				material.set_shader_parameter("base_color",original.albedo_color)
				node.set_surface_override_material(surface,material)
	for child in node.get_children(): softlight(child)

func find_animation(node:Node):
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var result=find_animation(child)
		if result: return result
	return null

func layout_camera() -> void:
	if not hud or not camera: return
	var vp:=get_viewport().get_visible_rect().size
	var gameplay_height:float=vp.y*hud.gameplay_height_ratio()
	# Preserve the proven vertical jump/cake/HUD envelope on short landscape.
	camera_rig.configure(maxf(7.2,3.45*vp.x/maxf(40.0,gameplay_height-108.0)))
	update_fight_camera(0.0,true)

func update_fight_camera(delta:float,snap:bool=false) -> void:
	if not hud or not camera or sim.fighters.size()!=2: return
	if not paused or snap:
		camera_rig.update(float(sim.fighters[0].x),float(sim.fighters[1].x),delta,snap)
	camera.position.x=camera_rig.center_x
	camera.size=camera_rig.width
	var vp:=get_viewport().get_visible_rect().size
	var gameplay_height:float=vp.y*hud.gameplay_height_ratio()
	camera.v_offset=0.0
	var ground_y:float=camera.unproject_position(Vector3.ZERO).y
	var wanted_ground:float=gameplay_height*0.70+25.0 if vp.y>vp.x else gameplay_height-26.0
	camera.v_offset=(wanted_ground-ground_y)*camera.size/maxf(1.0,vp.x)
	if stage and stage.has_method("update_view"):
		stage.motion_active=playing and not paused
		stage.update_view(camera,gameplay_height,not shake_enabled)

func _on_character_selected(kind:int) -> void:
	if lan and lan.active:
		lan.choose_character(kind)
		if not lan.is_host and not network_in_match:
			hud.show_lan_lobby("已选择 %s · 等待确认…" % str(Characters.get_character(kind).name))
	else:
		start_match(kind,hud.opponent_for(kind))

func _on_rematch_requested() -> void:
	if network_active:
		if network_is_host:
			if not playing: lan.host_rematch()
		else:
			lan.request_rematch()
	else:
		start_match(selected,opponent_selection.requested)

func _on_menu_requested() -> void:
	if network_active:
		lan.leave("已退出局域网对战")
	else:
		show_menu()

func _start_lan_discovery() -> void:
	if lan: lan.start_discovery()

func _stop_lan_discovery() -> void:
	if lan: lan.stop_discovery()

func _on_lan_host_requested(room:String,port:int,username:String) -> void:
	if not lan:
		hud.lan_status("浏览器版暂不支持局域网直连 · 请使用桌面版")
		return
	lan.stop_discovery()
	if lan.host_room(room,port,username):
		if OS.has_feature("web"):
			hud.lan_status("房间已创建 · 昵称 %s · 等待大厅对手加入" % username)
		else:
			hud.lan_status("房间已创建 · 昵称 %s · 本机 IP %s · 等待对手加入" % [username,lan.local_ipv4()])
	else:
		hud.lan_status("创建失败 · 端口 %d 可能已被占用" % port)

func _on_lan_join_requested(address:String,port:int,username:String) -> void:
	if not lan:
		hud.lan_status("浏览器版暂不支持局域网直连 · 请使用桌面版")
		return
	if lan.join_room(address,port,username):
		if OS.has_feature("web"):
			hud.lan_status("正在加入大厅房间 %s …" % address)
		else:
			hud.lan_status("正在连接 %s:%d …" % [address,port])
	else:
		hud.lan_status("无法发起连接 · 请检查房间或 IP")

func _on_lan_cancel_requested() -> void:
	if lan and lan.active:
		lan.leave("已取消局域网房间")
	else:
		hud.show_entry("已返回模式选择")

func _on_lan_lobby_ready(host_side:bool) -> void:
	network_active=true
	network_in_match=false
	network_is_host=host_side
	network_match_over=false
	hud.set_local_side(0 if network_is_host else 1)
	var local_name:String=lan.host_name if network_is_host else lan.local_name
	hud.show_lan_lobby("你（%s）已连接对手（%s） · 选择角色（双方不能相同）" % [local_name,lan.remote_name()])

func _lan_lobby_text(host_kind:int,guest_kind:int) -> String:
	var local_kind:int=host_kind if lan.is_host else guest_kind
	var remote_kind:int=guest_kind if lan.is_host else host_kind
	var local_name:String=lan.host_name if lan.is_host else lan.local_name
	var remote_name:String=lan.guest_name if lan.is_host else lan.host_name
	var parts:Array=[]
	if local_kind>=0: parts.append("你（%s）：%s" % [local_name,str(Characters.get_character(local_kind).name)])
	if remote_kind>=0: parts.append("对手（%s）：%s" % [remote_name,str(Characters.get_character(remote_kind).name)])
	var text:=""
	for part in parts:
		if text!="": text+=" · "
		text+=str(part)
	if host_kind>=0 and guest_kind>=0 and host_kind!=guest_kind:
		return text+" · 准备开赛！"
	if text.is_empty():
		return "已连接对手 %s · 选择角色（双方不能相同）" % lan.remote_name()
	return text+" · 等待选择…"

func _on_lan_selections_changed(host_kind:int,guest_kind:int) -> void:
	if not network_active or network_in_match: return
	hud.show_lan_lobby(_lan_lobby_text(host_kind,guest_kind))

func _on_lan_choice_rejected(reason:String) -> void:
	if network_active and not network_in_match:
		hud.show_lan_lobby(reason)

func _on_lan_match_started(host_kind:int,guest_kind:int) -> void:
	start_lan_match(host_kind,guest_kind,lan.is_host)

func _on_lan_snapshot(state:Dictionary) -> void:
	apply_network_snapshot(state)

func _on_lan_session_closed(reason:String) -> void:
	network_active=false
	network_in_match=false
	network_is_host=false
	network_match_over=false
	playing=false
	paused=false
	if audio_pool: audio_pool.suspend(false)
	if hud:
		hud.set_paused(false)
		hud.show_entry(reason)

func _on_lan_connection_failed(reason:String) -> void:
	hud.lan_status(reason)

func _on_lan_discovery_failed(reason:String) -> void:
	hud.lan_status(reason)

func _on_lan_discovery_ready() -> void:
	if OS.has_feature("web"):
		hud.lan_status("大厅已连接 · 可创建房间或从列表加入")
	else:
		hud.lan_status("局域网搜索已开启 · 可创建房间或手动加入")

func _on_lan_auth_register(username:String,question:String,answer:String) -> void:
	if lan: lan.auth_register(username,question,answer)

func _on_lan_auth_login_begin(username:String) -> void:
	if lan: lan.auth_login_begin(username)

func _on_lan_auth_login_answer(username:String,answer:String) -> void:
	if lan: lan.auth_login_answer(username,answer)

func _on_lan_pause_requested() -> void:
	if network_active and network_is_host:
		toggle_pause()

func _on_lan_rematch_requested() -> void:
	if network_active and network_is_host and not playing:
		lan.host_rematch()

func start_lan_match(host_kind:int,guest_kind:int,local_is_host:bool) -> void:
	host_kind=Characters.valid_kind(host_kind)
	guest_kind=Characters.valid_kind(guest_kind)
	if host_kind==guest_kind: return
	network_active=true; network_in_match=true; network_is_host=local_is_host
	network_match_over=false; network_result_reported=false; network_result_text=""
	selected=host_kind
	opponent_selected=guest_kind
	wins=[0,0]; playing=true; paused=false; round_delay=0.0; hitstop=0.0
	sim.event_serial=0
	sim.reset(selected,opponent_selected); brain.reset(); clear_inputs(); clear_feedback(); load_characters()
	if lan: lan.discard_guest_input()
	hud.set_local_side(0 if network_is_host else 1)
	hud.start_lan_match_view()
	hud.set_paused(false)
	status_text="第一回合 · 开始！"
	sound_enabled=true
	audio_pool.unlock(); audio_pool.suspend(false)
	ui_serial+=1; audio_pool.play_cue("ui_confirm","ui:"+str(ui_serial))
	layout_camera()

func _network_state() -> Dictionary:
	return {
		"fighters":sim.fighters.duplicate(true),
		"projectiles":sim.projectiles.duplicate(true),
		"events":sim.events.duplicate(true),
		"emitters":emitter_positions.duplicate(true),
		"time_left":sim.time_left,
		"round_over":sim.round_over,
		"winner":sim.winner,
		"elapsed":sim.elapsed,
		"wins":wins.duplicate(),
		"status":status_text,
		"playing":playing,
		"paused":paused,
		"result":network_result_text,
	}

func apply_network_snapshot(state:Dictionary) -> void:
	if not network_active or network_is_host or not network_in_match: return
	var incoming_paused:bool=bool(state.get("paused",false))
	if incoming_paused!=paused:
		paused=incoming_paused
		clear_inputs()
		hud.set_paused(paused)
		audio_pool.suspend(paused)
		if paused: reset_shake()
	sim.fighters=state.get("fighters",sim.fighters)
	sim.projectiles=state.get("projectiles",[])
	sim.time_left=float(state.get("time_left",sim.time_left))
	sim.round_over=bool(state.get("round_over",false))
	sim.winner=int(state.get("winner",-2))
	sim.elapsed=float(state.get("elapsed",sim.elapsed))
	wins=state.get("wins",[0,0])
	status_text=str(state.get("status",status_text))
	var emitters:Variant=state.get("emitters",{})
	if emitters is Dictionary: emitter_positions=emitters
	var was_playing:=playing
	playing=bool(state.get("playing",playing))
	var events:Array=state.get("events",[])
	sim.events=events
	for e:Dictionary in events:
		var event_id:int=int(e.get("event_id",-1))
		if event_id>sim.event_serial: sim.event_serial=event_id
		dispatch_feedback(e)
	sim.events=[]
	if not playing and was_playing:
		network_match_over=true
		hud.show_result(str(state.get("result","胜负已分")))
	elif playing and network_match_over:
		network_match_over=false

func _network_guest_tick(delta:float) -> void:
	if network_in_match and playing and not paused:
		lan.send_input(player_command())
	else:
		player_command()
	if hitstop>0.0:
		hitstop=maxf(0.0,hitstop-delta)

func start_match(kind:int,opponent_kind:int=-1) -> void:
	network_active=false; network_in_match=false; network_is_host=false; network_match_over=false
	selected=Characters.valid_kind(kind)
	opponent_selected=opponent_selection.begin_match(selected,opponent_kind)
	hud.set_opponent_choice(opponent_selection.requested)
	wins=[0,0]; playing=true; paused=false; round_delay=0.0; hitstop=0.0
	sim.reset(selected,opponent_selected); brain.reset(); clear_inputs(); clear_feedback(); load_characters()
	status_text="第一回合 · 开始！"
	hud.set_paused(false)
	sound_enabled=true
	audio_pool.unlock(); audio_pool.suspend(false)
	ui_serial+=1; audio_pool.play_cue("ui_confirm","ui:"+str(ui_serial))
	layout_camera()

func show_menu() -> void:
	playing=false; paused=false; clear_inputs(); hud.show_menu(); status_text="选择角色，开启演出"
	sim.reset(selected,opponent_selected); brain.reset(); round_delay=0; hitstop=0; clear_feedback(); layout_camera()

func toggle_mute() -> void:
	muted=not muted
	hud.set_muted(muted)
	audio_pool.configure(combat_gain,voice_gain,0.5,muted)
	save_feedback_preferences()

func toggle_pause() -> void:
	if not playing: return
	if network_active and not network_is_host:
		lan.request_pause()
		return
	paused=not paused; clear_inputs(); hud.set_paused(paused)
	audio_pool.suspend(paused)
	if paused: reset_shake()

func set_feedback_preferences(new_combat:float,new_voice:float,new_shake:bool) -> void:
	combat_gain=clampf(new_combat,0,1); voice_gain=clampf(new_voice,0,1); shake_enabled=new_shake
	audio_pool.configure(combat_gain,voice_gain,0.5,muted)
	hud.set_feedback_settings(combat_gain,voice_gain,shake_enabled)
	if not shake_enabled: reset_shake()
	save_feedback_preferences()

func set_feedback_settings(a:float,b:float,c:bool) -> void:
	set_feedback_preferences(a,b,c)

func load_feedback_preferences() -> void:
	var cfg:=ConfigFile.new()
	if cfg.load(SETTINGS_PATH)==OK:
		combat_gain=clampf(float(cfg.get_value("feedback","combat",0.85)),0,1)
		voice_gain=clampf(float(cfg.get_value("feedback","voice",1.0)),0,1)
		shake_enabled=bool(cfg.get_value("feedback","shake",true))
		muted=bool(cfg.get_value("feedback","muted",false))
	audio_pool.configure(combat_gain,voice_gain,0.5,muted)
	hud.set_feedback_settings(combat_gain,voice_gain,shake_enabled); hud.set_muted(muted)

func save_feedback_preferences() -> void:
	var cfg:=ConfigFile.new()
	cfg.set_value("feedback","combat",combat_gain); cfg.set_value("feedback","voice",voice_gain)
	cfg.set_value("feedback","shake",shake_enabled); cfg.set_value("feedback","muted",muted)
	cfg.save(SETTINGS_PATH)

func reset_shake() -> void:
	shake_remaining=0.0; shake_offset=Vector2.ZERO
	if camera: camera.h_offset=0.0

func tick_feedback(delta:float) -> void:
	audio_pool.tick(delta)
	if paused or not shake_enabled: reset_shake(); return
	shake_remaining=maxf(0.0,shake_remaining-delta)
	var envelope:float=shake_remaining/0.10
	shake_offset=Vector2(camera.size*0.003*envelope*sin((0.10-shake_remaining)*TAU*38.0),0)
	camera.h_offset=shake_offset.x

func clear_inputs() -> void:
	held.clear(); taps.clear(); keyboard_sources.clear(); touch_sources.clear()
	if sim and sim.has_method("cancel_pending_inputs"): sim.cancel_pending_inputs()

func _merge_command(action:String) -> void:
	var pressed:bool=bool(touch_sources.get(action,false))
	for source_action in keyboard_sources.values():
		if source_action==action: pressed=true
	var was_pressed:bool=bool(held.get(action,false))
	held[action]=pressed
	if pressed and not was_pressed: taps[action]=true

func on_command(action:String, pressed:bool) -> void:
	sound_enabled=true
	touch_sources[action]=pressed
	_merge_command(action)

func _input(event:InputEvent) -> void:
	if not OS.has_feature("web") and not OS.has_feature("mobile") and event is InputEventKey and not event.echo:
		if event.physical_keycode == KEY_F11 or (event.alt_pressed and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]):
			if event.pressed:
				clear_inputs()
				var fullscreen := get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
				get_window().mode = Window.MODE_WINDOWED if fullscreen else Window.MODE_FULLSCREEN
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_ESCAPE:
		if hud and hud.lan_panel_open():
			hud.request_lan_cancel()
			get_viewport().set_input_as_handled()
			return
		if network_active and not network_in_match and not playing:
			_on_menu_requested()
			get_viewport().set_input_as_handled()
			return
	if hud and hud.feedback_settings_open(): return
	if event is InputEventKey and not event.echo:
		if event.physical_keycode in [KEY_F6,KEY_F7,KEY_F10,KEY_F11,KEY_F12] and not OS.is_debug_build(): return
		var action:=""
		match event.physical_keycode:
			KEY_A, KEY_LEFT: action="left"
			KEY_D, KEY_RIGHT: action="right"
			KEY_SPACE, KEY_W, KEY_UP: action="jump"
			KEY_S, KEY_DOWN: action="crouch"
			KEY_J: action="punch"
			KEY_K: action="kick"
			KEY_L: action="heavy"
			KEY_I: action="roundhouse"
			KEY_O: action="special"
			KEY_F6:
				if event.pressed: get_window().size=Vector2i(390,844); layout_camera()
			KEY_F7:
				if event.pressed: get_window().size=Vector2i(375,667); layout_camera()
			KEY_F10:
				if event.pressed: get_window().size=Vector2i(1280,800); layout_camera()
			KEY_F11:
				if event.pressed and OS.is_debug_build():
					start_match(selected,opponent_selected)
					sim.fighters[0].x=-0.65; sim.fighters[1].x=0.65
					taps.kick=true
					screenshot_path="res://exports/native-kick.png"
					screenshot_countdown=0.40
			KEY_F12:
				if event.pressed:
					screenshot_path="res://exports/native-gameplay.png"
					capture.call_deferred()
			KEY_ESCAPE:
				if event.pressed: toggle_pause()
		if action!="":
			sound_enabled=true
			if event.pressed: keyboard_sources[event.physical_keycode]=action
			else: keyboard_sources.erase(event.physical_keycode)
			_merge_command(action)

func _notification(what:int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT or what==NOTIFICATION_APPLICATION_PAUSED:
		clear_inputs()
		if audio_pool: audio_pool.suspend(true)
		reset_shake()
		if network_active and not network_is_host:
			if audio_pool: audio_pool.suspend(paused)
			return
		if playing and not paused:
			paused=true
			if hud: hud.set_paused(true)

func player_command() -> Dictionary:
	var c:Dictionary={"move":float(held.get("right",false))-float(held.get("left",false)),"jump":taps.get("jump",false),"crouch":held.get("crouch",false),"punch":taps.get("punch",false),"kick":taps.get("kick",false),"heavy":taps.get("heavy",false),"roundhouse":taps.get("roundhouse",false),"special":taps.get("special",false)}
	taps.clear()
	return c

func _physics_process(delta:float) -> void:
	if not hud: return
	tick_feedback(delta)
	if network_active and not network_is_host:
		_network_guest_tick(delta)
		render_state(delta)
		return
	if auto_demo and playing:
		demo_elapsed+=delta
		if int(demo_elapsed*2)%3==0: held.right=true; held.left=false
		else: held.right=false
		if int(demo_elapsed*60)%65==0: taps.punch=true
		if int(demo_elapsed*60)%133==0: taps.kick=true
	if playing and not paused:
		if round_delay>0.0:
			if hitstop>0.0: hitstop=maxf(0.0,hitstop-delta)
			else:
				sim.step_post_round(delta)
				for e in sim.events: dispatch_feedback(e)
			round_delay-=delta
			if round_delay<=0.0 and not result_poses_ready(): round_delay=0.001
			if round_delay<=0.0:
				if wins[0]>=2 or wins[1]>=2:
					playing=false
					network_result_text=str(Characters.get_character(sim.fighters[0 if wins[0]>=2 else 1].kind).name)+" · 演出获胜！"
					hud.show_result(network_result_text)
					if network_active and network_is_host and not network_result_reported and lan:
						network_result_reported=true
						lan.report_result("host" if wins[0]>=2 else "guest")
				else:
					sim.reset(selected,opponent_selected); brain.reset(); clear_inputs(); clear_feedback(); layout_camera()
					if network_active: lan.discard_guest_input()
					status_text="平局重赛 · 开始！" if status_text.begins_with("平局") else "下一回合 · 开始！"
		elif hitstop>0.0: hitstop-=delta
		else:
			var opponent_command:Dictionary=lan.consume_guest_command() if network_active else brain.act(sim,delta)
			sim.step(delta,[player_command(),opponent_command])
			for e in sim.events:
				dispatch_feedback(e)
				if e.type=="round":
					if e.winner>=0: wins[e.winner]+=1
					if network_active:
						status_text="平局 · 本回合重赛" if e.winner==-1 else (str(Characters.get_character(sim.fighters[e.winner].kind).name)+" 拿下一局")
					else:
						status_text="平局 · 本回合重赛" if e.winner==-1 else ("你拿下一局！" if e.winner==0 else "对手拿下一局")
					round_delay=2.4; clear_inputs()
					if network_active: lan.discard_guest_input()
	elif network_active and paused and lan:
		lan.discard_guest_input()
	render_state(delta)
	if network_active and network_in_match and network_is_host and lan:
		lan.send_snapshot(_network_state())
	if screenshot_countdown>=0.0:
		screenshot_countdown-=delta
		if screenshot_countdown<0.0: capture.call_deferred()

func result_poses_ready() -> bool:
	for f in sim.fighters:
		if f.y>0.001: return false
		if f.get("down",false):
			if not (f.down_ko and f.down_phase=="hold"): return false
		elif f.land_lock>0.0: return false
	return true

func signature_clip(f: Dictionary) -> String:
	if int(f.kind)==4: return "CakeCast"
	if int(f.kind)==3: return "PeachCast"
	if int(f.kind)==2: return "RifleCast"
	if int(f.kind)==0: return "MeowCast"
	return {"start":"HeartCastStart","air":"HeartCastLoop","land":"HeartCastLand"}.get(f.get("special_phase","start"),"HeartCastStart")

func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var skeleton:=find_skeleton(child)
		if skeleton: return skeleton
	return null

func signature_emitter(index: int, cast_age: float) -> Vector2:
	# Called exactly at the deterministic emit event. Animation supplies ONLY origin,
	# never timing, collision, trajectory, damage or an extra actor-root translation.
	var f: Dictionary=sim.fighters[index]
	var emit_face: int=int(f.get("special_face",f.face))
	var emit_y: float=f.y
	if int(f.kind)==1:
		var air_time: float=clampf(cast_age-0.20,0.0,0.60)
		emit_y=maxf(0.0,5.25*air_time-8.75*air_time*air_time)
	actors[index].position=Vector3(f.x,emit_y,0)
	actors[index].rotation.y=emit_face*PI/2.0
	var phase_time: float=cast_age-0.20 if int(f.kind)==1 else cast_age
	var clip: String=str(Characters.get_character(int(f.kind)).special_clip)+("_R" if emit_face>0 else "_L")
	if anims[index] and anims[index].has_animation(clip):
		anims[index].play(clip,0.0)
		anims[index].seek(phase_time,true)
		anims[index].advance(0.0)
		current_clips[index]=clip
		anims[index].speed_scale=0.0
	var skeleton:=find_skeleton(actors[index])
	var key: String="purple" if int(f.kind)==0 else "yellow"
	var points: Array=marker_config.get(key,{}).get("points",[])
	if int(f.kind)==2: points=[rifle_contract.facing["R" if emit_face>0 else "L"].muzzle_marker]
	if int(f.kind)==3: points=peach_contract.facing["R" if emit_face>0 else "L"].emitter_points
	var origin:=Vector3(f.x+emit_face*0.10,emit_y+(1.65 if int(f.kind)==0 else 2.08),0.0)
	if int(f.kind)==3:
		var fallback:Vector2=Characters.get_character(3).fallback_muzzle
		origin=Vector3(f.x+emit_face*fallback.x,emit_y+fallback.y,0.0)
	if skeleton and not points.is_empty():
		skeleton.force_update_all_bone_transforms()
		origin=Vector3.ZERO
		var count:=0
		for point: Dictionary in points:
			var bone:int=skeleton.find_bone(str(point.bone))
			if bone<0: continue
			var v:Array=point.offset
			origin+=skeleton.to_global(skeleton.get_bone_global_pose(bone)*Vector3(float(v[0]),float(v[1]),float(v[2])))
			count+=1
		if count>0: origin/=float(count)
		else: origin=Vector3(f.x,f.y+1.65,0)
	emitter_positions[index]=origin
	return Vector2(origin.x,origin.y)

func render_state(_delta:float) -> void:
	update_fight_camera(_delta)
	if not paused:
		for effect in effects.duplicate():
			effect.life-=_delta
			if effect.life<=0.0:
				effect.node.queue_free(); effects.erase(effect)
			else:
				var progress:float=1.0-effect.life/effect.duration
				effect.node.scale=Vector3.ONE*(0.65+progress*0.8)
	for i in range(2):
		var f:Dictionary=sim.fighters[i]
		if previous_height[i]>0.001 and f.y<=0.001 and not f.get("down",false): landing_remaining[i]=0.09
		elif not paused and hitstop<=0.0: landing_remaining[i]=maxf(0.0,landing_remaining[i]-_delta)
		previous_height[i]=f.y
		# Presentation never moves a fighter away from its physical arena root.
		actors[i].position=Vector3(f.x,f.y,0)
		actors[i].rotation.y=f.face*PI/2.0
		var clip:="FightIdle" if playing else "Idle"
		var speed:=1.0
		if f.get("down",false):
			clip="Recover" if f.down_phase=="rise" else "Knockdown"
		elif sim.round_over:
			if f.y>0.001: clip="FlyingKickLoop" if f.attack=="kick" else "JumpLoop"
			elif landing_remaining[i]>0.0: clip="FlyingKickLand" if f.attack=="kick" else "JumpLand"
			else: clip="Knockdown" if f.hp<=0 else ("Victory" if sim.winner==i else "FightIdle")
		elif f.stun>0: clip="HitReactStrong" if anims[i] and anims[i].has_animation("HitReactStrong") else "HitReact"
		elif f.attack=="special":
			clip=signature_clip(f)
		elif f.attack in ["punch","straight","heavy"]:
			clip={"punch":"Jab","straight":"Straight","heavy":"HeavyPunch"}[f.attack]
			if not anims[i] or not anims[i].has_animation(clip+("_R" if f.face>0 else "_L")): clip="Punch"
			if anims[i] and anims[i].has_animation(clip): speed=anims[i].get_animation(clip).length/f.duration
		elif f.attack=="roundhouse":
			clip="RoundhouseKick"
			# Diagnostic branch only until the isolated 59-clip asset gate.
			if not anims[i] or not anims[i].has_animation(clip+("_R" if f.face>0 else "_L")): clip="FightIdle"
		elif f.attack=="kick":
			clip="FlyingKickStart" if f.clock<0.23 else ("FlyingKickLoop" if f.y>0.04 else "FlyingKickLand")
		elif f.y>0.02: clip="JumpStart" if f.vy>4.0 else "JumpLoop"
		elif landing_remaining[i]>0.0: clip="JumpLand"
		elif float(f.get("crouch_amount",0.0))>0.0:
			clip="CrouchLoop" if float(f.crouch_amount)>=1.0 else ("CrouchStart" if bool(f.get("crouching",false)) else "CrouchEnd")
		elif f.blocking:
			clip="BackstepGuard" if absf(f.x)<2.099 else "Guard"
			speed=absf(f.vx)/float(Characters.get_character(f.kind).backstep_speed) if clip=="BackstepGuard" else 1.0
		elif absf(f.vx)>0.15:
			clip="Run"; speed=absf(f.vx)/float(Characters.get_character(f.kind).run_speed)
			if f.move*f.face<0: speed=-speed
		var base_clip:String=clip
		if anims[i]:
			var variant:String=clip+("_R" if f.face>0 else "_L")
			if clip!="Idle" and anims[i].has_animation(variant): clip=variant
			if not anims[i].has_animation(clip): clip="Idle"
			if current_clips[i]!=clip or (f.attack!="" and rendered_attack_ids[i]!=f.attack_id):
				var old_base:String=String(current_clips[i]).trim_suffix("_R").trim_suffix("_L")
				var changing_side:bool=rendered_faces[i]!=f.face
				var old_time:float=anims[i].current_animation_position if anims[i].is_playing() else 0.0
				# Do not blend a camera-open R pose through its back after the physical root flips to L.
				anims[i].play(clip,0.0 if changing_side or f.stun>0 or f.get("down",false) or f.attack=="special" or base_clip.begins_with("Crouch") else 0.10,1.0,speed<0)
				if changing_side and old_base==base_clip: anims[i].seek(minf(old_time,anims[i].get_animation(clip).length),true)
				rendered_attack_ids[i]=f.attack_id
				current_clips[i]=clip
			rendered_faces[i]=f.face
			anims[i].speed_scale=0.0 if paused or hitstop>0.0 else speed
			if not paused and hitstop<=0.0: anims[i].advance(0.0 if f.attack=="special" or base_clip.begins_with("Crouch") else _delta)
			if f.get("down",false):
				var down_time:float=f.down_clock
				if f.down_phase=="air": down_time=minf(sim.DOWN_AIR_LOSS_END,maxf(0.04,down_time))
				elif f.down_phase=="fall": down_time=maxf(0.04,down_time)
				elif f.down_phase=="hold": down_time=sim.DOWN_FALL_DURATION
				var down_length:float=anims[i].get_animation(clip).length
				var expected:float=sim.DOWN_RISE_DURATION if f.down_phase=="rise" else sim.DOWN_FALL_DURATION
				anims[i].seek(clampf(down_time/expected*down_length,0.0,down_length),true)
				anims[i].speed_scale=0.0
			if (landing_remaining[i]>0.0 and base_clip in ["JumpLand","FlyingKickLand"] and f.attack=="") or (sim.round_over and landing_remaining[i]>0.0 and not f.get("down",false)):
				var land_length:float=anims[i].get_animation(clip).length
				anims[i].seek(clampf(1.0-landing_remaining[i]/0.09,0.0,1.0)*land_length,true)
				anims[i].speed_scale=0.0
			if base_clip.begins_with("Crouch"):
				var crouch_length:float=anims[i].get_animation(clip).length
				var amount:float=clampf(float(f.get("crouch_amount",0.0)),0.0,1.0)
				var crouch_time:float=fmod(sim.elapsed,crouch_length) if base_clip=="CrouchLoop" else (amount if base_clip=="CrouchStart" else 1.0-amount)*crouch_length
				anims[i].seek(crouch_time,true);anims[i].speed_scale=0.0
			# Recoil is visible immediately and completes inside existing stun, never delayed by blending.
			if f.stun>0.0 and not sim.round_over and not f.get("down",false):
				var hurt_length:float=anims[i].get_animation(clip).length
				var hurt_time:float=0.04+(hurt_length-0.04)*clampf(f.hit_age/maxf(0.01,f.stun_duration),0.0,1.0)
				anims[i].seek(hurt_time,true); anims[i].speed_scale=0.0
			# Attack poses follow the simulation clock, not variable render frame time.
			if f.attack!="" and not sim.round_over:
				var pose_time:float=f.clock
				var length:float=anims[i].get_animation(clip).length
				if f.attack=="special": pose_time=float(f.get("special_phase_clock",f.clock))
				elif base_clip in ["Punch","Jab","Straight","HeavyPunch","RoundhouseKick"]: pose_time=f.clock/f.duration*length
				elif base_clip=="FlyingKickStart": pose_time=f.clock/0.23*length
				elif base_clip=="FlyingKickLoop": pose_time=f.clock-0.23
				elif base_clip=="FlyingKickLand": pose_time=f.clock-0.525
				anims[i].seek(clampf(pose_time,0.0,length),true)
				anims[i].speed_scale=0.0
		update_rifle(i)
	if projectile_view:
		projectile_view.sync_projectiles(sim.projectiles)
		projectile_view.sync_cake_warnings(sim.cake_warnings())
	var a:Dictionary=sim.fighters[0];var b:Dictionary=sim.fighters[1]
	var hud_status:String=status_text if sim.elapsed<2.0 or sim.round_over else "后退防守 · 留意防御槽"
	if not sim.round_over:
		if a.get("down",false): hud_status="倒地中 · 起身后短暂保护"
		elif b.get("down",false): hud_status="飞踢击倒 · 倒地无法追打"
	var suffix0:String=""
	var suffix1:String=" AI"
	if network_active:
		suffix0="（你）" if network_is_host else "（对手）"
		suffix1="（对手）" if network_is_host else "（你）"
	hud.set_match({"special_kind":a.kind,"special_cd":a.get("special_cooldown",0.0),"special_kind0":a.kind,"special_cd0":a.get("special_cooldown",0.0),"special_kind1":b.kind,"special_cd1":b.get("special_cooldown",0.0),"hp0":a.hp,"hp1":b.hp,"guard0":a.guard,"guard1":b.guard,"wins0":wins[0],"wins1":wins[1],"time":ceili(sim.time_left),"status":hud_status,"kinds":[a.kind,b.kind],"names":[str(Characters.get_character(a.kind).name)+suffix0,str(Characters.get_character(b.kind).name)+suffix1]})

func clear_feedback() -> void:
	for prop in rifle_props:
		if is_instance_valid(prop): prop.hide()
	for effect in effects:
		if is_instance_valid(effect.node): effect.node.queue_free()
	effects.clear()
	if projectile_view: projectile_view.clear()
	if audio_pool: audio_pool.clear()
	feedback_floor=sim.event_serial; feedback_watermark=feedback_floor; feedback_seen.clear(); feedback_history.clear(); reset_shake()
	emitter_positions.clear()
	projectile_audio_kinds.clear()
	last_feedback=""; landing_remaining=[0.0,0.0]; previous_height=[0.0,0.0]

func spawn_hit(index:int,blocked:bool,strong:bool=false,low_contact:bool=false,world_contact_y:float=-1.0,world_contact_x:float=NAN) -> void:
	var flash:=Node3D.new(); world.add_child(flash)
	var f:Dictionary=sim.fighters[index]
	var incoming:float=signf(sim.fighters[1-index].x-f.x)
	flash.position=Vector3(world_contact_x if is_finite(world_contact_x) else f.x+incoming*0.27,world_contact_y if world_contact_y>=0.0 else f.y+(0.65 if low_contact else 1.30),0.36)
	var mat:=StandardMaterial3D.new(); mat.albedo_color=Color("8bd6ff") if blocked else Color("ffe5a4"); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var radius:float=0.085 if blocked else (0.16 if strong else 0.12)
	for j in range(4 if blocked else 6):
		var ray:=MeshInstance3D.new(); var mesh:=BoxMesh.new()
		mesh.size=Vector3(radius*0.55,0.022,0.016); ray.mesh=mesh; ray.material_override=mat
		var angle:float=float(j)*TAU/(4.0 if blocked else 6.0)
		ray.position=Vector3(cos(angle)*radius,sin(angle)*radius,0); ray.rotation.z=angle; flash.add_child(ray)
	var duration:float=0.11 if blocked else 0.16
	effects.append({"node":flash,"life":duration,"duration":duration})

func spawn_muzzle_flash(origin:Vector3) -> void:
	var flash:=MeshInstance3D.new();var shape:=SphereMesh.new()
	shape.radius=0.055;shape.height=0.11;flash.mesh=shape
	var material:=StandardMaterial3D.new();material.albedo_color=Color("ffeab3")
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;flash.material_override=material
	world.add_child(flash);flash.position=origin
	effects.append({"node":flash,"life":0.055,"duration":0.055})

func dispatch_feedback(e:Dictionary) -> bool:
	var id:int=int(e.get("event_id",-1))
	if id<=feedback_watermark or id<=feedback_floor or feedback_seen.has(id): return false
	feedback_watermark=id
	feedback_seen[id]=true
	if feedback_seen.size()>512: feedback_seen.erase(feedback_seen.keys()[0])
	var kind:String=str(e.get("kind","")); var cue:=""; var stop:=0.0; var shake:=false
	if e.type=="attack" and kind=="special" and int(sim.fighters[int(e.fighter)].kind)==4:
		cue="cake_warn"
	elif e.type=="projectile_spawn":
		projectile_audio_kinds[int(e.id)]=kind
		var origin:Vector3=Vector3(e.pos.x,e.pos.y,0) if kind=="cake" else emitter_positions.get(e.fighter,Vector3(e.pos.x,e.pos.y,0))
		projectile_view.note_emission(e.id,origin.z)
		if kind=="rifle": spawn_muzzle_flash(origin)
		cue={"rifle":"rifle_emit","meow":"meow","heart":"heart_emit","peach":"peach_emit","cake":"cake_drop"}.get(kind,"")
	elif e.type=="projectile_despawn":
		var projectile_kind:String=projectile_audio_kinds.get(int(e.id),"")
		projectile_audio_kinds.erase(int(e.id))
		if projectile_kind=="cake" and e.get("reason","")=="boundary" and absf(float(e.pos.y))<0.001:
			cue="cake_land"
	elif e.type=="swing": cue="swing_kick" if kind in ["kick","roundhouse"] else "swing_punch"
	elif e.type in ["hit","break","block"]:
		var blocked:bool=e.type=="block"
		stop=0.025 if blocked else (0.095 if kind=="heavy" else (0.075 if kind in ["kick","roundhouse"] else (0.065 if kind=="straight" else 0.055)))
		hitstop=maxf(hitstop,stop); last_feedback=e.type+":"+kind
		cue="block" if blocked else ("guard_break" if e.type=="break" else {"punch":"hit_light","straight":"hit_straight","heavy":"hit_heavy","kick":"hit_kick","roundhouse":"hit_kick","meow":"hit_straight","heart":"heart_hit","rifle":"hit_straight","peach":"peach_hit","cake":"cake_land"}.get(kind,"hit_light"))
		spawn_hit(e.fighter,blocked,kind in ["kick","heavy","roundhouse"],kind=="kick",float(e.get("impact_y",-1)),float(e.get("impact_x",NAN)))
		shake=not blocked and (kind=="heavy" or bool(e.get("ko",false))) and shake_enabled
		if shake: shake_remaining=0.10
		if bool(e.get("ko",false)) and sound_enabled: audio_pool.play_cue("ko",str(id))
	elif e.type=="jump": cue="jump"
	elif e.type=="land" and not e.get("down",false): cue="land"
	elif e.type=="down_land": cue="down_land"
	if not cue.is_empty() and sound_enabled: audio_pool.play_cue(cue,str(id))
	feedback_history.append({"event_id":id,"type":e.type,"kind":kind,"cue":cue,"impact_x":e.get("impact_x",NAN),"impact_y":e.get("impact_y",NAN),"hitstop":stop,"shake":shake})
	if feedback_history.size()>256: feedback_history.pop_front()
	return true

func capture() -> void:
	await RenderingServer.frame_post_draw
	var img:=get_viewport().get_texture().get_image()
	print("SCREENSHOT ",screenshot_path," result=",img.save_png(screenshot_path))
	if screenshot_countdown<0.0 and auto_demo: get_tree().quit()
