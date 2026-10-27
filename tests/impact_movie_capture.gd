extends SceneTree
## Native MovieWriter proof, not a slideshow or offline mixed soundtrack.
## Run in a real root window (not --headless):
## godot --path . --script tests/impact_movie_capture.gd --write-movie output.avi --fixed-fps 60 --disable-vsync -- --telemetry=output.json
## Every scenario is explicitly a controlled fixture. Only initial position,
## guard and the labelled final KO health are assigned. Commands use fresh
## on_command edges, and main keeps its automatic 60 Hz physics callback.
## No calls to main._physics_process, sim.step, AnimationPlayer.advance or seek.
const Combat = preload("res://scripts/combat.gd")
const FPS := 60
const FRAMES_PER_SCENARIO := 120
const SCENARIOS := [
	{"title":"JAB HIT", "kind":0, "face":1, "move":"punch", "outcome":"hit"},
	{"title":"JAB BLOCK", "kind":0, "face":1, "move":"punch", "outcome":"block"},
	{"title":"JAB WHIFF", "kind":0, "face":1, "move":"punch", "outcome":"miss"},
	{"title":"JAB TO STRAIGHT", "kind":1, "face":-1, "move":"straight", "outcome":"hit"},
	{"title":"HEAVY HIT", "kind":0, "face":-1, "move":"heavy", "outcome":"hit"},
	{"title":"HEAVY BLOCK", "kind":1, "face":1, "move":"heavy", "outcome":"block"},
	{"title":"FLYING KICK", "kind":0, "face":1, "move":"kick", "outcome":"hit"},
	{"title":"ROUNDHOUSE", "kind":1, "face":-1, "move":"roundhouse", "outcome":"hit"},
	{"title":"MEOW HIT", "kind":0, "face":1, "move":"special", "outcome":"hit"},
	{"title":"MEOW BLOCK", "kind":0, "face":-1, "move":"special", "outcome":"block"},
	{"title":"HEART HIT", "kind":1, "face":1, "move":"special", "outcome":"hit"},
	{"title":"HEART BLOCK", "kind":1, "face":-1, "move":"special", "outcome":"block"},
	{"title":"MUTED HEAVY", "kind":0, "face":1, "move":"heavy", "outcome":"hit", "muted":true},
	{"title":"SHAKE OFF", "kind":1, "face":-1, "move":"heavy", "outcome":"hit", "shake":false},
	{"title":"KO FIXTURE", "kind":0, "face":1, "move":"heavy", "outcome":"hit", "ko":true},
]

class FixtureBrain extends RefCounted:
	var command: Dictionary = {}
	func reset() -> void: command.clear()
	func act(_sim, _delta: float) -> Dictionary: return command.duplicate()

class BeforeMain extends Node:
	var director
	func _physics_process(delta: float) -> void: director.before_main(delta)

class AfterMain extends Node:
	var director
	func _physics_process(delta: float) -> void: director.after_main(delta)

var game
var robot := FixtureBrain.new()
var frame := 0
var scenario_index := -1
var frame_in_scenario := 0
var queued_straight := false
var released_straight := false
var caption: Label
var settings_stills := ""
var telemetry_path := "res://exports/impact-movie-telemetry.json"
var telemetry: Dictionary = {"capture":"native_root_window_movie_writer", "fps":FPS, "target_seconds":30,
	"clock":"one automatic main physics tick per fixed engine frame; native AudioServer mixer", "controlled_fixtures":true,
	"no_offline_audio":true, "scenario_results":[], "physics_frames":0, "delta_errors":0}
var current_result: Dictionary = {}
var event_keys: Dictionary = {}
var audio_seen: Dictionary = {}
var finished := false
var before_elapsed := 0.0
var observed_frame := -1

func _initialize() -> void:
	call_deferred("run_movie")

func run_movie() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--telemetry="): telemetry_path = arg.trim_prefix("--telemetry=")
		if arg.begins_with("--settings-stills="): settings_stills = arg.trim_prefix("--settings-stills=")
	Engine.physics_ticks_per_second = FPS
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	game = load("res://main.tscn").instantiate()
	game.set_physics_process(false)
	root.add_child(game)
	game.auto_demo = false
	game.brain = robot
	if not settings_stills.is_empty():
		capture_settings_stills.call_deferred()
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var panel := Panel.new()
	panel.position = Vector2(24,104)
	panel.size = Vector2(1232,74)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035,0.045,0.08,0.90)
	background.corner_radius_top_left = 12; background.corner_radius_top_right = 12
	background.corner_radius_bottom_left = 12; background.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel",background)
	layer.add_child(panel)
	caption = Label.new()
	caption.position = Vector2(16,8); caption.size = Vector2(1200,58)
	caption.add_theme_font_override("font",game.hud._ui_font)
	caption.add_theme_font_size_override("font_size",21)
	caption.add_theme_color_override("font_color",Color("f8e9bd"))
	panel.add_child(caption)
	var before := BeforeMain.new()
	before.director = self; before.process_physics_priority = -100
	root.add_child(before)
	var after := AfterMain.new()
	after.director = self; after.process_physics_priority = 100
	root.add_child(after)
	game.process_physics_priority = 0
	game.set_physics_process(true)
	print("IMPACT MOVIE START: 1800 automatic physics frames / 30 seconds / native engine audio")

