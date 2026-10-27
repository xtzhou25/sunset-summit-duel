extends SceneTree
## Deterministic behavioral edge checks, run with:
## godot --headless --path . --script tests/edge_test.gd
## Does not modify gameplay resources. Snapshot repositioning is explicitly
## identified where a test isolates an attack phase or committed-facing rule.
const Combat = preload("res://scripts/combat.gd")
const DT := 1.0 / 60.0
const EPS := 0.00001
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		printerr("FAIL: ", label)

func close_fixture(kind: int = 0):
	var sim = Combat.new()
	sim.reset(kind)
	sim.fighters[0].x = -Combat.BODY
	sim.fighters[1].x = Combat.BODY
	return sim

func cmd(attack: String) -> Dictionary:
	return {attack: true}

func event_count(sim, event_type: String, target: int = -1) -> int:
	var count := 0
	for event: Dictionary in sim.events:
		if event.type == event_type and (target < 0 or int(event.get("fighter", -1)) == target):
			count += 1
	return count

func attack_phase_tests() -> void:
	for kind in range(2):
		for attack in ["punch", "kick"]:
			var sim = close_fixture(kind)
			var config: Dictionary = sim.attack_config(sim.fighters[0], attack)
			var label := "kind %d %s" % [kind, attack]
			var startup_samples := 0
			var premature_damage := false
			var hit_events := 0
			var active_hit_seen := false
			sim.step(DT, [cmd(attack), {}])
			for frame in range(100):
				var fighter: Dictionary = sim.fighters[0]
				if fighter.attack == "":
					break
				if float(fighter.clock) < float(config.startup):
					startup_samples += 1
					premature_damage = premature_damage or sim.fighters[1].hp < 100.0
				var hits := event_count(sim, "hit", 1)
				if hits > 0:
					active_hit_seen = float(fighter.clock) >= float(config.startup) and float(fighter.clock) < float(config.startup + config.active)
					hit_events += hits
				sim.step(DT, [{}, {}])
			check(startup_samples >= 8 and not premature_damage, label + " never damages during observed startup")
			check(active_hit_seen and hit_events == 1 and is_equal_approx(sim.fighters[1].hp, 100.0 - float(config.damage)), label + " deals exactly one correctly timed active hit")
			# Whiff through the entire active window, then place the opponent in
			# reach during recovery. This isolates recovery hitbox deactivation.
			sim = close_fixture(kind)
			sim.fighters[0].x = Combat.LEFT
			sim.fighters[1].x = Combat.RIGHT
			sim.step(DT, [cmd(attack), {}])
			while float(sim.fighters[0].clock) < float(config.startup + config.active) + DT:
				sim.step(DT, [{}, {}])
			var recovery_samples := 0
			var recovery_damage := false
			while sim.fighters[0].attack != "":
				sim.fighters[1].x = minf(Combat.RIGHT, float(sim.fighters[0].x) + Combat.BODY * 2.0)
				sim.fighters[1].y = 0.0
				sim.step(DT, [{}, {}])
				recovery_samples += 1
				recovery_damage = recovery_damage or sim.fighters[1].hp < 100.0
			check(recovery_samples >= 10 and not recovery_damage, label + " cannot hit a newly entering target during recovery")

func committed_facing_tests() -> void:
	for attack in ["punch", "kick"]:
		var sim = close_fixture()
		sim.step(DT, [cmd(attack), {}])
		var committed_face: int = sim.fighters[0].face
		# Simulate the opponent completing a cross-up after attack commitment.
		# The attack must not retarget its already-committed facing direction.
		sim.fighters[1].x = -1.3
		var stable := true
		var samples := 0
		while sim.fighters[0].attack != "":
			stable = stable and sim.fighters[0].face == committed_face
			samples += 1
			sim.step(DT, [{}, {}])
		check(samples > 20 and stable and sim.fighters[1].hp == 100.0, attack + " keeps committed facing and does not hit opponent behind")
		check(sim.fighters[0].face == -1, attack + " reacquires opponent facing only after attack ends")

