extends SceneTree
## Actual v4 AI: delayed public observation, autonomous planned straight/heavy,
## finite reaction, and main-loop integration with zero player attack inputs.
## godot --headless --path . --script tests/ai_variation_test.gd
const Combat = preload("res://scripts/combat.gd")
const Brain = preload("res://scripts/ai.gd")
const DT := 1.0 / 60.0
const EPS := 0.00001
class PublicWorld extends RefCounted:
	# Deliberately contains no user commands, taps, held inputs, or private buffers.
	var fighters: Array = [
		{"x":-1.0, "y":0.0, "attack":""},
		{"x":1.0, "y":0.0, "face":-1, "attack":"", "attack_id":0, "duration":0.0, "clock":0.0, "guard":100.0}
	]
var checks := 0
var failures := 0
var game

func _initialize() -> void: call_deferred("run_tests")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else: failures += 1; printerr("FAIL: ", label)

func fresh_brain(seed_value: int = 607122):
	var brain = Brain.new()
	brain.rng.seed = seed_value
	brain.reset()
	return brain

func observation_tests() -> void:
	var brain = fresh_brain()
	var public_world := PublicWorld.new()
	var quiet := true
	for frame in range(14):
		var command: Dictionary = brain.act(public_world, DT)
		quiet = quiet and command.get("move", 0.0) == 0.0 and not command.get("punch", false) and not command.get("heavy", false) and not command.get("kick", false) and not command.get("jump", false)
	check(quiet and is_equal_approx(brain.reaction, 0.24), "actual AI has finite 240 ms reaction and no early actions with only public world fields")
	var responded := false
	for frame in range(30): responded = brain.act(public_world, DT).get("move", 0.0) == -1.0 or responded
	check(responded and brain.snapshots.size() <= 16, "actual AI eventually reacts and maintains a bounded delayed observation history")

	# Two identical histories, then a sudden public position reversal in one.
	# Before the 240 ms observation delay, their commands must remain identical.
	var first = fresh_brain(19)
	var second = fresh_brain(19)
	var world_a := PublicWorld.new()
	var world_b := PublicWorld.new()
	for frame in range(40): first.act(world_a, DT); second.act(world_b, DT)
	world_b.fighters[0].x = 3.0
	var delayed := true
	for frame in range(13): delayed = first.act(world_a, DT) == second.act(world_b, DT) and delayed
	check(delayed, "actual AI cannot react to a fresh opponent cross-up before delayed snapshots mature")
	var diverged := false
	for frame in range(50):
		var a: Dictionary = first.act(world_a, DT)
		var b: Dictionary = second.act(world_b, DT)
		diverged = (a.get("move", 0.0) == -1.0 and b.get("move", 0.0) == 1.0) or diverged
	check(diverged, "matured public cross-up eventually changes AI movement, not permanent blindness")

	# Same public history, radically different unpublished player input/buffer state.
	var sim_a = Combat.new()
	var sim_b = Combat.new()
	first = fresh_brain(53); second = fresh_brain(53)
	var independent := true
	for frame in range(240):
		var opponent: Dictionary = sim_b.fighters[0]
		opponent.punch_held = frame % 2 == 0
		opponent.heavy_held = frame % 3 == 0
		opponent.queued = "straight" if frame % 2 == 0 else ""
		opponent.queued_attack_id = frame
		opponent.input_rearm = frame % 5 == 0
		independent = first.act(sim_a, DT) == second.act(sim_b, DT) and independent
	check(independent, "actual AI decisions ignore opponent private held edges and queued follow-ups")

func own_plan_tests() -> void:
	var found_planner := false
	for seed_value in range(1, 65):
		var brain = fresh_brain(seed_value)
		var world := PublicWorld.new()
		var self_f: Dictionary = world.fighters[1]
		# Explicit public self-attack fixture isolates planning from hit outcomes.
		self_f.attack = "punch"; self_f.attack_id = 31; self_f.duration = 0.48
		var emitted := 0
		var earliest := 100.0
		var tied_to_own_id := true
		for frame in range(29):
			self_f.clock = frame * DT
			var command: Dictionary = brain.act(world, DT)
			if command.get("punch", false): emitted += 1; earliest = minf(earliest, self_f.clock)
			tied_to_own_id = tied_to_own_id and brain.combo_attack_id == 31
		if emitted > 0:
			found_planner = true
			check(emitted == 1 and earliest >= self_f.duration - 0.10 - EPS and earliest < self_f.duration and tied_to_own_id and brain.combo_sent, "AI independently plans one late follow-up tied to its own jab attack id")
			brain.reset()
			check(brain.combo_attack_id == -1 and not brain.combo_wanted and not brain.combo_sent and brain.snapshots.is_empty() and is_equal_approx(brain.remaining, 0.25), "AI reset drops own combo plan and delayed observation history")
			break
	check(found_planner, "deterministic seeded actual AI can choose a straight plan without user input")

