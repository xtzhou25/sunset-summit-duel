extends Node
var game
var initial_hashes:Dictionary={}
var pair_captures:Dictionary={}
var capture_records:Array=[]
var initial_stage_nodes:=0
var rendered_frames:=0
var clip_counts:Dictionary={}
var started:int
var frame:=0
var samples:Array=[]
var errors:Array=[]
var round_count:=0
var match_count:=0
var menu_cycles:=0
var focus_cycles:=0
var pause_cycles:=0
var previous_over:=false
var last_second:=-1
var last_usec:=0
var frame_intervals:Array=[]
var duration:=180.0
var pair_index:=-1
var pairs:Array=[[0, 1], [0, 2], [0, 3], [0, 4], [1, 0], [1, 2], [1, 3], [1, 4], [2, 0], [2, 1], [2, 3], [2, 4], [3, 0], [3, 1], [3, 2], [3, 4], [4, 0], [4, 1], [4, 2], [4, 3]]
var pairs_seen:Array=[]
var rifle_emissions:=0
var peach_emissions:=0
var cake_emissions:=0
var rifle_visible_frames:=0
var output:="res://exports/qa-random-audio/native180.json"
var peaks:Dictionary={}
var event_types:Dictionary={}
var resumed_check:=false
var last_event_id:=0

func _ready() -> void:
	RenderingServer.frame_post_draw.connect(_frame_drawn)
	call_deferred("run")

func _frame_drawn() -> void:
	rendered_frames+=1
func check(ok:bool,label:String) -> void:
	if not ok and not errors.has(label): errors.append(label);printerr("FAIL ",label)
func snapshot(elapsed:float) -> Dictionary:
	var active:=0
	for slot in game.audio_pool.slots:
		if slot.active: active+=1
	var row={"audience_nodes":count_descendants(game.stage.audience),"audience_band_top":game.stage.audience.band_top,"audience_band_bottom":game.stage.audience.band_bottom,"far_layer_x":game.stage.far_layer.position.x,"back_layer_x":game.stage.back_layer.position.x,"camera_x":game.camera.position.x,"camera_width":game.camera.size,"fighter_separation":absf(game.sim.fighters[0].x-game.sim.fighters[1].x),"stage_nodes":count_descendants(game.stage),"elapsed":elapsed,"frames":frame,"rendered_frames":rendered_frames,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"fps":Engine.get_frames_per_second(),"static_memory":OS.get_static_memory_usage(),"nodes":get_tree().get_node_count(),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"voices":game.audio_pool.players.size(),"active_voices":active,"effects":game.effects.size(),"projectiles":game.sim.projectiles.size(),"projectile_views":game.projectile_view.views.size(),"projectile_depths":game.projectile_view.depths.size(),"feedback_history":game.feedback_history.size(),"feedback_seen":game.feedback_seen.size(),"audio_seen":game.audio_pool._seen.size(),"audio_log":game.audio_pool.played_log.size(),"audio_rejected":game.audio_pool.rejected_log.size(),"ai_snapshots":game.brain.snapshots.size(),"rounds":round_count,"matches":match_count,"physics_process_seconds":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)}
	for key in row:
		if key!="elapsed": peaks[key]=maxf(float(peaks.get(key,0)),float(row[key]))
	return row
func count_descendants(node:Node) -> int:
	var total:=1
	for child in node.get_children(): total+=count_descendants(child)
	return total
func runtime_hashes() -> Dictionary:
	var hashes:Dictionary={}
	for name in ["opponent_selection.gd","combat_audio.gd","main.gd","combat.gd","ai.gd","fight_camera.gd","stage.gd","hud.gd","audience.gd","stage_audience.gd"]:
		var path:String="res://scripts/"+name
		if FileAccess.file_exists(path): hashes[name]=FileAccess.get_sha256(path)
	for relative in ["stage-art/expanded_livehouse.gd","stage-art/fan_band.gd"]:
		var path:String="res://"+relative
		if FileAccess.file_exists(path):hashes[relative]=FileAccess.get_sha256(path)
	return hashes
func capture_pair(pair:Array,index:int) -> void:
	await RenderingServer.frame_post_draw
	var image:Image=get_viewport().get_texture().get_image()
	var path:String="res://exports/qa-random-audio/native-pair-%02d-%d-%d.png"%[index,pair[0],pair[1]]
	var result:int=image.save_png(path)
	capture_records.append({"pair":pair,"path":path,"save_error":result,"dimensions":str(image.get_size()),"elapsed":float(Time.get_ticks_usec()-started)/1000000.0,"camera_x":game.camera.position.x,"camera_width":game.camera.size})
	check(result==OK,"native pair PNG saved")
