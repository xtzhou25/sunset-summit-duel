extends "res://tests/spacing_scene_test.gd"
## Native, deterministic real-main evidence. Six 60 Hz command sequences, 24 s
## total, 15 fps PNGs. No authored pose playback, attack-clock injection, HP refill,
## or position changes inside scenarios. Reset/initial positions are labelled.
## Copy this file AND spacing_scene_test.gd into RC7 for an identical baseline.
## godot --path . --script tests/spacing_capture.gd -- --frames=/absolute/path
## Optional: --baseline, --only=04_heavy_hit, --skin-every=12 (default 5 Hz).
var capture_output := "res://exports/qa-v7/spacing-fixture"
var capture_only := ""
var skin_every := 12
var capture_viewport: SubViewport
var capture_title: Label
var capture_detail: Label
var frame_number := 0
var all_samples: Array = []
var scenario_summaries: Array = []
const SCENARIOS := [
	{"id":"01_jump_cross_right", "kind":0, "face":1, "gap":0.90, "frames":240, "title":"JUMP CROSS RIGHT + MID-AIR REVERSAL"},
	{"id":"02_crouch_cross_left", "kind":1, "face":-1, "gap":0.90, "frames":240, "title":"DOWN CROUCH / RELEASE / JUMP CROSS LEFT"},
	{"id":"03_guard_retreat", "kind":0, "face":1, "gap":0.80, "frames":180, "title":"FASTER RETREAT, GUARD REMAINS ACTIVE"},
	{"id":"04_heavy_hit", "kind":0, "face":1, "gap":0.70, "frames":180, "title":"HEAVY HIT: OPEN SPACE WITHOUT KNOCKDOWN"},
	{"id":"05_heavy_block", "kind":0, "face":1, "gap":0.70, "frames":180, "title":"HEAVY BLOCK: LESS PUSH, NO HP DAMAGE"},
	{"id":"06_normal_ai", "kind":0, "face":1, "gap":0.70, "frames":420, "title":"AFTER HEAVY: NORMAL AI RESUMES THE DUEL"}
]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="): capture_output = argument.trim_prefix("--frames=")
		if argument.begins_with("--only="): capture_only = argument.trim_prefix("--only=")
		if argument.begins_with("--skin-every="): skin_every = maxi(1, int(argument.trim_prefix("--skin-every=")))
		if argument == "--baseline": baseline = true
	call_deferred("run_spacing_capture")

func build_capture_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	game.add_child(layer)
	capture_title = Label.new()
	capture_title.position = Vector2(14, 83)
	capture_title.add_theme_font_size_override("font_size", 18)
	capture_title.add_theme_color_override("font_color", Color("ffe8b4"))
	capture_title.add_theme_color_override("font_outline_color", Color("16101e"))
	capture_title.add_theme_constant_override("outline_size", 6)
	layer.add_child(capture_title)
	capture_detail = Label.new()
	capture_detail.position = Vector2(14, 106)
	capture_detail.add_theme_font_size_override("font_size", 13)
	capture_detail.add_theme_color_override("font_outline_color", Color("16101e"))
	capture_detail.add_theme_constant_override("outline_size", 5)
	layer.add_child(capture_detail)

func capture_commands(config: Dictionary, frame: int, contacted: bool) -> void:
	var face: int = config.face
	match String(config.id):
		"01_jump_cross_right":
			if frame == 18: set_move(face); game.on_command("jump", true)
			if frame == 19: game.on_command("jump", false)
			if frame == 120: set_move(-face); game.on_command("jump", true)
			if frame == 121: game.on_command("jump", false)
			if frame == 134: set_move(face)
			if frame == 152: set_move(0.0)
		"02_crouch_cross_left":
			if frame == 15: game.on_command("crouch", true)
			if frame == 70: game.on_command("crouch", false)
			if frame == 105: set_move(face); game.on_command("jump", true)
			if frame == 106: game.on_command("jump", false)
		"03_guard_retreat":
			if frame == 25: set_move(-face)
			if frame == 61: set_move(0.0)
			if frame == 85: set_move(face)
			if frame == 100: set_move(0.0)
			if frame == 110: set_move(-face)
			if frame == 145: set_move(0.0)
		"04_heavy_hit", "05_heavy_block", "06_normal_ai":
			if frame == 24: game.on_command("heavy", true)
			if frame == 25: game.on_command("heavy", false)
			if config.id == "05_heavy_block" and not contacted and game.sim.fighters[0].attack == "heavy" and game.sim.fighters[0].clock >= 0.32:
				robot.command = {"move":float(face)}

func write_capture_json(path: String, value) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		printerr("Unable to write capture telemetry: ", path)
		return
	file.store_string(JSON.stringify(value)); file.close()

