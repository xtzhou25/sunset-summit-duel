extends SceneTree
## Real-main signature integration. Commands enter through fresh on_command edges;
## no attack clocks, projectile spawns, emission positions, or phase state injected.
## Only position/guard/invulnerability fixtures are used, explicitly labelled.
## godot --headless --path . --script tests/signature_scene_test.gd
## Add -- --require-new for final paired clips AND complete measured markers.
## Headless results never certify visual appearance or audio hardware playback.
const Combat = preload("res://scripts/combat.gd")
const DT := 1.0 / 60.0
const EPS := 0.00002
const OLD_BASES := ["Idle", "Walk", "Run", "SitDown", "SitIdle", "StandUp", "JumpStart", "JumpLoop", "JumpLand", "Punch", "FlyingKickStart", "FlyingKickLoop", "FlyingKickLand", "Guard", "HitReact", "Knockdown", "Recover", "Victory", "BackstepGuard", "FightIdle", "HitReactStrong"]
const OLD_PAIRED := ["FightIdle", "Guard", "BackstepGuard", "Walk", "Run", "FlyingKickLoop", "HitReactStrong", "Punch", "FlyingKickStart", "FlyingKickLand", "JumpStart", "JumpLoop", "JumpLand", "Knockdown", "Recover", "Jab", "Straight", "HeavyPunch", "RoundhouseKick"]
const ACTIONS := ["punch", "kick", "heavy", "roundhouse", "special"]
class ScriptedAI extends RefCounted:
	var command: Dictionary = {}
	func reset() -> void: command.clear()
	func act(_sim, _delta: float) -> Dictionary: return command.duplicate()
var game
var robot := ScriptedAI.new()
var checks := 0
var failures := 0
var require_new := false
var missing_assets: Array[String] = []
var observations: Array = []
var observed_emissions: Array = []
var independent_markers: Dictionary = {}
var verified_pose_samples := 0
var fallback_pose_samples := 0
var verified_marker_samples := 0
var marker_ready := [false, false]
var reference_roots: Array = []
var reference_players: Array = []
var verified_bone_pose_samples := 0
var maximum_bone_origin_error := 0.0
var maximum_bone_basis_error := 0.0

func _initialize() -> void:
	require_new = "--require-new" in OS.get_cmdline_user_args()
	call_deferred("run_tests")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else: failures += 1; printerr("FAIL: ", label)

func gate(ok: bool, label: String) -> void:
	if not ok: missing_assets.append(label)
	if require_new or ok: check(ok, label)
	else: print("PROVISIONAL MISSING: ", label)

func setup(kind: int = 0, face: int = 1) -> void:
	game.brain = robot
	game.hud._choose(kind)
	game.set_physics_process(false)
	game.auto_demo = false
	if game.muted: game.toggle_mute()
	game.sound_enabled = true
	game.sound.stop(); game.sound.stream = null
	game.meow_sound.stop()
	game.sim.fighters[0].x = -0.8 * face
	game.sim.fighters[1].x = 1.2 * face
	game.sim.fighters[0].face = face
	game.sim.fighters[1].face = -face
	observations.clear()
	game.sim.emitter_provider = observe_emitter
	game.render_state(0.0)

func step(delta: float = DT) -> Array:
	var before: float = game.sim.elapsed
	game._physics_process(delta)
	return game.sim.events.duplicate(true) if game.sim.elapsed != before else []

func press(action: String = "special") -> void: game.on_command(action, true)
func release(action: String = "special") -> void: game.on_command(action, false)
func pulse(action: String = "special") -> Array:
	press(action)
	var events := step()
	release(action)
	return events
func settle(frames: int) -> void:
	for frame in range(frames): step()