func run() -> void:
	initial_hashes=runtime_hashes()
	DirAccess.make_dir_recursive_absolute("res://exports/qa-random-audio")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--seconds="): duration=float(arg.trim_prefix("--seconds="))
	get_tree().root.size=Vector2i(960,600)
	game=load("res://main.tscn").instantiate();add_child(game)
	await get_tree().process_frame
	game.set_physics_process(false);game.hud._choose(0);game.brain.rng.seed=45861
	started=Time.get_ticks_usec();last_usec=started
	initial_stage_nodes=count_descendants(game.stage)
	print("SOAK_START ",output," duration=",duration," display=",DisplayServer.get_name())
	while true:
		await get_tree().physics_frame
		var now:=Time.get_ticks_usec()
		var elapsed:=float(now-started)/1000000.0
		frame_intervals.append(float(now-last_usec)/1000.0);last_usec=now
		if elapsed>=duration: break
		var next_pair:=mini(19,int(elapsed/(duration/20.0)))
		if next_pair!=pair_index:
			game.show_menu();menu_cycles+=1
			check_cleanup("pair transition")
			pair_index=next_pair;pairs_seen.append(pairs[pair_index])
			game.hud.opponent_choice=pairs[pair_index][1];game.hud._choose(pairs[pair_index][0])
			check(game.loaded_pair==pairs[pair_index],"selected pair exact")
		if not game.playing:
			match_count+=1;game.hud._request_rematch()
		var cycle:int=frame%1800
		if cycle==600:
			print("PAUSE_BEFORE frame=",frame," playing=",game.playing," paused=",game.paused," suspended=",game.audio_pool.is_suspended)
			game.on_command("left",true);game.on_command("heavy",true);game.toggle_pause();pause_cycles+=1
			print("PAUSE_AFTER frame=",frame," playing=",game.playing," paused=",game.paused," suspended=",game.audio_pool.is_suspended," held=",game.held," taps=",game.taps)
			check(game.held.is_empty() and game.taps.is_empty() and game.audio_pool.is_suspended,"pause clears input and suspends audio")
		if cycle==630:
			if game.paused: game.toggle_pause()
			resumed_check=true
		if cycle==1200:
			game.on_command("right",true);game.on_command("jump",true)
			game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);focus_cycles+=1
			check(game.paused and game.held.is_empty() and game.touch_sources.is_empty() and game.keyboard_sources.is_empty() and game.audio_pool.is_suspended,"focus loss clears sources and suspends")
		if cycle==1230:
			if game.paused: game.toggle_pause()
			resumed_check=true
		if not game.paused:
			var f:Dictionary=game.sim.fighters[0];var other:Dictionary=game.sim.fighters[1]
			var distance:float=absf(other.x-f.x)
			var retreat:bool=(frame/180)%4==1
			game.on_command("left",(other.x<f.x) != retreat and distance>0.65)
			game.on_command("right",(other.x>f.x) != retreat and distance>0.65)
			game.on_command("jump",frame%227==10)
			game.on_command("crouch",frame%181>=145 and frame%181<160)
			game.on_command("punch",frame%47==0 or (f.attack=="punch" and f.duration-f.clock<=0.09 and f.duration-f.clock>0.06))
			game.on_command("heavy",frame%137==43)
			game.on_command("roundhouse",frame%113==50)
			game.on_command("kick",frame%157==0)
			game.on_command("special",frame%269==0)
			if resumed_check:
				check(not game.audio_pool.is_suspended,"resume enables current audio events");resumed_check=false
		game._physics_process(1.0/60.0)
		for clip in game.current_clips:
			clip_counts[clip]=int(clip_counts.get(clip,0))+1
		for e in game.sim.events:
			if int(e.event_id)>last_event_id:
				if e.type=="projectile_spawn" and e.get("kind","")=="rifle": rifle_emissions+=1
				if e.type=="projectile_spawn" and e.get("kind","")=="peach": peach_emissions+=1
				if e.type=="projectile_spawn" and e.get("kind","")=="cake": cake_emissions+=1
				event_types[e.type]=int(event_types.get(e.type,0))+1;last_event_id=int(e.event_id)
		if game.sim.round_over and not previous_over: round_count+=1
		previous_over=game.sim.round_over
		check(game.audio_pool.players.size()==10,"audio players remain exactly ten")
		check(game.feedback_history.size()<=256 and game.feedback_seen.size()<=512,"feedback histories bounded")
		check(game.audio_pool.played_log.size()<=64 and game.audio_pool.rejected_log.size()<=64,"audio logs bounded")
		check(game.sim.projectiles.size()<=4 and game.projectile_view.views.size()<=4 and game.projectile_view.depths.size()<=4,"projectiles and views bounded")
		check(game.effects.size()<=16,"contact effects bounded")
		for f in game.sim.fighters:
			check(f.x>=game.sim.LEFT-.000001 and f.x<=game.sim.RIGHT+.000001 and f.y>=0 and f.hp>=0 and f.hp<=100,"fighter bounds valid")
		for i in range(2):
			if game.rifle_props[i].visible:
				rifle_visible_frames+=1
				check(game.sim.fighters[i].kind==2 and game.sim.fighters[i].attack=="special","rifle only during Qi cast")
		check(game.model_cache.size()<=5,"five model cache cap")
		check(absf(game.sim.fighters[0].x-game.sim.fighters[1].x)<=game.sim.SEPARATION_MAX+.00001,"live shared-window maximum")
		check(count_descendants(game.stage)==initial_stage_nodes,"stage art nodes remain bounded and unchanged")
		check(is_finite(game.camera.position.x) and is_finite(game.camera.size),"camera finite")
		if not pair_captures.has(pair_index) and elapsed-float(pair_index)*(duration/20.0)>=duration/40.0:
			pair_captures[pair_index]=true
			capture_pair.call_deferred(pairs[pair_index].duplicate(),pair_index)
		var sec:=int(elapsed)
		if sec!=last_second:
			last_second=sec
			var row=snapshot(elapsed);samples.append(row)
			if sec%60==0: print("SOAK_SAMPLE ",JSON.stringify(row))
		frame+=1
	game.show_menu();check_cleanup("final menu")
	if duration>=180: check(pairs_seen.size()==20,"all twenty pairs covered")
	if duration>=180: check(rifle_emissions>0 and rifle_visible_frames>0,"rifle actually emitted and displayed by state")
	if duration>=180: check(peach_emissions>0,"peach actually emitted")
	if duration>=180: check(cake_emissions>0,"cake actually emitted")
	check(DisplayServer.get_name()!="headless" and rendered_frames>0,"native renderer produced frames")
	check(initial_hashes==runtime_hashes(),"runtime source unchanged throughout native soak")
	if duration>=180: check(capture_records.size()==20,"all twenty pair native PNGs captured")
	frame_intervals.sort()
	var report={"source_hashes":initial_hashes,"ending_source_hashes":runtime_hashes(),"native_pair_captures":capture_records,"stage_initial_nodes":initial_stage_nodes,"timing_note":"Includes 20 finite PNG capture/write frames; this is a native stability/rendering sample, not isolated GPU benchmark.","status":"pass" if errors.is_empty() else "fail","mode":"real-time native graphical full-main scene at 60Hz, scripted ordinary player inputs; rendered-frame callbacks counted; not browser or physical phone","wall_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"display":DisplayServer.get_name(),"rendered_frames":rendered_frames,"clip_counts":clip_counts,"physics_frames":frame,"physics_interval_ms_p50":frame_intervals[int(frame_intervals.size()*0.5)],"physics_interval_ms_p95":frame_intervals[int(frame_intervals.size()*0.95)],"physics_interval_ms_p99":frame_intervals[int(frame_intervals.size()*0.99)],"errors":errors,"pause_cycles":pause_cycles,"focus_cycles":focus_cycles,"menu_cycles":menu_cycles,"rounds":round_count,"matches":match_count,"events":event_types,"peaks":peaks,"samples":samples,"audio_counts":game.audio_pool.counts.duplicate(true),"pairs":pairs_seen,"cake_emissions":cake_emissions,"ha_sha256":FileAccess.get_sha256("res://assets/ha.glb"),"peach_emissions":peach_emissions,"tao_sha256":FileAccess.get_sha256("res://assets/tao.glb"),"rifle_emissions":rifle_emissions,"rifle_visible_frames":rifle_visible_frames,"qi_sha256":FileAccess.get_sha256("res://assets/qi.glb"),"limits":"No GPU benchmark, phone hardware, low-power mode, browser address-bar or audible-output certification. Notifications are explicit application callbacks, not physical OS app-switch tests."}
	var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("SOAK_DONE ",report.status," wall_seconds=",report.wall_seconds," frames=",frame," errors=",errors)
	game.queue_free();await get_tree().process_frame;get_tree().quit(0 if errors.is_empty() else 1)

func check_cleanup(label:String) -> void:
	check(game.sim.projectiles.is_empty() and game.projectile_view.views.is_empty() and game.projectile_view.depths.is_empty() and game.effects.is_empty(),label+" projectile and effect cleanup")
	for prop in game.rifle_props: check(not prop.visible,label+" rifles hidden")