func record_scenario(config: Dictionary) -> void:
	setup_spacing(config.kind, config.face, config.gap)
	var folder := capture_output + "/" + String(config.id)
	DirAccess.make_dir_recursive_absolute(folder)
	var samples: Array = []
	var contacted := false
	var ai_started := false
	var contact_count := 0
	var maximum_gap := root_gap()
	var max_height := 0.0
	var cross_count := 0
	var previous_side: int = 1 if game.sim.fighters[1].x > game.sim.fighters[0].x else -1
	var latest_skin := skin_gap()
	var last_skin_frame := -1
	var png_count := 0
	capture_title.text = ("RC7 BASELINE | " if baseline else "TUNED BUILD | ") + String(config.title)
	for frame in range(int(config.frames)):
		capture_commands(config, frame, contacted)
		var events := spacing_step()
		var p: Dictionary = game.sim.fighters[0]
		var o: Dictionary = game.sim.fighters[1]
		maximum_gap = maxf(maximum_gap, root_gap())
		max_height = maxf(max_height, float(p.y))
		var side: int = 1 if o.x > p.x else -1
		if side != previous_side: cross_count += 1; previous_side = side
		for event: Dictionary in events:
			if event.type == "land" and event.fighter == 0 and config.id in ["01_jump_cross_right", "02_crouch_cross_left"]: set_move(0.0)
			if event.type in ["hit", "block", "break"]:
				contact_count += 1
				if event.get("kind", "") == "heavy" and event.fighter == 1 and not contacted:
					contacted = true
					robot.command.clear()
					if config.id == "06_normal_ai":
						var normal = NormalAI.new()
						normal.rng.seed = 607122; normal.reset()
						game.brain = normal; ai_started = true
		if frame % skin_every == 0 or not events.is_empty():
			latest_skin = skin_gap(); last_skin_frame = frame
		var fixture := "Controlled start + scripted passive/guard target; real game commands"
		if config.id == "06_normal_ai": fixture = "Controlled opening; NORMAL AI ACTIVE" if ai_started else "Controlled opening; normal AI starts after the heavy lands"
		if baseline and config.id == "02_crouch_cross_left" and frame < 105: fixture = "RC7 has no down-crouch command; same inputs are deliberately replayed"
		capture_detail.text = "%s\nRoot gap %.2f m | skin gap %.2f m | HP %.0f / %.0f | %s" % [fixture, root_gap(), latest_skin.world_gap, p.hp, o.hp, "GUARD" if p.blocking else String(p.state)]
		var sample := {"scenario":config.id, "frame":frame, "global_frame":frame_number,
			"sim_time":game.sim.elapsed, "elapsed_video":float(frame)/60.0,
			"player":p.duplicate(true), "target":o.duplicate(true),
			"held_inputs":game.held.duplicate(true), "clips":game.current_clips.duplicate(),
			"events":events, "root_gap":root_gap(), "skin_gap":latest_skin,
			"skin_measured_at_frame":last_skin_frame, "normal_ai_active":ai_started,
			"hitstop":game.hitstop, "wins":game.wins.duplicate()}
		samples.append(sample)
		if frame % 4 == 0:
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var png := "%04d.png" % png_count
				var image = capture_viewport.get_texture().get_image()
				image.save_png(folder + "/" + png)
				# Continuous sequence as well as individual scenarios, for GIF/video.
				image.save_png(capture_output + "/" + ("%04d.png" % int(frame_number / 4)))
			png_count += 1
		frame_number += 1
		await process_frame
	var summary := {"id":config.id, "mode":"controlled opening then normal AI" if config.id == "06_normal_ai" else "controlled initial position and scripted target",
		"seconds":float(config.frames)/60.0, "frames_60hz":config.frames, "png_frames_15fps":png_count if DisplayServer.get_name() != "headless" else 0,
		"contact_count":contact_count, "cross_count":cross_count, "max_root_gap":maximum_gap,
		"final_root_gap":root_gap(), "peak_player_y":max_height, "final_skin_gap":skin_gap(),
		"player_hp":game.sim.fighters[0].hp, "target_hp":game.sim.fighters[1].hp, "normal_ai_started":ai_started}
	scenario_summaries.append(summary)
	all_samples.append_array(samples)
	write_capture_json(folder + "/telemetry.json", {"summary":summary, "samples":samples})
	print("SPACING_CAPTURE_SCENARIO ", JSON.stringify(summary))

func run_spacing_capture() -> void:
	DirAccess.make_dir_recursive_absolute(capture_output)
	capture_viewport = SubViewport.new()
	capture_viewport.size = Vector2i(960, 600)
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	capture_viewport.own_world_3d = true
	root.add_child(capture_viewport)
	game = load("res://main.tscn").instantiate()
	capture_viewport.add_child(game); game.set_physics_process(false)
	await process_frame
	build_capture_overlay()
	for config: Dictionary in SCENARIOS:
		if capture_only != "" and capture_only != config.id: continue
		await record_scenario(config)
	write_capture_json(capture_output + "/telemetry.json", {
		"kind":"Controlled initial positions; real-main input and simulation; normal AI only in the labelled final segment",
		"baseline":baseline, "simulation_fps":60, "capture_fps":15, "resolution":[960,600],
		"no_hp_or_attack_clock_overrides":true, "skin_gap_definition":"All actual weighted GLB vertices projected to screen; stale samples carry their measurement frame",
		"scenarios":scenario_summaries, "samples":all_samples})
	print("SPACING_CAPTURE_COMPLETE ", capture_output, " seconds=", float(frame_number)/60.0, " rendered=", DisplayServer.get_name() != "headless")
	game.sound.stop(); capture_viewport.queue_free(); await process_frame
	quit()