func skeleton_of(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var result := skeleton_of(child)
		if result: return result
	return null

func measure_marker(index: int) -> Dictionary:
	return marker_from_model(game.actors[index], int(game.sim.fighters[index].kind))

func marker_from_model(model: Node, kind: int) -> Dictionary:
	# Independently traverse the imported model and read the JSON from disk,
	# rather than accepting main.emitter_positions or signature_emitter output.
	var skeleton := skeleton_of(model)
	var key := "purple" if kind == 0 else "yellow"
	var points: Array = independent_markers.get(key, {}).get("points", [])
	var total := Vector3.ZERO
	var count := 0
	if not skeleton: return {"valid":false, "world":total}
	skeleton.force_update_all_bone_transforms()
	for point: Dictionary in points:
		var bone: int = skeleton.find_bone(str(point.get("bone", "")))
		var offset: Array = point.get("offset", [])
		if bone < 0 or offset.size() != 3: return {"valid":false, "world":total}
		var local := Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
		if not local.is_finite(): return {"valid":false, "world":total}
		total += skeleton.global_transform * skeleton.get_bone_global_pose(bone) * local
		count += 1
	return {"valid":count > 0, "world":total / maxf(1.0, count)}

func observe_emitter(index: int, exact_age: float) -> Vector2:
	# Transparent observer only: real main owns the callback and return value.
	var result: Vector2 = game.signature_emitter(index, exact_age)
	var marker := measure_marker(index)
	var f: Dictionary = game.sim.fighters[index]
	var kind: int = f.kind
	var face: int = f.special_face
	var reference: Node3D = reference_roots[kind]
	var player: AnimationPlayer = reference_players[kind]
	var clip := paired_name(kind, "air", face)
	var air_age: float = clampf(exact_age - 0.20, 0.0, 0.60)
	reference.position = Vector3(f.x, 0.0 if kind == 0 else maxf(0.0, 5.25 * air_age - 8.75 * air_age * air_age), 0.0)
	reference.rotation.y = face * PI / 2.0
	var independent_pose: Dictionary = {"valid":false, "world":Vector3.ZERO}
	if player.has_animation(clip):
		# Clean imported reference never went through main's blend/previous pose.
		player.stop(); player.play(clip, 0.0); player.seek(exact_age if kind == 0 else exact_age - 0.20, true); player.advance(0.0)
		independent_pose = marker_from_model(reference, kind)
	observations.append({"index":index, "age":exact_age, "clock":game.sim.fighters[index].clock,
		"origin":result, "world":marker.world, "valid":marker.valid, "reference_valid":independent_pose.valid, "reference_world":independent_pose.world,
		"root":game.actors[index].position, "clip":game.anims[index].current_animation,
		"pose_time":game.anims[index].current_animation_position})
	return result

func paired_name(kind: int, phase: String, face: int) -> String:
	var base: String = "MeowCast" if kind == 0 else {"start":"HeartCastStart", "air":"HeartCastLoop", "land":"HeartCastLand"}.get(phase, "HeartCastStart")
	return base + ("_R" if face > 0 else "_L")

func pose_matches(index: int) -> bool:
	var f: Dictionary = game.sim.fighters[index]
	var clip := paired_name(f.kind, f.special_phase, f.face)
	if not game.anims[index].has_animation(clip):
		fallback_pose_samples += 1
		return not require_new
	verified_pose_samples += 1
	return game.current_clips[index] == clip and game.anims[index].current_animation == clip and absf(game.anims[index].current_animation_position - f.special_phase_clock) < EPS and game.anims[index].speed_scale == 0.0

func asset_tests() -> void:
	setup()
	for index in range(2):
		var kind: int = game.sim.fighters[index].kind
		var old_present := true
		for clip: String in OLD_BASES: old_present = old_present and game.anims[index].has_animation(clip)
		for base: String in OLD_PAIRED:
			for side in ["_R", "_L"]: old_present = old_present and game.anims[index].has_animation(base + side)
		check(OLD_BASES.size() + 2 * OLD_PAIRED.size() == 59 and old_present, "kind %d retains every one of the 59 original clip names" % kind)
		var names: Dictionary = {"MeowCast":1.0} if kind == 0 else {"HeartCastStart":0.20, "HeartCastLoop":0.60, "HeartCastLand":0.25}
		for base: String in names:
			for side in ["_R", "_L"]:
				var clip: String = base + side
				var exists: bool = game.anims[index].has_animation(clip)
				gate(exists, "kind %d final paired clip %s" % [kind, clip])
				if exists:
					var animation: Animation = game.anims[index].get_animation(clip)
					check(absf(animation.length - names[base]) < EPS and animation.loop_mode == Animation.LOOP_NONE, "%s authored duration %.2f and no automatic loop" % [clip, names[base]])
		var key: String = "purple" if kind == 0 else "yellow"
		var status: String = str(independent_markers.get("status", "")).to_lower()
		var marker := measure_marker(index)
		var points: Array = independent_markers.get(key, {}).get("points", [])
		marker_ready[kind] = marker.valid and points.size() >= (1 if kind == 0 else 2) and not ("wip" in status or "pending" in status or "provisional" in status)
		gate(marker_ready[kind], "kind %d complete non-WIP measured mouth or two-hand marker record with valid imported bones" % kind)

func projectile_visual_ok(p: Dictionary, observation: Dictionary) -> bool:
	if not game.projectile_view.views.has(p.id): return false
	var node: Node3D = game.projectile_view.views[p.id]
	var depth: float = game.emitter_positions[p.owner].z
	if node.position.distance_to(Vector3(p.pos.x, p.pos.y, depth)) > EPS or node.scale != Vector3.ONE: return false
	if observation.valid and absf(depth - observation.world.z) > EPS: return false
	if p.kind == "meow":
		return node is Label3D and node.text == "喵" and node.font.has_char("喵".unicode_at(0)) and node.billboard == BaseMaterial3D.BILLBOARD_ENABLED and node.basis.determinant() > 0.0
	if not node is MeshInstance3D or not node.mesh is ArrayMesh or node.mesh.get_surface_count() != 1: return false
	var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top_notch := false
	var bottom_point := false
	for vertex: Vector3 in vertices:
		if absf(vertex.x) < EPS and absf(vertex.y - 0.14) < EPS: top_notch = true
		if absf(vertex.x) < EPS and absf(vertex.y + 0.25) < EPS: bottom_point = true
	return top_notch and bottom_point and node.mesh.get_aabb().size.z > 0.10 and node.material_override.albedo_color == Color("f284bd")

func cast_and_feedback_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for outcome in ["hit", "block", "miss"]:
				setup(kind, face)
				if outcome == "block": robot.command = {"move":float(face)}
				var label := "kind %d face %d %s" % [kind, face, outcome]
				pulse()
				var f: Dictionary = game.sim.fighters[0]
				var target: Dictionary = game.sim.fighters[1]
				var root_x: float = f.x
				var begun: float = game.sim.elapsed
				var emit_age := 0.38 if kind == 0 else 0.48
				check(f.attack == "special" and f.clock == 0.0 and f.special_cooldown == 4.0 and game.sim.attack_serial == 1, label + " fresh scene input begins at zero and commits four-second cooldown")
				if outcome == "miss":
					# Cross-up position fixture AFTER commitment. No cast clock changes.
					target.x = -1.8 * face
				var spawn_count := 0
				var contact_count := 0
				var land_count := 0
				var body_ok := true
				var pose_ok := pose_matches(0)
				var origin_ok := true
				var visual_ok := true
				var feedback_ok := true
				var freeze_ok := true
				var effect_xy_ok := true
				var max_height := 0.0
				var completed_at := -1.0
				press("right" if face > 0 else "left")
				for frame in range(150):
					var guard_before: float = target.guard
					var events := step()
					if f.attack == "special":
						var air_age: float = clampf(f.clock - 0.20, 0.0, 0.60)
						var expected_y: float = 0.0 if kind == 0 else maxf(0.0, 5.25 * air_age - 8.75 * air_age * air_age)
						body_ok = body_ok and absf(f.x - root_x) < EPS and f.vx == 0.0 and absf(f.y - expected_y) < EPS and game.actors[0].position.distance_to(Vector3(f.x, f.y, 0)) < EPS and game.actors[0].get_child(0).position.length() < EPS and f.face == face
						pose_ok = pose_matches(0) and pose_ok
						max_height = maxf(max_height, f.y)
					elif completed_at < 0.0:
						completed_at = game.sim.elapsed - begun
						release("right" if face > 0 else "left")
					for event: Dictionary in events:
						if event.type == "land" and event.fighter == 0: land_count += 1
						if event.type == "projectile_spawn":
							spawn_count += 1
							var observation: Dictionary = observations.back()
							var marker_correct: bool = observation.valid and observation.reference_valid and event.pos.distance_to(Vector2(observation.world.x, observation.world.y)) < EPS and observation.origin.distance_to(event.pos) < EPS and observation.world.distance_to(observation.reference_world) < 0.001
							if observation.valid and observation.reference_valid: origin_ok = origin_ok and marker_correct
							if marker_ready[kind]: verified_marker_samples += 1; origin_ok = origin_ok and marker_correct
							elif require_new: origin_ok = false
							var expected_root := 0.0 if kind == 0 else 0.784
							origin_ok = origin_ok and absf(observation.age - emit_age) < EPS and f.clock >= emit_age and f.clock < emit_age + DT + EPS and absf(observation.root.y - expected_root) < EPS and observations.size() == 1
							var emitted_clip := paired_name(kind, "air", face)
							if game.anims[0].has_animation(emitted_clip): origin_ok = origin_ok and observation.clip == emitted_clip and absf(observation.pose_time - (0.38 if kind == 0 else 0.28)) < EPS
							observed_emissions.append({"kind":kind, "face":face, "outcome":outcome, "age":observation.age, "frame_clock":f.clock, "origin":str(event.pos), "world":str(observation.world), "reference_world":str(observation.reference_world), "marker_verified":marker_ready[kind] and marker_correct})
							for p: Dictionary in game.sim.projectiles:
								if p.id == event.id:
									visual_ok = visual_ok and projectile_visual_ok(p, observation) and absf(p.age - (f.clock - emit_age)) < EPS and p.previous_pos.distance_to(event.pos) < EPS and absf(p.velocity.x - face * 3.6) < EPS
									if kind == 0: visual_ok = visual_ok and p.velocity.y == 0.0
						if event.type in ["hit", "block", "break"]:
							contact_count += 1
							feedback_ok = feedback_ok and event.type == outcome and event.kind == ("meow" if kind == 0 else "heart") and event.fighter == 1 and game.last_feedback == outcome + ":" + event.kind and not target.down
							feedback_ok = feedback_ok and is_equal_approx(game.hitstop, 0.025 if outcome == "block" else 0.055)
							effect_xy_ok = effect_xy_ok and game.effects.size() == 1 and event.has("impact_x") and absf(game.effects[0].node.position.x - float(event.get("impact_x", INF))) < EPS and absf(game.effects[0].node.position.y - event.impact_y) < EPS
							var swept_contact := Vector2(INF, INF)
							for swept: Dictionary in events:
								if swept.type == "projectile_despawn" and swept.reason == "contact": swept_contact = swept.pos
							effect_xy_ok = effect_xy_ok and swept_contact.distance_to(Vector2(float(event.get("impact_x", INF)), event.impact_y)) < EPS
							if outcome == "hit": feedback_ok = feedback_ok and absf(target.stun - 0.26) < EPS and game.current_clips[1] == "HitReactStrong" + ("_R" if target.face > 0 else "_L")
							elif outcome == "block": feedback_ok = feedback_ok and absf(target.guard - (guard_before - 28.0 - 9.0 * DT)) < EPS
							var frozen: Array = [game.sim.elapsed, game.sim.time_left, f.clock, f.special_cooldown, game.anims[0].current_animation_position, game.sim.projectiles.duplicate(true)]
							step()
							freeze_ok = freeze_ok and frozen == [game.sim.elapsed, game.sim.time_left, f.clock, f.special_cooldown, game.anims[0].current_animation_position, game.sim.projectiles]
					if completed_at >= 0.0 and game.sim.projectiles.is_empty() and game.hitstop <= 0.0: break
				release("right" if face > 0 else "left")
				check(spawn_count == 1 and observations.size() == 1 and origin_ok, label + " exactly one fixed-time event with independently checked final marker when available")
				check(pose_ok, label + " paired pose seeks phase clock, never renderer time (missing assets are provisional only)")
				check(body_ok and land_count == (0 if kind == 0 else 1) and absf(max_height - (0.0 if kind == 0 else 0.7875)) < EPS, label + " single analytic body jump, one yellow landing, no doubled root motion")
				check(visual_ok, label + " real spawned view uses exact world XY/depth, readable nonmirrored glyph or solid true-heart mesh")
				check(contact_count == (0 if outcome == "miss" else 1) and feedback_ok and target.hp == (88.0 if outcome == "hit" else 100.0), label + " one correct hit/block or genuine facing-locked miss; no duplicate damage")
				check(effect_xy_ok, label + " hit/block effect uses exact swept contact XY, not current owner/target position")
				check(freeze_ok and completed_at >= f.duration - EPS and completed_at <= f.duration + DT + EPS, label + " hitstop freezes clocks; full cast and landing recovery are retained")
				check(game.sim.projectiles.is_empty() and game.projectile_view.views.is_empty(), label + " consumed or expired wave cleans up simulation and view")



func independent_bone_pose_error(index: int) -> Dictionary:
	var f: Dictionary = game.sim.fighters[index]
	var kind: int = f.kind
	var cast_age: float = f.clock
	var phase: String = "cast" if kind == 0 else ("start" if cast_age + EPS < 0.20 else ("air" if cast_age + EPS < 0.80 else "land"))
	var phase_age: float = cast_age if kind == 0 or phase == "start" else cast_age - (0.20 if phase == "air" else 0.80)
	var clip := paired_name(kind, phase, int(f.special_face))
	var player: AnimationPlayer = reference_players[kind]
	if not player.has_animation(clip): return {"available":false, "origin":INF, "basis":INF, "worst":"missing clip"}
	var reference: Node3D = reference_roots[kind]
	var air_age: float = clampf(cast_age - 0.20, 0.0, 0.60)
	reference.position = Vector3(f.x, 0.0 if kind == 0 else maxf(0.0, 5.25 * air_age - 8.75 * air_age * air_age), 0.0)
	reference.rotation.y = f.special_face * PI / 2.0
	# A fresh no-blend pose in a separate imported model is the expected result.
	# This catches a correct clip name/clock with stale FightIdle blend weights.
	player.stop(); player.play(clip, 0.0); player.seek(maxf(0.0, phase_age), true); player.advance(0.0)
	var actual := skeleton_of(game.actors[index])
	var expected := skeleton_of(reference)
	if not actual or not expected: return {"available":false, "origin":INF, "basis":INF, "worst":"missing skeleton"}
	actual.force_update_all_bone_transforms(); expected.force_update_all_bone_transforms()
	var origin_error := 0.0
	var basis_error := 0.0
	var worst := ""
	for bone_name: String in ["DEF-spine", "DEF-spine.006", "DEF-hand.L", "DEF-hand.R", "DEF-foot.L", "DEF-foot.R"]:
		var actual_bone: int = actual.find_bone(bone_name)
		var expected_bone: int = expected.find_bone(bone_name)
		if actual_bone < 0 or expected_bone < 0: return {"available":false, "origin":INF, "basis":INF, "worst":bone_name}
		var actual_world: Transform3D = actual.global_transform * actual.get_bone_global_pose(actual_bone)
		var expected_world: Transform3D = expected.global_transform * expected.get_bone_global_pose(expected_bone)
		var distance: float = actual_world.origin.distance_to(expected_world.origin)
		if distance > origin_error: origin_error = distance; worst = bone_name
		basis_error = maxf(basis_error, maxf(actual_world.basis.x.distance_to(expected_world.basis.x), maxf(actual_world.basis.y.distance_to(expected_world.basis.y), actual_world.basis.z.distance_to(expected_world.basis.z))))
	verified_bone_pose_samples += 6
	maximum_bone_origin_error = maxf(maximum_bone_origin_error, origin_error)
	maximum_bone_basis_error = maxf(maximum_bone_basis_error, basis_error)
	return {"available":true, "origin":origin_error, "basis":basis_error, "worst":worst}

func actual_bone_pose_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			setup(kind, face)
			game.sim.fighters[1].invuln = 10.0 # Isolates pose progression from hitstop.
			pulse()
			var sample_frames: Array = [2, 6, 12, 18, 22, 24, 33, 48, 57] if kind == 0 else [2, 6, 11, 12, 14, 18, 24, 28, 30, 37, 47, 48, 50, 57, 62]
			for frame in range(1, 63):
				step()
				if frame not in sample_frames: continue
				var error := independent_bone_pose_error(0)
				var phase: String = game.sim.fighters[0].special_phase
				var label := "kind %d face %d age %.6f %s" % [kind, face, game.sim.fighters[0].clock, phase]
				if not error.available and not require_new:
					print("PROVISIONAL BONE SAMPLE: ", label)
					continue
				check(error.available and error.origin < 0.001 and error.basis < 0.001, label + " head/hands/feet/pelvis match clean imported pose (origin %.6fm, basis %.6f, worst %s)" % [error.origin, error.basis, error.worst])
				# Extra presentation updates cannot advance a blend independently of
				# the simulation clock or perturb the physically owned body height.
				game.render_state(0.003); game.render_state(0.041)
				var repeated := independent_bone_pose_error(0)
				check(repeated.available and repeated.origin < 0.001 and repeated.basis < 0.001, label + " variable render delta keeps actual bones on the same authoritative pose")

func exact_phase_and_large_step_tests() -> void:
	setup(1)
	game.sim.fighters[1].invuln = 10.0
	pulse()
	var f: Dictionary = game.sim.fighters[0]
	step(0.20)
	check(f.special_phase == "air" and absf(f.special_phase_clock) < EPS and f.y == 0.0 and f.vy == 5.25 and pose_matches(0), "real main exact .20 takeoff seeks air clip at zero with vy=5.25")
	step(0.28)
	check(f.special_phase == "air" and absf(f.special_phase_clock - 0.28) < EPS and absf(f.y - 0.784) < EPS and absf(f.vy - 0.35) < EPS and observations.size() == 1, "real main exact .48 global/.28 air emits once on analytic gravity-17.5 arc")
	step(0.32)
	print("EXACT LAND SAMPLE phase=", f.special_phase, "; phase_clock=", f.special_phase_clock, "; root_y=", f.y, "; vy=", f.vy, "; clip=", game.current_clips[0], "; assigned=", game.anims[0].current_animation, "; time=", game.anims[0].current_animation_position, "; speed=", game.anims[0].speed_scale)
	check(f.special_phase == "land" and f.y == 0.0 and f.vy == 0.0 and pose_matches(0), "real main exact .80 landing changes to landed phase at zero pose time")
	step(0.249)
	print("EXACT LAND RECOVERY phase=", f.special_phase, "; phase_clock=", f.special_phase_clock, "; attack=", f.attack, "; root_y=", f.y, "; clip=", game.current_clips[0], "; assigned=", game.anims[0].current_animation, "; time=", game.anims[0].current_animation_position)
	check(f.attack == "special" and f.special_phase == "land" and pose_matches(0), "real main retains full landing recovery through 1.049 seconds")
	step(0.001)
	check(f.attack == "" and f.special_phase == "" and f.y == 0.0, "real main releases yellow at exactly 1.05 seconds")
	for kind in range(2):
		for face in [-1, 1]:
			setup(kind, face)
			pulse()
			# A cross-up after cast lock cannot turn the emission around, even if
			# one main-loop step crosses both emission and complete recovery.
			game.sim.fighters[1].x = -1.8 * face
			var events := step(1.20)
			var spawns := 0
			for event: Dictionary in events:
				if event.type == "projectile_spawn": spawns += 1
			var observed: Dictionary = observations[0] if not observations.is_empty() else {}
			var expected := paired_name(kind, "air", face)
			var pose_ok: bool = not require_new if not game.anims[0].has_animation(expected) else not observed.is_empty() and observed.clip == expected and absf(observed.pose_time - (0.38 if kind == 0 else 0.28)) < EPS
			check(spawns == 1 and observations.size() == 1 and game.sim.fighters[0].attack == "" and game.sim.fighters[1].hp == 100.0 and pose_ok, "kind %d face %d large real-main step emits once at original locked-facing pose, even across recovery" % [kind, face])
			if marker_ready[kind]:
				check(observed.reference_valid and observed.world.distance_to(observed.reference_world) < 0.001, "kind %d face %d large-step origin matches independently sought clean imported pose" % [kind, face])
			step(0.20)
			check(observations.size() == 1 and game.sim.projectile_serial == 1, "kind %d face %d large-step emission never repeats" % [kind, face])

func input_and_cooldown_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			setup(kind, face); game.sim.fighters[1].invuln = 8.0
			press(); step(); settle(300)
			check(game.sim.attack_serial == 1 and game.sim.projectile_serial == 1 and game.sim.fighters[0].special_cooldown == 0.0, label + " held real-scene special never repeats after recovery or cooldown")
			release(); pulse()
			check(game.sim.attack_serial == 2 and game.sim.fighters[0].clock == 0.0 and game.sim.fighters[0].special_cooldown == 4.0, label + " release then fresh press starts immediately")
			settle(80); pulse(); settle(200)
			check(game.sim.attack_serial == 2 and game.sim.fighters[0].queued == "", label + " rejected cooldown press is not buffered until expiry")
			setup(kind, face); pulse("jump"); press(); step(); settle(120)
			check(game.sim.attack_serial == 0 and game.sim.fighters[0].special_cooldown == 0.0 and game.sim.fighters[0].y == 0.0, label + " rejected airborne held cast spends no cooldown and never fires on landing")
			release(); pulse()
			check(game.sim.fighters[0].attack == "special", label + " fresh grounded cast works after air rejection")
			setup(kind, face)
			var key := InputEventKey.new()
			key.physical_keycode = KEY_O; key.pressed = true
			game._input(key); step()
			check(game.sim.fighters[0].attack == "special" and game.held.get("special", false) and not game.held.get("roundhouse", false), label + " physical O maps independently to signature, not I roundhouse")
			key.echo = true
			for frame in range(300): game._input(key); step()
			check(game.sim.attack_serial == 1, label + " keyboard O repeat never recasts after cooldown")
			key.echo = false; key.pressed = false; game._input(key)
			key.pressed = true; game._input(key); step()
			check(game.sim.attack_serial == 2, label + " fresh O after release recasts")
			key.pressed = false; game._input(key)

func live_wave(kind: int, face: int = 1) -> bool:
	setup(kind, face)
	game.sim.fighters[1].invuln = 10.0 # Isolates a live wave, not a contact claim.
	pulse()
	for frame in range(50):
		step()
		if not game.sim.projectiles.is_empty(): return true
	return false

func pause_and_lifecycle_tests() -> void:
	for kind in range(2):
		for notification in [0, Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_PAUSED]:
			var label := "kind %d pause/background %d" % [kind, notification]
			check(live_wave(kind), label + " fixture reaches real emitted wave")
			press(); press("right")
			if notification == 0: game.toggle_pause()
			else: game._notification(notification)
			var frozen: Array = [game.sim.fighters.duplicate(true), game.sim.projectiles.duplicate(true), game.sim.time_left, game.anims[0].current_animation_position]
			step(0.5)
			check(game.paused and frozen == [game.sim.fighters, game.sim.projectiles, game.sim.time_left, game.anims[0].current_animation_position] and not game.meow_sound.playing, label + " freezes cast/projectile/cooldown/pose and stops meow")
			check(game.held.is_empty() and game.taps.is_empty() and not game.sim.fighters[0].special_held, label + " clears held input, tap, and special rearm state")
			game.toggle_pause(); settle(300)
			check(game.sim.attack_serial == 1 and game.sim.projectile_serial == 1, label + " resume cannot replay a stale cast or emission")
			pulse()
			check(game.sim.attack_serial == 2, label + " first fresh ready post-resume press works")
		for destination in ["menu", "rematch", "timeout"]:
			var label := "kind %d %s" % [kind, destination]
			check(live_wave(kind), label + " starts with a real cast and wave")
			press(); press("right")
			if destination == "menu": game.show_menu()
			elif destination == "rematch": game.hud._request_rematch()
			else: game.sim.time_left = DT * 0.5; step()
			check(game.sim.projectiles.is_empty() and game.projectile_view.views.is_empty() and game.held.is_empty() and game.taps.is_empty(), label + " removes waves and stale inputs immediately")
			if destination == "menu": game.hud._choose(1 - kind)
			elif destination == "timeout": settle(180)
			game.render_state(0.0)
			check(game.sim.attack_serial == 0 and game.sim.projectile_serial == 0 and game.sim.fighters[0].special_cooldown == 0.0 and game.emitter_positions.is_empty(), label + " reset or reselection clears cooldown, serials, and markers")
			pulse()
			check(game.sim.attack_serial == 1 and game.sim.fighters[0].attack == "special", label + " fresh cast after reset is immediately accepted")



func owner_crossup_impact_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			setup(kind, face); pulse()
			for frame in range(50):
				step()
				if game.sim.projectile_serial == 1: break
			# Owner-position fixture after genuine emission. The wave keeps its
			# original path while the owner is now beyond the target's far side.
			game.sim.fighters[0].x = 1.95 * face
			var verified := false
			for frame in range(80):
				var events := step()
				var swept := Vector2(INF, INF)
				for event: Dictionary in events:
					if event.type == "projectile_despawn" and event.reason == "contact": swept = event.pos
				for event: Dictionary in events:
					if event.type == "hit" and event.fighter == 1 and event.kind == ("meow" if kind == 0 else "heart"):
						var actual := Vector2(float(event.get("impact_x", INF)), event.impact_y)
						verified = actual.is_finite() and actual.distance_to(swept) < EPS and game.effects.size() == 1 and Vector2(game.effects[0].node.position.x, game.effects[0].node.position.y).distance_to(swept) < EPS and absf(swept.x - (game.sim.fighters[1].x + face * 0.27)) > 0.4
				if verified: break
			check(verified, "kind %d face %d spark remains on true swept impact side after owner crosses beyond target" % [kind, face])

func actual_interruption_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for after_emit in [false, true]:
				setup(kind, face)
				# Contact-distance + defender invulnerability fixtures isolate the
				# opponent's real jab interrupt without injecting a hit/projectile.
				game.sim.fighters[0].x = -0.35 * face
				game.sim.fighters[1].x = 0.35 * face
				game.sim.fighters[1].invuln = 10.0
				pulse()
				if after_emit:
					for frame in range(50):
						step()
						if game.sim.projectile_serial == 1: break
				robot.command = {"punch":true}
				var actual_hit := false
				var wave_survived := false
				var f: Dictionary = game.sim.fighters[0]
				for frame in range(35):
					for event: Dictionary in step():
						if event.type == "hit" and event.kind == "punch" and event.fighter == 0:
							actual_hit = true
							wave_survived = not game.sim.projectiles.is_empty()
					if actual_hit: break
				check(actual_hit and f.attack == "" and f.hp == 92.0 and f.special_cooldown > 3.0 and f.special_cooldown < 4.0 and f.special_phase == "", "kind %d face %d %s actual opponent jab cancels cast without cooldown refund" % [kind, face, "post-emission" if after_emit else "startup"])
				if after_emit: check(wave_survived and game.sim.projectile_serial == 1, "kind %d face %d already emitted wave survives real owner hit" % [kind, face])
				robot.command = {}; settle(120)
				check(game.sim.projectile_serial == (1 if after_emit else 0) and f.y == 0.0 and game.sim.projectiles.is_empty(), "kind %d face %d interrupt never emits a stale wave and body safely lands" % [kind, face])

func audio_tests() -> void:
	var wav: AudioStreamWAV = game.audio_pool.cue_streams["meow"][0]
	check(wav != null and wav.resource_path == "res://assets/audio/meow.wav" and not game.meow_sound.autoplay and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED, "dedicated packaged meow WAV is non-autoplay and non-looping")
	var source_wav := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://assets/audio/meow.wav"))
	print("MEOW IMPORT format=", wav.format, "; bytes=", wav.data.size(), "; length=", wav.get_length(), "; rate=", wav.mix_rate)
	check(source_wav != null and source_wav.mix_rate == 48000 and source_wav.format == AudioStreamWAV.FORMAT_16_BITS and not source_wav.stereo and source_wav.data.size() == 46042 and absf(source_wav.get_length() - 0.4796041667) < EPS, "meow source is complete mono 48 kHz PCM recorded vocalization, not combat tone")
	check(wav.mix_rate == 48000 and not wav.stereo and absf(wav.get_length() - source_wav.get_length()) < 0.001, "Godot imported stream preserves source rate, channels, and duration despite allowed compression")
	var source := "res://assets/audio/originals/bigsoundbank_0494_original.wav"
	check(FileAccess.file_exists(source) and FileAccess.get_sha256(source) == "a3af64f8c9dd921343f076d7ed3bcfc9d0f7db49b84e6a81c84fae72d1c8b38d" and FileAccess.get_sha256("res://assets/audio/meow.wav") == "551cc7c8a4c90e6a120de466707ba36670f05dc8e0d96223a8a355b47cfd3eb2", "recorded source and processed WAV retain documented SHA-256 provenance")
	var license: String = FileAccess.get_file_as_string("res://docs/MEOW-AUDIO-LICENSE.txt")
	check("CC0" in license and "https://bigsoundbank.com/little-meow-of-a-cat-s0494.html" in license and "Auditory validation was NOT possible" in license, "source/license and honest non-auditory validation limit are packaged")
	setup(0); game.hud.mute_requested.emit(); pulse(); settle(26)
	check(game.muted and not game.meow_sound.playing and game.sim.projectile_serial == 1, "actual HUD mute suppresses emitted meow while projectile still works")
	setup(0); game.sound_enabled = false; robot.command = {"special":true}; settle(26)
	check(game.sim.projectile_serial == 0 and not game.meow_sound.playing, "yellow AI early startup produces no accidental meow/autoplay")
	setup(1); game.sound_enabled = false; robot.command = {"special":true}; settle(26)
	check(game.sim.projectile_serial == 1 and not game.meow_sound.playing and game.sound.stream == null, "actual purple AI cast with audio locked emits its wave without autoplay")
	setup(0); pulse(); settle(24)
	check(game.sim.projectile_serial == 1 and game.meow_sound.playing, "user-enabled purple emission starts dedicated WAV playback state (not hardware audibility)")
	game.hud.mute_requested.emit()
	check(not game.meow_sound.playing, "muting stops an already playing meow")
	setup(1); pulse(); settle(30)
	check(game.sim.projectile_serial == 1 and not game.meow_sound.playing, "yellow heart never plays cat vocalization")

func touch_tests() -> void:
	for kind in range(2):
		setup(kind)
		await process_frame; await process_frame
		var badge: Button = game.hud._touch_buttons["special"]
		var caption := "喵波" if kind == 0 else "爱心波"
		check(game.hud._touch_buttons.size() == 5 and game.hud._direction_pad != null and badge.text == caption and "O" in badge.tooltip_text, "kind %d actual main HUD retains continuous direction pad and five separately named attacks" % kind)
		var actions_present := true
		for action: String in ACTIONS: actions_present = actions_present and game.hud._touch_buttons.has(action)
		check(actions_present, "kind %d all five attack mappings survive directional-pad revision" % kind)
		var touch := InputEventScreenTouch.new()
		touch.index = 12; touch.position = badge.get_global_rect().get_center(); touch.pressed = true
		game.hud._input(touch); step()
		check(game.sim.fighters[0].attack == "special" and game.sim.attack_serial == 1 and badge.disabled and game.hud._special_cooldown_overlay.visible, "kind %d real screen touch routes HUD signal through main and starts cooldown display" % kind)
		touch.pressed = false; game.hud._input(touch)
		check(not game.held.get("special", false) and game.hud._touch_contacts.is_empty(), "kind %d touch release clears main hold even when cooldown disabled the button" % kind)
		var cd: float = game.sim.fighters[0].special_cooldown
		step()
		check(absf(game.hud._special_cd - game.sim.fighters[0].special_cooldown) < EPS and game.hud._special_cd < cd, "kind %d countdown follows actual main simulation, not an independent timer" % kind)
		game.toggle_pause(); var frozen: float = game.hud._special_cd; step(0.5)
		check(game.hud._special_cd == frozen, "kind %d paused HUD cooldown stays frozen" % kind)

func run_tests() -> void:
	# A real supported viewport is required for touch hit testing, not headless 64x64.
	root.size = Vector2i(960,600)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/signature_markers.json")) if FileAccess.file_exists("res://assets/signature_markers.json") else null
	if parsed is Dictionary: independent_markers = parsed
	game = load("res://main.tscn").instantiate()
	root.add_child(game); game.set_physics_process(false)
	await process_frame
	check(not game.meow_sound.playing and not game.meow_sound.autoplay and not game.sound_enabled, "fresh main menu never starts meow or unlocks audio")
	for path in ["res://assets/purple.glb", "res://assets/yellow.glb"]:
		var reference := Node3D.new(); root.add_child(reference); reference.hide()
		var model: Node3D = load(path).instantiate(); model.scale = Vector3.ONE * 1.2; reference.add_child(model)
		reference_roots.append(reference)
		var player: AnimationPlayer = game.find_animation(reference)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		reference_players.append(player)
	asset_tests()
	cast_and_feedback_tests()
	actual_bone_pose_tests()
	exact_phase_and_large_step_tests()
	input_and_cooldown_tests()
	pause_and_lifecycle_tests()
	owner_crossup_impact_tests()
	actual_interruption_tests()
	audio_tests()
	await touch_tests()
	print("SIGNATURE BONE POSES samples=", verified_bone_pose_samples, "; maximum world-origin error=", maximum_bone_origin_error, "; maximum world-basis error=", maximum_bone_basis_error)
	print("SIGNATURE OBSERVED EMISSIONS ", JSON.stringify(observed_emissions))
	print("Signature scene checks: ", checks, "; failures: ", failures, "; missing assets: ", missing_assets.size(), "; verified paired pose samples: ", verified_pose_samples, "; fallback samples: ", fallback_pose_samples, "; verified marker samples: ", verified_marker_samples, "; strict assets: ", require_new)
	if not missing_assets.is_empty(): print("NOT ASSET-READY: diagnostic mechanics result only; final paired clips and complete non-WIP mouth/two-hand records are unverified.")
	print("LIMITED QA: deterministic real-main headless integration, not visual/native/browser/mobile/audio-hardware certification.")
	game.queue_free()
	for reference: Node3D in reference_roots: reference.queue_free()
	await process_frame
	quit(mini(failures, 255))