func actual_main_loop_tests() -> void:
	for kind in range(2):
		game.brain = fresh_brain(607122 + kind)
		game.hud._choose(kind)
		game.set_physics_process(false)
		game.auto_demo = false
		game.muted = true
		# Endurance health/time fixture avoids a round reset obscuring move counts.
		game.sim.time_left = 600.0
		game.sim.fighters[0].hp = 100000.0
		game.sim.fighters[1].hp = 100000.0
		game.sim.fighters[0].x = Combat.LEFT
		game.sim.fighters[1].x = Combat.LEFT + 0.79
		var seen_ids: Dictionary = {}
		var counts := {"punch":0, "straight":0, "heavy":0, "kick":0, "roundhouse":0,"special":0}
		var previous_attack := ""
		var straight_is_planned := true
		var queue_observed := false
		var queue_timed := true
		var finite := true
		var no_player_input := true
		var own_id := -1
		var frames_run := 0
		for frame in range(12000):
			game._physics_process(DT)
			frames_run += 1
			var self_f: Dictionary = game.sim.fighters[1]
			finite = finite and is_finite(game.brain.remaining) and is_finite(game.brain.reaction) and game.brain.reaction >= 0.20 and game.brain.snapshots.size() <= 16
			no_player_input = no_player_input and game.held.is_empty() and game.taps.is_empty() and game.sim.fighters[0].attack == ""
			if self_f.queued == "straight":
				queue_observed = true
				own_id = self_f.attack_id
				queue_timed = queue_timed and self_f.attack == "punch" and self_f.queued_attack_id == self_f.attack_id and game.brain.combo_sent and game.brain.combo_attack_id == self_f.attack_id and self_f.duration - self_f.clock <= 0.10 + EPS
			if self_f.attack != "" and not seen_ids.has(self_f.attack_id):
				seen_ids[self_f.attack_id] = true
				counts[self_f.attack] += 1
				if self_f.attack == "straight": straight_is_planned = straight_is_planned and previous_attack == "punch" and game.brain.combo_attack_id == own_id and game.brain.combo_sent and self_f.chain == 2 and self_f.clock == 0.0
				previous_attack = self_f.attack
			if counts.straight >= 3 and counts.heavy >= 3 and counts.kick >= 1 and counts.roundhouse >= 1: break
		check(counts.punch > 0 and counts.straight >= 3 and counts.heavy >= 3, "kind %d actual main-loop AI independently emits jabs, at least three straights, and at least three heavies" % kind)
		check(counts.roundhouse >= 1, "kind %d actual main-loop AI independently emits the new roundhouse" % kind)
		check(queue_observed and queue_timed and straight_is_planned, "kind %d actual AI straight is its own bounded planned follow-up, not injected scene input" % kind)
		check(no_player_input and finite and not game.sim.round_over, "kind %d AI remains finite/reactive while player supplies no commands" % kind)
		print("AI SAMPLE kind=", kind, " frames=", frames_run, " attacks=", counts)
		game.hud._request_rematch()
		check(game.brain.combo_attack_id == -1 and not game.brain.combo_sent and game.brain.snapshots.is_empty() and game.sim.attack_serial == 0, "kind %d real rematch clears AI planned follow-up" % kind)

func run_tests() -> void:
	observation_tests()
	own_plan_tests()
	game = load("res://main.tscn").instantiate()
	root.add_child(game); game.set_physics_process(false)
	await process_frame
	actual_main_loop_tests()
	print("AI variation checks: ", checks, "; failures: ", failures)
	game.queue_free(); await process_frame
	quit(mini(failures, 255))
