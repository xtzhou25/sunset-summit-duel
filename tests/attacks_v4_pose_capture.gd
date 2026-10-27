extends SceneTree
## Labelled native pose fixtures, not live matches and not the real opponent AI.
## Four 4-second scenarios: both characters, both facings, scripted wall guard.
## Initial body-center separation .84. All subsequent motion, damage and poses
## come from normal inputs and the real 60 Hz main loop. Images sample at 15 fps.
## godot --path . --audio-driver Dummy --script tests/attacks_v4_pose_capture.gd -- --frames=/absolute/output
## Headless mode runs the same fixtures and telemetry but deliberately skips PNGs.
const DT := 1.0 / 60.0
const FRAMES_PER_SCENARIO := 240
const Combat = preload("res://scripts/combat.gd")
class ScriptedWallGuard extends RefCounted:
	var direction := 1.0
	func reset() -> void: pass
	func act(_sim, _delta: float) -> Dictionary: return {"move":direction}
var output := "res://exports/qa-v4/attack-pose-fixtures"
var failures := 0

func _initialize() -> void: call_deferred("run")
func require(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("FIXTURE FAILURE: ", message)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="): output = arg.trim_prefix("--frames=")
	var error := DirAccess.make_dir_recursive_absolute(output)
	if error != OK:
		printerr("Cannot create capture destination: ", output, " error=", error)
		quit(1); return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var scene = load("res://main.tscn").instantiate()
	viewport.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	var guard := ScriptedWallGuard.new()
	scene.brain = guard
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	viewport.add_child(overlay)
	var backing := ColorRect.new()
	backing.position = Vector2(12, 80)
	backing.size = Vector2(936, 40)
	backing.color = Color(0.025, 0.02, 0.05, 0.88)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(backing)
	var label := Label.new()
	label.position = Vector2(20, 82)
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(label)
	var telemetry: Array = []
	var summaries: Array = []
	var image_count := 0
	var scenario := 0
	for character in range(2):
		for facing in [-1, 1]:
			var name := "%s-%s" % ["purple" if character == 0 else "yellow", "left" if facing < 0 else "right"]
			var destination := output + "/" + name
			require(DirAccess.make_dir_recursive_absolute(destination) == OK, "scenario directory " + destination)
			scene.hud._choose(character)
			scene.muted = true
			scene.auto_demo = false
			guard.direction = float(facing)
			# The only position/facing fixture. Holding back at the arena wall is
			# actual stationary guard, not an immobilized or fake blocking state.
			scene.sim.fighters[1].x = Combat.RIGHT if facing > 0 else Combat.LEFT
			scene.sim.fighters[0].x = scene.sim.fighters[1].x - float(facing) * 0.84
			scene.sim.fighters[0].face = facing
			scene.sim.fighters[1].face = -facing
			scene.render_state(0.0)
			var initial_guard_x: float = scene.sim.fighters[1].x
			var queued := false
			var heavy_started := false
			var attack_order: Array[String] = []
			var attack_ids: Dictionary = {}
			var contacts: Array = []
			var stationary_guard := true
			var saw_blocking := false
			for frame in range(FRAMES_PER_SCENARIO):
				var fighter: Dictionary = scene.sim.fighters[0]
				var jab_press := frame == 12
				if not queued and fighter.attack == "punch" and scene.hitstop <= 0.0 and fighter.duration - fighter.clock <= 0.095:
					jab_press = true
					queued = true
				var heavy_press := false
				if not heavy_started and "straight" in attack_order and fighter.attack == "" and fighter.land_lock <= 0.0 and scene.hitstop <= 0.0:
					heavy_press = true
					heavy_started = true
				scene.on_command("punch", jab_press)
				scene.on_command("heavy", heavy_press)
				var before_elapsed: float = scene.sim.elapsed
				scene._physics_process(DT)
				fighter = scene.sim.fighters[0]
				var defender: Dictionary = scene.sim.fighters[1]
				stationary_guard = stationary_guard and is_equal_approx(defender.x, initial_guard_x)
				saw_blocking = saw_blocking or defender.blocking
				if fighter.attack != "" and not attack_ids.has(fighter.attack_id):
					attack_ids[fighter.attack_id] = true
					attack_order.append(fighter.attack)
				var fresh_events: Array = scene.sim.events.duplicate(true) if scene.sim.elapsed != before_elapsed else []
				for event: Dictionary in fresh_events:
					if event.type in ["hit", "block", "break"]:
						contacts.append({"frame":frame, "event":event.duplicate(true)})
				label.text = "POSE FIXTURE %d/4 | %s | scripted stationary wall guard | NOT A LIVE MATCH\nJab > late-buffer Straight > Heavy | %.2fs | player: %s | initial center separation 0.84" % [scenario + 1, name.to_upper(), frame * DT, fighter.attack if fighter.attack != "" else "ready"]
				if frame % 4 == 0:
					if DisplayServer.get_name() != "headless":
						await RenderingServer.frame_post_draw
						var saved := viewport.get_texture().get_image().save_png(destination + "/%04d.png" % int(frame / 4))
						require(saved == OK, "image save " + name + " frame " + str(frame))
						if saved == OK: image_count += 1
					telemetry.append({"fixture":true, "scenario":name, "scenario_index":scenario, "frame":frame, "global_frame":scenario * FRAMES_PER_SCENARIO + frame, "simulation_elapsed":scene.sim.elapsed, "player":fighter.duplicate(true), "scripted_guard":defender.duplicate(true), "clips":scene.current_clips.duplicate(), "animation_positions":[scene.anims[0].current_animation_position, scene.anims[1].current_animation_position], "fresh_events":fresh_events, "hitstop":scene.hitstop, "last_feedback":scene.last_feedback})
				await process_frame
			require(attack_order == ["punch", "straight", "heavy"], name + " exact normal-input jab > straight > heavy order: " + str(attack_order))
			require(stationary_guard and saw_blocking, name + " scripted defender stayed stationary and actually guarded")
			require(scene.sim.fighters[0].attack == "" and scene.sim.fighters[0].land_lock == 0.0 and scene.sim.fighters[0].queued == "", name + " full recovery completed")
			require(not scene.sim.round_over, name + " remains a fixture, not a staged KO")
			summaries.append({"scenario":name, "attack_order":attack_order, "contacts":contacts, "stationary_guard":stationary_guard, "initial_separation":0.84, "samples":FRAMES_PER_SCENARIO / 4, "final_player":scene.sim.fighters[0].duplicate(true), "final_guard":scene.sim.fighters[1].duplicate(true)})
			print("POSE FIXTURE ", name, " attacks=", attack_order, " contacts=", contacts.size(), " stationary_guard=", stationary_guard)
			scenario += 1
	var document := {"fixture":true, "description":"Labelled scripted wall-guard pose fixtures, not live matches or real AI demonstrations. Only initial position/facing setup; normal on_command input and real main-loop simulation afterward.", "resolution":[960,600], "simulation_hz":60, "capture_fps":15, "scenario_seconds":4, "headless":DisplayServer.get_name() == "headless", "image_count":image_count, "failures":failures, "scenarios":summaries, "samples":telemetry}
	var file := FileAccess.open(output + "/telemetry.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(document))
		file.close()
	else: require(false, "telemetry file open " + output)
	print("LABELLED POSE FIXTURES ", output, " scenarios=", scenario, " samples=", telemetry.size(), " PNGs=", image_count, " failures=", failures, "; not live-match or real-AI evidence")
	scene.sound.stop()
	viewport.queue_free()
	await process_frame
	quit(mini(failures, 255))