func has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.name) == property_name: return true
	return false

func pool_records() -> Array:
	if not has_property(game,"audio_pool") or not game.audio_pool: return []
	for property_name in ["played_log"]:
		if has_property(game.audio_pool,property_name): return game.audio_pool.get(property_name)
	return []

func start_scenario(index: int) -> void:
	scenario_index = index
	var fixture: Dictionary = SCENARIOS[index]
	game.hud._choose(int(fixture.kind))
	game.brain = robot; robot.reset()
	game.sound_enabled = true
	if game.muted: game.toggle_mute()
	if bool(fixture.get("muted",false)): game.toggle_mute()
	if game.has_method("set_feedback_preferences"):
		game.set_feedback_preferences(1.0,1.0,bool(fixture.get("shake",true)))
	elif game.hud.has_signal("feedback_settings_changed"):
		game.hud.feedback_settings_changed.emit(1.0,1.0,bool(fixture.get("shake",true)))
	var face: int = int(fixture.face)
	# Wall fixture makes guard contact deterministic without defender teleports.
	var target_x: float = Combat.RIGHT if face > 0 else Combat.LEFT
	game.sim.fighters[1].x = target_x
	game.sim.fighters[0].x = target_x - float(face) * (2.0 if fixture.move == "special" else 0.70)
	if fixture.outcome == "miss": game.sim.fighters[0].x = -target_x
	game.sim.fighters[0].face = face; game.sim.fighters[1].face = -face
	if fixture.outcome == "block": robot.command = {"move":float(face)}
	if bool(fixture.get("ko",false)):
		# Labelled KO fixture: exact initial heavy damage, never mid-attack edits.
		game.sim.fighters[1].hp = 16.0
	game.render_state(0.0)
	queued_straight = false; released_straight = false
	event_keys.clear()
	audio_seen.clear()
	for record: Dictionary in pool_records(): audio_seen[str(record)] = true
	current_result = {"title":fixture.title, "fixture":fixture.duplicate(true), "start_frame":frame,
		"physics_frames":0, "events":[], "event_counts":{}, "cue_counts":{}, "audio_records":[],
		"max_hitstop":0.0, "max_effects":0, "max_camera_shift_px":0.0, "camera_zoom_changed":false,
		"camera_size":game.camera.size, "hud_transform":str(game.hud._root.get_global_transform()),
		"hud_moved":false, "main_ticks_observed":0, "peak_audio_active":0, "peak_audio_groups":{"combat":0,"voice":0,"ui":0}}
	caption.text = "%02d / %02d   %s\nCONTROLLED INITIAL POSITIONS  |  Native 60 Hz  |  %s" % [index+1,SCENARIOS.size(),fixture.title,"MUTED" if game.muted else "NATIVE ENGINE AUDIO"]
	print("IMPACT MOVIE SCENARIO ",index+1," ",fixture.title)

func before_main(delta: float) -> void:
	if finished: return
	if frame >= SCENARIOS.size() * FRAMES_PER_SCENARIO:
		finish_movie.call_deferred()
		finished = true
		game.set_physics_process(false)
		return
	frame_in_scenario = frame % FRAMES_PER_SCENARIO
	if frame_in_scenario == 0: start_scenario(frame / FRAMES_PER_SCENARIO)
	if absf(delta - 1.0 / FPS) > 0.000001: telemetry.delta_errors += 1
	var fixture: Dictionary = SCENARIOS[scenario_index]
	var action: String = "punch" if fixture.move == "straight" else str(fixture.move)
	if frame_in_scenario == 18: game.on_command(action,true)
	if frame_in_scenario == 19: game.on_command(action,false)
	if fixture.move == "straight":
		var fighter: Dictionary = game.sim.fighters[0]
		if not queued_straight and fighter.attack == "punch" and game.hitstop <= 0.0 and fighter.clock >= fighter.duration - Combat.PUNCH_BUFFER_WINDOW:
			game.on_command("punch",true); queued_straight = true
		elif queued_straight and not released_straight:
			game.on_command("punch",false); released_straight = true
	before_elapsed = game.sim.elapsed