func chain_tests() -> void:
	for kind in range(2):
		var sim = close_fixture(kind)
		sim.fighters[0].x = Combat.LEFT
		sim.fighters[1].x = Combat.RIGHT
		var starts: Array[float] = []
		var attack_kinds: Array[String] = []
		var max_chain := 0
		var locked_samples := 0
		var attack_during_lock := false
		var first_lock_time := -1.0
		var queued_second := false
		var straight_config: Dictionary = sim.attack_config(sim.fighters[0], "straight")
		var straight_duration: float = straight_config.startup + straight_config.active + straight_config.recovery
		for frame in range(180):
			var fighter: Dictionary = sim.fighters[0]
			var pre_lock := float(fighter.land_lock)
			var command: Dictionary = {}
			if frame == 0:
				command.punch = true
			elif fighter.attack == "punch" and fighter.chain == 1 and not queued_second and fighter.clock + DT >= fighter.duration - Combat.PUNCH_BUFFER_WINDOW + EPS:
				# A distinct late press, not a held input, requests the rear straight.
				command.punch = true
				queued_second = true
			elif fighter.attack == "straight" or pre_lock > 0.0:
				# Repeated fresh third presses stress both the committed second
				# attack and its mandatory recovery; neither may be cancelled.
				command.punch = frame % 2 == 0
			elif starts.size() == 2 and fighter.attack == "":
				command.punch = true
			sim.step(DT, [command, {}])
			max_chain = maxi(max_chain, int(fighter.chain))
			if event_count(sim, "attack") > 0:
				starts.append(float(sim.elapsed))
				attack_kinds.append(fighter.attack)
				attack_during_lock = attack_during_lock or pre_lock > DT + EPS
			if fighter.attack == "" and float(fighter.land_lock) > 0.0:
				locked_samples += 1
				if first_lock_time < 0.0:
					first_lock_time = float(sim.elapsed)
			if starts.size() >= 3:
				break
		check(starts.size() == 3 and attack_kinds == ["punch", "straight", "punch"] and max_chain == 2, "kind %d fresh buffered presses form jab/straight, then a new jab burst" % kind)
		check(locked_samples >= 10 and not attack_during_lock, "kind %d cannot start third attack during chain lock" % kind)
		if starts.size() >= 3:
			check(starts[2] - starts[1] >= straight_duration + 0.19 - DT - EPS and starts[2] - first_lock_time >= 0.18, "kind %d third attack waits for full straight duration plus measurable extra recovery" % kind)

func guard_tests() -> void:
	for attacker in range(2):
		var defender := 1 - attacker
		var retreat := 1.0 if defender == 1 else -1.0
		for use_retreat in [true, false]:
			var sim = close_fixture()
			# Wall pin isolates correct/wrong-direction guard from spacing escape.
			sim.fighters[defender].x = Combat.RIGHT if retreat > 0.0 else Combat.LEFT
			sim.fighters[attacker].x = sim.fighters[defender].x - retreat * Combat.BODY * 2.0
			var configs: Array = [{}, {}]
			configs[attacker] = {"punch": true}
			configs[defender] = {"move": retreat if use_retreat else -retreat}
			sim.step(DT, configs)
			configs[attacker] = {}
			var blocks := 0
			var hits := 0
			for frame in range(20):
				sim.step(DT, configs)
				blocks += event_count(sim, "block", defender)
				hits += event_count(sim, "hit", defender)
			if use_retreat:
				check(blocks == 1 and hits == 0 and sim.fighters[defender].hp == 100.0 and sim.fighters[defender].guard < 78.0, "side %d frontal retreat blocks once and consumes guard" % attacker)
			else:
				check(blocks == 0 and hits == 1 and sim.fighters[defender].hp == 92.0, "side %d wrong-direction movement cannot guard incoming attack" % attacker)
	var sim = close_fixture()
	# A low-guard target stays in measured reach until the hand extends.
	sim.fighters[1].x = Combat.RIGHT
	sim.fighters[0].x = Combat.RIGHT - Combat.BODY * 2.0
	sim.fighters[1].guard = 10.0
	sim.fighters[1].guard_delay = 10.0
	sim.step(DT, [{"punch": true}, {"move": 1.0}])
	var breaks := 0
	var break_stun := 0.0
	for frame in range(20):
		sim.step(DT, [{}, {"move": 1.0}])
		if event_count(sim, "break", 1) > 0:
			breaks += 1
			break_stun = sim.fighters[1].stun
	check(breaks == 1 and sim.fighters[1].guard == 0.0 and sim.fighters[1].hp == 92.0, "insufficient frontal guard breaks and takes normal hit damage")
	check(break_stun >= 0.40 and not sim.fighters[1].blocking and sim.fighters[1].guard_delay > 1.5, "guard break adds stun and prevents instant re-guard/regeneration")
	sim = close_fixture()
	sim.step(DT, [{"punch": true}, {"jump": true, "move": 1.0}])
	var aerial_block := false
	for frame in range(18):
		sim.step(DT, [{}, {"move": 1.0}])
		aerial_block = aerial_block or event_count(sim, "block", 1) > 0 or (sim.fighters[1].y > 0.001 and sim.fighters[1].blocking)
	check(not aerial_block, "holding retreat while airborne never enables guard")