func after_main(_delta: float) -> void:
	if finished: return
	if observed_frame == frame:
		printerr("MOVIE INVALID: duplicate observer frame ",frame)
		telemetry.delta_errors += 1
	observed_frame = frame
	current_result.physics_frames += 1
	current_result.main_ticks_observed += 1
	current_result.max_hitstop = maxf(float(current_result.max_hitstop),float(game.hitstop))
	current_result.max_effects = maxi(int(current_result.max_effects),game.effects.size())
	current_result.camera_zoom_changed = current_result.camera_zoom_changed or not is_equal_approx(game.camera.size,float(current_result.camera_size))
	current_result.hud_moved = current_result.hud_moved or str(game.hud._root.get_global_transform()) != str(current_result.hud_transform)
	if has_property(game,"shake_offset"):
		var offset = game.get("shake_offset")
		if offset is Vector2: current_result.max_camera_shift_px = maxf(float(current_result.max_camera_shift_px),offset.length()*1280.0/maxf(game.camera.size,0.001))
	for event: Dictionary in game.sim.events:
		var key: String = str(event.get("event_id",str(event)))
		if event_keys.has(key): continue
		event_keys[key] = true
		var copy := event.duplicate(true)
		copy["movie_frame"] = frame
		current_result.events.append(copy)
		var name: String = str(event.type) + ":" + str(event.get("kind",""))
		current_result.event_counts[name] = int(current_result.event_counts.get(name,0)) + 1
	var audio_diag: Dictionary = game.audio_pool.diagnostics()
	current_result.peak_audio_active = maxi(int(current_result.peak_audio_active),int(audio_diag.active_count))
	for group in ["combat","voice","ui"]: current_result.peak_audio_groups[group] = maxi(int(current_result.peak_audio_groups[group]),int(audio_diag.active_groups[group]))
	var records := pool_records()
	for item: Dictionary in records:
		var key: String = str(item)
		if audio_seen.has(key): continue
		audio_seen[key] = true
		var record: Dictionary = item.duplicate(true)
		record["movie_frame"] = frame
		current_result.audio_records.append(record)
		var cue: String = str(record.get("cue",record.get("name","unknown")))
		current_result.cue_counts[cue] = int(current_result.cue_counts.get(cue,0)) + 1
	frame += 1
	telemetry.physics_frames = frame
	if frame % FRAMES_PER_SCENARIO == 0:
		current_result["end_frame"] = frame-1
		current_result["hp"] = [game.sim.fighters[0].hp,game.sim.fighters[1].hp]
		telemetry.scenario_results.append(current_result)

func finish_movie() -> void:
	var scenario_failures: Array = []
	for result: Dictionary in telemetry.scenario_results:
		var fixture: Dictionary = result.fixture
		var kind: String = ("meow" if int(fixture.kind) == 0 else "heart") if fixture.move == "special" else str(fixture.move)
		var contact_key: String = str(fixture.outcome) + ":" + kind
		var observed: int = int(result.event_counts.get(contact_key,0))
		if fixture.outcome != "miss" and observed != 1: scenario_failures.append(str(fixture.title) + " expected one " + contact_key + ", observed " + str(observed))
		if fixture.outcome == "miss":
			for event: Dictionary in result.events:
				if event.type in ["hit","block","break"]: scenario_failures.append(str(fixture.title) + " unexpectedly contacted")
		if int(result.physics_frames) != FRAMES_PER_SCENARIO or result.camera_zoom_changed or result.hud_moved: scenario_failures.append(str(fixture.title) + " frame count, camera or HUD instability")
		if bool(fixture.get("muted",false)) and not result.audio_records.is_empty(): scenario_failures.append(str(fixture.title) + " audio played while muted")
		if not bool(fixture.get("shake",true)) and float(result.max_camera_shift_px) > 0.0001: scenario_failures.append(str(fixture.title) + " camera moved with shake off")
	telemetry["scenario_failures"] = scenario_failures
	telemetry["completed"] = frame == SCENARIOS.size() * FRAMES_PER_SCENARIO and scenario_failures.is_empty()
	telemetry["engine_physics_frames_at_finish"] = Engine.get_physics_frames()
	telemetry["duration_seconds"] = float(frame)/FPS
	DirAccess.make_dir_recursive_absolute(telemetry_path.get_base_dir())
	var output := FileAccess.open(telemetry_path,FileAccess.WRITE)
	if output: output.store_string(JSON.stringify(telemetry,"\t")); output.close()
	else: printerr("MOVIE TELEMETRY WRITE FAILED ",telemetry_path)
	print("IMPACT MOVIE COMPLETE frames=",frame," seconds=",float(frame)/FPS," telemetry=",telemetry_path," delta_errors=",telemetry.delta_errors)
	quit(0 if output and telemetry.delta_errors == 0 and telemetry.completed else 1)

func capture_settings_stills() -> void:
	game.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(settings_stills)
	for dims: Vector2i in [Vector2i(375,614),Vector2i(568,267)]:
		root.size = dims
		root.content_scale_size = dims
		game.show_menu()
		game.hud._open_feedback_settings()
		for warmup in range(5): await process_frame
		game.layout_camera()
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var path: String = settings_stills.path_join("settings-%dx%d.png" % [dims.x,dims.y])
		var result: int = image.save_png(path)
		print("SETTINGS STILL ",path," actual=",image.get_size()," result=",result)
		game.hud._close_feedback_settings()
	quit()