func rear_contact_snapshot_test() -> void:
	# Isolate the frontal-only guard predicate with a deliberate contact
	# snapshot: fighter 0 establishes left-facing guard, then fighter 1 slides
	# across its rear in the same step. Opposite-facing lateral velocity is
	# injected here to exercise the defensive invariant, not claimed to be a
	# player-accessible move. No guard flag or damage result is injected.
	var sim = close_fixture()
	var defender: Dictionary = sim.fighters[0]
	var attacker: Dictionary = sim.fighters[1]
	defender.x = 0.0
	attacker.x = -0.005
	attacker.y = 0.60
	attacker.face = -1
	sim.begin_attack(attacker, "kick")
	attacker.clock = float(sim.attack_config(attacker, "kick").startup) - DT + 0.0001
	attacker.vx = 2.1
	attacker.vy = 0.0
	sim.step(DT, [{"move": 1.0}, {}])
	check(attacker.x > defender.x and defender.face == -1 and event_count(sim, "hit", 0) == 1 and defender.hp == 87.0, "rear-contact snapshot bypasses established wrong-facing guard")
	check(event_count(sim, "block", 0) == 0 and event_count(sim, "break", 0) == 0 and defender.guard > 99.0, "rear contact is an ordinary hit, not a frontal block or guard break")

func trade_tests() -> void:
	for lethal in [false, true]:
		var sim = close_fixture()
		if lethal:
			sim.fighters[0].hp = 8.0
			sim.fighters[1].hp = 8.0
		sim.step(DT, [{"punch": true}, {"punch": true}])
		var simultaneous_hits := 0
		for frame in range(20):
			sim.step(DT, [{}, {}])
			simultaneous_hits = maxi(simultaneous_hits, event_count(sim, "hit"))
			if simultaneous_hits == 2:
				break
		var remaining := 0.0 if lethal else 92.0
		check(simultaneous_hits == 2 and sim.fighters[0].hp == remaining and sim.fighters[1].hp == remaining, "simultaneous %s strikes both resolve without fighter-index priority" % ("lethal" if lethal else "nonlethal"))
		if lethal:
			check(sim.round_over and sim.winner == -1 and event_count(sim, "round") == 1, "double knockout produces one draw result")
		else:
			check(not sim.round_over and sim.fighters[0].stun > 0 and sim.fighters[1].stun > 0, "nonlethal trade stuns both and keeps round running")
	var sim = close_fixture()
	sim.time_left = DT * 0.5
	sim.step(DT, [{}, {}])
	check(sim.round_over and sim.winner == -1, "equal-health timeout is a draw")

func aerial_and_wall_tests() -> void:
	# Real jump + opposing movement, no injected airborne positions/velocities.
	var sim = close_fixture()
	var initial_order: bool = sim.fighters[0].x < sim.fighters[1].x
	var crossed := false
	var crossed_while_airborne := false
	var peak := 0.0
	for frame in range(65):
		var first := {"move": 1.0}
		if frame == 0:
			first.jump = true
		sim.step(DT, [first, {"move": -1.0}])
		peak = maxf(peak, float(sim.fighters[0].y))
		if sim.fighters[0].x > sim.fighters[1].x:
			crossed = true
			crossed_while_airborne = crossed_while_airborne or sim.fighters[0].y > 0.55
	check(initial_order and peak > 0.55 and crossed and crossed_while_airborne, "actual jump permits intentional apex cross-up during opposing movement")
	check(sim.fighters[0].y == 0.0 and absf(sim.fighters[0].x - sim.fighters[1].x) >= Combat.BODY * 2.0 - EPS, "ground pushboxes separate fighters again after aerial cross-up lands")
	for side in [-1.0, 1.0]:
		for reversed_order in [false, true]:
			sim = close_fixture()
			var boundary: float = Combat.RIGHT if side > 0 else Combat.LEFT
			sim.fighters[0].x = boundary - side * 0.10
			sim.fighters[1].x = boundary
			if reversed_order:
				var x: float = sim.fighters[0].x
				sim.fighters[0].x = sim.fighters[1].x
				sim.fighters[1].x = x
			var expected_order: float = signf(sim.fighters[1].x - sim.fighters[0].x)
			var valid := true
			for frame in range(240):
				sim.step(DT, [{"move": side}, {"move": side}])
				var a: Dictionary = sim.fighters[0]
				var b: Dictionary = sim.fighters[1]
				valid = valid and a.x >= Combat.LEFT - EPS and a.x <= Combat.RIGHT + EPS and b.x >= Combat.LEFT - EPS and b.x <= Combat.RIGHT + EPS
				valid = valid and absf(a.x - b.x) >= Combat.BODY * 2.0 - EPS and signf(b.x - a.x) == expected_order
			check(valid, "wall %.0f order %s keeps ground separation/order and clamps both fighters for 240 frames" % [side, str(reversed_order)])

func _init() -> void:
	attack_phase_tests()
	committed_facing_tests()
	chain_tests()
	guard_tests()
	rear_contact_snapshot_test()
	trade_tests()
	aerial_and_wall_tests()
	print("Edge test checks: ", checks, "; failures: ", failures)
	quit(failures)
