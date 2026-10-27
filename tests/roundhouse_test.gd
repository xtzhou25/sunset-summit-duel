extends SceneTree
## v5 deterministic grounded roundhouse. These are simulation checks, not proof
## of visual quality/support-foot contact. Measured-foot numeric curves are checked.
## Run: godot --headless --path . --script tests/roundhouse_test.gd
const Combat = preload("res://scripts/combat.gd")
const DT := 1.0 / 60.0
const EPS := 0.00001
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else: failures += 1; printerr("FAIL: ", label)

func fixture(kind: int = 0, face: int = 1, distant: bool = false):
	var sim = Combat.new()
	sim.reset(kind)
	sim.fighters[1].x = Combat.RIGHT if face == 1 else Combat.LEFT
	sim.fighters[0].x = -sim.fighters[1].x if distant else sim.fighters[1].x - face * Combat.BODY * 2.0
	sim.fighters[0].face = face
	sim.fighters[1].face = -face
	return sim

func tick(sim, frames: int, first: Dictionary = {}, second: Dictionary = {}) -> void:
	for frame in range(frames): sim.step(DT, [first, second])

func count_event(sim, event_type: String, kind: String = "", target: int = -1) -> int:
	var result := 0
	for event: Dictionary in sim.events:
		if event.type == event_type and (kind == "" or event.get("kind", "") == kind) and (target == -1 or event.get("fighter", -1) == target): result += 1
	return result

func finish_attack(sim, defense: Dictionary = {}) -> void:
	for frame in range(120):
		if sim.fighters[0].attack == "": return
		sim.step(DT, [{}, defense])

func queue_straight(sim) -> void:
	var f: Dictionary = sim.fighters[0]
	for frame in range(60):
		if f.clock + DT >= f.duration - Combat.PUNCH_BUFFER_WINDOW + EPS: break
		sim.step(DT, [{}, {}])
	sim.step(DT, [{"punch": true}, {}])

func active_snapshot(sim, attack: String = "roundhouse") -> void:
	# Repeated contact fixture. Do not inject defender HP, down phase or immunity.
	var f: Dictionary = sim.fighters[0]
	var o: Dictionary = sim.fighters[1]
	f.x = o.x + o.face * Combat.BODY * 2.0
	if f.x < Combat.LEFT or f.x > Combat.RIGHT: f.x = o.x - o.face * Combat.BODY * 2.0
	f.face = 1 if o.x >= f.x else -1
	f.y = 0.0; f.vy = 0.0; f.vx = 0.0
	f.attack = attack; f.state = attack; f.hit = false
	f.clock = (Combat.ROUNDHOUSE_PEAK if attack == "roundhouse" else 0.19) - DT + EPS
	var config: Dictionary = sim.attack_config(f, attack)
	f.duration = config.startup + config.active + config.recovery

func config_and_edge_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			var sim = fixture(kind, face, true)
			var f: Dictionary = sim.fighters[0]
			var config: Dictionary = sim.attack_config(f, "roundhouse")
			check(config == {"startup":0.28,"active":0.14,"recovery":0.48 if kind==0 else 0.54,"reach":1.40,"damage":13.0,"guard":30.0,"stun":0.28,"push":0.30,"low":0.7846265172958375 if kind==0 else 0.7802888488769532,"high":1.1684436178207398 if kind==0 else 1.1709970092773438}, label + " measured roundhouse cap/envelope keeps timing and damage config explicit")
			check(is_equal_approx(config.startup + config.active + config.recovery, 0.90 if kind == 0 else 0.96) and is_equal_approx(Combat.ROUNDHOUSE_PEAK, 0.35), label + " final .90/.96 total, .28-.42 active, .35 peak timing")
			check(not Combat.ROUNDHOUSE_REACH_PROVISIONAL and sim.effective_reach(f, "roundhouse", 0.28) < 0.75 and sim.effective_reach(f, "roundhouse", 0.35) == 1.40, label + " measured foot extension replaces provisional static reach and caps the .35 peak")
			for move in ["punch", "straight", "heavy", "kick"]:
				var move_config: Dictionary = sim.attack_config(f, move)
				var geometry: Dictionary = sim.contact_geometry(f, move, 0.35)
				check(geometry == {"reach":sim.effective_reach(f, move, 0.35),"low":move_config.low,"high":move_config.high,"depth_overlap":true}, label + " " + move + " unified contact geometry preserves current reach/height and exposes future depth gate")
			sim.step(DT, [{"roundhouse": true, "move": float(face)}, {}])
			check(f.attack == "roundhouse" and f.state == "roundhouse" and f.clock == 0.0 and f.chain == 1 and sim.attack_serial == 1 and count_event(sim, "attack", "roundhouse") == 1, label + " first fresh press starts immediately with standard attack event")
			var starts := 1
			var stationary := true
			var start_x: float = f.x
			for frame in range(200):
				# Movement during the attack may not turn a pivot into a flying kick.
				var movement: float = float(face) if f.attack != "" else 0.0
				sim.step(DT, [{"roundhouse": true, "move": movement}, {}])
				starts += count_event(sim, "attack")
				if f.attack != "": stationary = stationary and f.x == start_x and f.vx == 0.0 and f.y == 0.0 and f.vy == 0.0
			check(starts == 1 and f.attack == "" and f.queued == "" and f.roundhouse_held, label + " held roundhouse never repeats or buffers after full recovery")
			check(stationary, label + " no root slide or jump throughout startup/active/recovery")
			sim.step(DT, [{}, {}]); sim.step(DT, [{"roundhouse": true}, {}])
			check(f.attack == "roundhouse" and sim.attack_serial == 2, label + " release then fresh roundhouse starts normally")

func measured_surface_tests() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/ROUNDHOUSE-ACTIVE-SURFACE-CURVES.json"))
	check(FileAccess.get_sha256("res://docs/ROUNDHOUSE-ACTIVE-SURFACE-CURVES.json") == "00f24cdf13302925c8d1e171cef5739aea5fb5e7484af1c05c0bf7d35e62ebdc", "copied actual-GLB report matches verified source SHA256")
	check(report.padding_included == false, "source bounds are unpadded; runtime allowances are applied exactly once")
	for kind in range(2):
		var character: String = "Lavender" if kind == 0 else "YellowWhite"
		var samples: Array = report.characters[character].R
		check(samples.size() == 15 and samples == report.characters[character].L, character + " actual R/L source bounds are exactly identical across all 15 samples")
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			var sim = fixture(kind, face, true)
			var f: Dictionary = sim.fighters[0]
			for row: Dictionary in samples:
				var expected_bounds: Array = row.depth_x + row.height_y + row.forward_z
				var actual_bounds: Array = sim._roundhouse_surface_bounds(f, row.time)
				var same_bounds := true
				for axis in range(6): same_bounds = same_bounds and absf(actual_bounds[axis] - expected_bounds[axis]) < EPS
				check(same_bounds, label + " all six XYZ foot bounds match independent source at %.2f" % row.time)
				var geometry: Dictionary = sim.contact_geometry(f, "roundhouse", row.time)
				var plane: bool = row.depth_x[0] <= 0.25 and row.depth_x[1] >= -0.25
				check(absf(geometry.reach - minf(1.40, row.forward_z[1] + 0.04)) < EPS and absf(geometry.low - (row.height_y[0] - 0.06)) < EPS and absf(geometry.high - (row.height_y[1] + 0.06)) < EPS and geometry.depth_overlap == plane, label + " contact geometry applies .04 forward/.06 height and actual depth overlap at %.2f" % row.time)
				check(absf(sim.effective_reach(f, "roundhouse", row.time) - geometry.reach) < EPS, label + " debug effective reach equals collector geometry at %.2f" % row.time)
			for index in range(samples.size() - 1):
				var before: Dictionary = samples[index]
				var after: Dictionary = samples[index + 1]
				var seconds: float = before.time + 0.005
				var expected_before: Array = before.depth_x + before.height_y + before.forward_z
				var expected_after: Array = after.depth_x + after.height_y + after.forward_z
				var actual: Array = sim._roundhouse_surface_bounds(f, seconds)
				var interpolated := true
				for axis in range(6): interpolated = interpolated and absf(actual[axis] - (expected_before[axis] + expected_after[axis]) * 0.5) < EPS
				check(interpolated, label + " independent XYZ bounds linearly interpolate halfway at %.3f" % seconds)
			check(sim._roundhouse_surface_bounds(f, 0.0) == sim._roundhouse_surface_bounds(f, 0.28) and sim._roundhouse_surface_bounds(f, 3.0) == sim._roundhouse_surface_bounds(f, 0.42), label + " surface reads outside sampled range safely clamp endpoints")
			f.clock = 0.35
			check(sim.contact_geometry(f, "roundhouse") == sim.contact_geometry(f, "roundhouse", 0.35) and sim.effective_reach(f, "roundhouse") == sim.contact_geometry(f, "roundhouse").reach, label + " omitted absolute time consistently reads fighter clock without recursion")
			# Distinguish nominal active from actual foot entering/leaving the
			# opponent's depth band. This is deliberately not a hardcoded subwindow.
			for seconds in [0.28, 0.30, 0.32, 0.325, 0.33, 0.35, 0.40, 0.41]:
				sim = fixture(kind, face); f = sim.fighters[0]
				sim.begin_attack(f, "roundhouse"); f.clock = seconds
				sim.step(0.0, [{}, {}])
				var expected: bool = seconds >= 0.33 and seconds <= 0.40
				check(sim.fighters[1].hp == (87.0 if expected else 100.0) and (count_event(sim, "hit", "roundhouse", 1) == 1) == expected, label + " early/late off-plane foot cannot hit despite nominal active and close target at %.3f" % seconds)
			# Actual sub-sample crossings are derived from independent surface data.
			for crossing_index in [4, 12]:
				var row: Dictionary = samples[crossing_index]
				var next_row: Dictionary = samples[crossing_index + 1]
				var entering: bool = crossing_index == 4
				var axis: int = 1 if entering else 0
				var threshold: float = -0.25 if entering else 0.25
				var crossing: float = row.time + 0.01 * (threshold - row.depth_x[axis]) / (next_row.depth_x[axis] - row.depth_x[axis])
				for offset in [-EPS, EPS]:
					sim = fixture(kind, face); f = sim.fighters[0]
					sim.begin_attack(f, "roundhouse"); f.clock = crossing + offset
					sim.step(0.0, [{}, {}])
					var expected: bool = offset > 0.0 if entering else offset < 0.0
					check(sim.fighters[1].hp == (87.0 if expected else 100.0), label + " interpolated depth %s crossing %.6f offset %f" % ["entry" if entering else "exit", crossing, offset])
			for seconds in [0.33, 0.34, 0.35, 0.40]:
				var source_row: Dictionary = samples[roundi((seconds - 0.28) / 0.01)]
				var reach: float = minf(1.40, source_row.forward_z[1] + 0.04)
				for offset in [-EPS, 0.0, EPS]:
					sim = fixture(kind, face, true); f = sim.fighters[0]
					f.x = 0.0; sim.fighters[1].x = face * (reach + Combat.HURT_X + offset)
					sim.begin_attack(f, "roundhouse"); f.clock = seconds; sim.step(0.0, [{}, {}])
					check(sim.fighters[1].hp == (87.0 if offset <= 0.0 else 100.0), label + " actual interpolated forward boundary at %.2f plus separate hurtbox offset %f" % [seconds, offset])
			# A real command at almost peak range cannot receive full reach before
			# the authored sweep extends. No clocks/positions change after launch.
			sim = fixture(kind, face, true); f = sim.fighters[0]
			f.x = 0.0; sim.fighters[1].x = face * (1.40 + Combat.HURT_X - 0.005)
			sim.step(DT, [{"roundhouse": true}, {}])
			var first_hit := -1.0
			var hits := 0
			var early_damage := false
			for frame in range(70):
				sim.step(DT, [{}, {}])
				if f.attack == "": break
				if f.clock < 0.34: early_damage = early_damage or sim.fighters[1].hp < 100.0
				if count_event(sim, "hit", "roundhouse", 1) > 0:
					hits += 1
					if first_hit < 0.0: first_hit = f.clock
			check(hits == 1 and not early_damage and first_hit >= 0.34 and first_hit <= 0.36 and sim.fighters[1].hp == 87.0, label + " normal input near maximum range connects exactly once near .35 peak, not nominal active onset")

func ground_only_and_busy_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			var sim = fixture(kind, face, true)
			sim.step(DT, [{"jump": true}, {}]); sim.step(DT, [{"roundhouse": true}, {}])
			var f: Dictionary = sim.fighters[0]
			check(f.y > 0.0 and f.attack == "" and sim.attack_serial == 0 and f.queued == "", label + " airborne press is rejected and consumed")
			tick(sim, 100, {"roundhouse": true})
			check(f.y == 0.0 and f.attack == "" and sim.attack_serial == 0, label + " held airborne rejection cannot auto-fire on landing")
			sim.step(DT, [{}, {}]); sim.step(DT, [{"roundhouse": true}, {}])
			check(f.attack == "roundhouse", label + " new ground press works after rejected air input")
			for airborne in [{"y":0.1,"vy":-1.0}, {"y":0.0,"vy":1.0}]:
				sim = fixture(kind, face, true); f = sim.fighters[0]
				f.y = airborne.y; f.vy = airborne.vy
				sim.begin_attack(f, "roundhouse")
				check(f.attack == "" and sim.attack_serial == 0, label + " public begin rejects above-ground or upward-velocity roundhouse %s" % airborne)
			for original in ["punch", "heavy", "roundhouse", "kick"]:
				sim = fixture(kind, face, true)
				sim.step(DT, [{original: true}, {}]); sim.step(DT, [{}, {}])
				f = sim.fighters[0]
				sim.step(DT, [{"roundhouse": true}, {}]); tick(sim, 150, {"roundhouse": true})
				check(sim.attack_serial == 1 and f.attack == "" and f.queued == "", label + " press during " + original + " is consumed, never a delayed roundhouse")
			# Existing landing locks also consume an early roundhouse edge.
			sim = fixture(kind, face, true); f = sim.fighters[0]; f.land_lock = 0.09
			sim.step(DT, [{"roundhouse": true}, {}]); tick(sim, 30, {"roundhouse": true})
			check(sim.attack_serial == 0 and f.attack == "", label + " held landing-lock press cannot bypass recovery")
			sim.step(DT, [{}, {}]); sim.step(DT, [{"roundhouse": true}, {}])
			check(f.attack == "roundhouse", label + " new post-landing-lock edge starts normally")

func contact_and_phase_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			for outcome in ["hit", "block", "break", "miss"]:
				var sim = fixture(kind, face, outcome == "miss")
				var f: Dictionary = sim.fighters[0]
				var o: Dictionary = sim.fighters[1]
				var defense: Dictionary = {"move": float(face)} if outcome in ["block", "break"] else {}
				if outcome == "break": o.guard = 10.0; o.guard_delay = 10.0
				sim.step(DT, [{"roundhouse": true}, defense])
				var contacts := 0
				var no_early_damage := true
				var valid_phase := true
				var ordinary_hurt := true
				var down_events := 0
				for frame in range(90):
					sim.step(DT, [{}, defense])
					if f.attack != "" and f.clock < 0.28: no_early_damage = no_early_damage and o.hp == 100.0
					var count := count_event(sim, outcome, "roundhouse", 1)
					contacts += count
					down_events += count_event(sim, "down")
					if count > 0:
						valid_phase = valid_phase and f.clock >= 0.28 and f.clock < 0.42
						if outcome in ["hit", "break"]:
							ordinary_hurt = ordinary_hurt and o.state == "hurt" and not o.down and is_equal_approx(o.stun, 0.45 if outcome == "break" else 0.28) and is_equal_approx(o.invuln, 0.63 if outcome == "break" else 0.46) and o.hit_kind == "roundhouse"
				check(contacts == (0 if outcome == "miss" else 1) and no_early_damage and valid_phase, label + " " + outcome + " occurs only once during active phase")
				check(o.hp == (87.0 if outcome in ["hit", "break"] else 100.0) and ordinary_hurt and not o.down and down_events == 0, label + " " + outcome + " never causes nonlethal knockdown")
				if outcome == "block": check(o.guard < 70.0 and o.stun == 0.0, label + " frontal guard absorbs roundhouse and consumes guard")
				elif outcome == "break": check(o.guard == 0.0, label + " insufficient guard breaks with bounded ordinary stun")
				elif outcome == "miss": check(o.guard == 100.0, label + " miss is silent and has no guard damage")
			for phase_time in [0.28 - EPS, 0.28, 0.35, 0.42, 0.50]:
				var sim = fixture(kind, face)
				var f: Dictionary = sim.fighters[0]
				sim.begin_attack(f, "roundhouse"); f.clock = phase_time
				sim.step(0.0, [{}, {}])
				var expected: bool = phase_time == 0.35
				check((count_event(sim, "hit", "roundhouse", 1) == 1) == expected and sim.fighters[1].hp == (87.0 if expected else 100.0), label + " exact contact phase boundary %.5f" % phase_time)
			var sim = fixture(kind, face, true)
			var f: Dictionary = sim.fighters[0]
			sim.begin_attack(f, "roundhouse"); f.clock = 0.42 + EPS
			sim.fighters[1].x = f.x + face * Combat.BODY * 2.0
			finish_attack(sim)
			check(sim.fighters[1].hp == 100.0, label + " target entering only during recovery cannot be hit")
			sim = fixture(kind, face); f = sim.fighters[0]
			sim.begin_attack(f, "roundhouse"); sim.fighters[1].invuln = 1.0
			finish_attack(sim)
			check(sim.fighters[1].hp == 100.0, label + " roundhouse respects existing hit/wakeup protection")

func spatial_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			for offset in [-EPS, 0.0, EPS]:
				var sim = fixture(kind, face, true)
				var f: Dictionary = sim.fighters[0]
				f.x = 0.0; sim.fighters[1].x = face * (1.40 + Combat.HURT_X + offset)
				sim.begin_attack(f, "roundhouse"); f.clock = 0.35; sim.step(0.0, [{}, {}])
				check(sim.fighters[1].hp == (87.0 if offset <= 0.0 else 100.0), label + " actual-foot peak cap + separate hurtbox boundary %f" % offset)
			for offset in [-EPS, 0.0, EPS]:
				var sim = fixture(kind, face)
				var f: Dictionary = sim.fighters[0]
				sim.fighters[1].y = (1.1084436178207397 if kind == 0 else 1.1109970092773438) + 0.06 - 0.15 + offset
				sim.begin_attack(f, "roundhouse"); f.clock = 0.35; sim.step(0.0, [{}, {}])
				check(sim.fighters[1].hp == (87.0 if offset <= 0.0 else 100.0), label + " actual-foot peak height plus .06 allowance has bounded vertical overlap %f" % offset)
			var sim = fixture(kind, face, true)
			var f: Dictionary = sim.fighters[0]
			f.x = 0.0; sim.fighters[1].x = -face * Combat.BODY * 2.0
			sim.begin_attack(f, "roundhouse")
			var committed := true
			for frame in range(70):
				if f.attack == "": break
				committed = committed and f.face == face
				sim.step(DT, [{}, {}])
			check(committed and sim.fighters[1].hp == 100.0 and f.face == -face, label + " no rear or 360 AOE contact; facing changes only after recovery")
			# Wall guard/hit cases above also check the correct outward direction.
			sim = fixture(kind, face)
			sim.step(DT, [{"roundhouse": true}, {}])
			var bounded := true
			for frame in range(100):
				sim.step(DT, [{"move": float(face)}, {"move": float(face)}])
				for fighter: Dictionary in sim.fighters:
					bounded = bounded and fighter.x >= Combat.LEFT and fighter.x <= Combat.RIGHT and fighter.y >= 0.0
				bounded = bounded and absf(sim.fighters[0].x - sim.fighters[1].x) >= Combat.BODY * 2.0 - EPS
			check(bounded, label + " wall pressure preserves clamp and ground pushboxes")

func interrupt_and_cancellation_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			for phase in ["startup", "active", "recovery"]:
				var sim = fixture(kind, face)
				sim.step(DT, [{"roundhouse": true}, {}])
				var f: Dictionary = sim.fighters[0]
				var o: Dictionary = sim.fighters[1]
				f.clock = {"startup":0.10,"active":0.35,"recovery":0.60}[phase] - DT
				sim.begin_attack(o, "punch"); o.clock = 0.19 - DT + EPS
				sim.step(DT, [{"roundhouse": true}, {}])
				check(f.attack == "" and f.state == "hurt" and f.hp == 92.0 and not f.down and f.queued == "" and f.queued_attack_id == 0, label + " incoming jab interrupts roundhouse " + phase)
				check(o.hp == (87.0 if phase == "active" else 100.0) and not o.down, label + " " + phase + " permits fair active trade, no startup/recovery phantom hit")
				tick(sim, 100, {"roundhouse": true})
				check(sim.attack_serial == 2 and f.attack == "", label + " held interrupted roundhouse does not restart after hurt")
				sim.step(DT, [{}, {}]); sim.step(DT, [{"roundhouse": true}, {}])
				check(f.attack == "roundhouse" and sim.attack_serial == 3, label + " fresh edge after hurt can attack normally")
			var sim = fixture(kind, face, true)
			sim.step(DT, [{"roundhouse": true}, {}]); finish_attack(sim)
			var f: Dictionary = sim.fighters[0]
			f.roundhouse_held = true
			sim.cancel_pending_inputs()
			check(not f.roundhouse_held and f.queued == "" and f.queued_attack_id == 0, label + " pause/background/menu clears roundhouse edge and pending input")
			sim.step(DT, [{"roundhouse": true}, {}])
			check(f.attack == "roundhouse" and sim.attack_serial == 2, label + " first fresh resume press works without extra neutral simulation tick")
			# Pausing freezes simulation externally; clearing input must not cancel
			# an already committed animation or manufacture a second attack.
			var clock_before: float = f.clock
			sim.cancel_pending_inputs()
			check(f.attack == "roundhouse" and f.clock == clock_before and not f.roundhouse_held, label + " pause input clear does not mutate current attack phase")
			finish_attack(sim); tick(sim, 30)
			check(sim.attack_serial == 2 and f.attack == "", label + " resume has no ghost roundhouse")
			sim.time_left = DT * 0.5; sim.step(DT, [{"roundhouse": true}, {}])
			check(sim.round_over and f.queued == "", label + " timeout clears input queue")
			var serial: int = sim.attack_serial
			for frame in range(180): sim.step_post_round(DT)
			check(sim.attack_serial == serial, label + " result settling never starts a roundhouse")
			sim.reset(kind)
			var clean := true
			for fighter: Dictionary in sim.fighters:
				clean = clean and not fighter.roundhouse_held and fighter.attack == "" and fighter.queued == "" and not fighter.input_rearm and not fighter.down
			check(clean and sim.attack_serial == 0 and not sim.round_over, label + " rematch/character reset clears all roundhouse state")
			sim.step(DT, [{"roundhouse": true}, {}])
			check(sim.fighters[0].attack == "roundhouse", label + " first ready roundhouse after reset is immediate")

func chain_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			var sim = fixture(kind, face, true)
			sim.step(DT, [{"punch": true}, {}])
			var f: Dictionary = sim.fighters[0]
			f.clock = f.duration - 0.10
			sim.step(DT, [{"roundhouse": true}, {}]); tick(sim, 100, {"roundhouse": true})
			check(sim.attack_serial == 1 and f.queued == "" and f.attack == "", label + " roundhouse edge in jab buffer does not queue a new chain extension")
			sim = fixture(kind, face, true)
			sim.step(DT, [{"punch": true}, {}]); queue_straight(sim)
			f = sim.fighters[0]
			check(f.queued == "straight", label + " normal two-punch sequence can still queue")
			sim.step(DT, [{"roundhouse": true}, {}])
			check(f.queued == "straight", label + " roundhouse cannot replace an authorized queued straight")
			tick(sim, 150, {"roundhouse": true})
			check(sim.attack_serial == 2 and f.attack == "" and f.queued == "", label + " held roundhouse cannot become a third attack after jab/straight")
			for second in ["punch", "heavy", "roundhouse", "kick"]:
				sim = fixture(kind, face, true)
				sim.step(DT, [{"roundhouse": true}, {}]); finish_attack(sim)
				sim.step(DT, [{second: true}, {}]); f = sim.fighters[0]
				check(f.attack == second and f.chain == 2, label + " fresh " + second + " after full roundhouse recovery retains existing chain count")
				var maximum_chain := 2
				var extra_starts := 0
				for frame in range(100):
					var before_lock: float = f.land_lock
					if f.attack == "" and before_lock <= DT + EPS: break
					sim.step(DT, [{"roundhouse": frame % 2 == 0, "punch": frame % 2 == 1}, {}])
					maximum_chain = maxi(maximum_chain, f.chain)
					extra_starts += count_event(sim, "attack")
				check(maximum_chain == 2 and extra_starts == 0 and sim.attack_serial == 2 and f.queued == "", label + " roundhouse then " + second + " keeps two-attack maximum and rejects third edges")
				check(f.chain == 0, label + " roundhouse then " + second + " clears chain after mandatory recovery")

func down_and_ko_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			var sim = fixture(kind, face)
			sim.step(DT, [{"kick": true}, {}])
			for frame in range(60):
				if sim.fighters[1].down: break
				sim.step(DT, [{}, {}])
			var o: Dictionary = sim.fighters[1]
			check(o.down and o.hp == 87.0, label + " ordinary flying kick still creates the separate down state")
			var protected := true
			var reached_rise := false
			var recovery_time: float = sim.elapsed
			for frame in range(180):
				active_snapshot(sim)
				sim.step(DT, [{}, {"roundhouse": true}])
				protected = protected and o.hp == 87.0 and o.attack == "" and count_event(sim, "hit", "roundhouse", 1) == 0 and count_event(sim, "down") == 0
				reached_rise = reached_rise or o.down_phase == "rise"
				if not o.down: break
			check(protected and reached_rise and not o.down and o.input_rearm and is_equal_approx(o.invuln, 0.35), label + " repeated roundhouse snapshots cannot hit-lock or restart down/rise")
			check(sim.elapsed - recovery_time >= 2.05 - EPS and sim.elapsed - recovery_time <= 2.05 + DT + EPS, label + " roundhouse spam never extends finite down lifecycle")
			var protected_samples := 0
			for frame in range(30):
				var before: float = o.invuln
				active_snapshot(sim); sim.step(DT, [{}, {"roundhouse": true}])
				if before > DT + EPS:
					protected_samples += 1
					protected = protected and o.hp == 87.0
				if o.hp < 87.0: break
			check(protected and protected_samples >= 19 and o.hp == 74.0 and not o.down and o.state == "hurt", label + " wakeup protection expires into ordinary hurt, not infinite invulnerability or down")
			tick(sim, 90, {}, {"roundhouse": true})
			check(o.attack == "" and o.input_rearm, label + " held down/wakeup roundhouse remains disarmed after protection and hurt")
			sim.step(DT, [{}, {}]); sim.step(DT, [{}, {"roundhouse": true}])
			check(o.attack == "roundhouse" and not o.input_rearm, label + " release then fresh roundhouse after recovery is accepted")
			for double_ko in [false, true]:
				sim = fixture(kind, face)
				sim.fighters[1].hp = 13.0
				if double_ko: sim.fighters[0].hp = 13.0
				sim.step(DT, [{"roundhouse": true}, {"roundhouse": true} if double_ko else {}])
				for frame in range(40):
					if sim.round_over: break
					sim.step(DT, [{}, {}])
				check(sim.round_over and sim.winner == (-1 if double_ko else 0) and count_event(sim, "hit", "roundhouse") == (2 if double_ko else 1) and count_event(sim, "down") == (2 if double_ko else 1) and count_event(sim, "round") == 1, label + " lethal roundhouse double=%s resolves fair KO and one result" % double_ko)
				var forbidden_events := 0
				for frame in range(240):
					sim.step_post_round(DT)
					for event_type in ["attack", "hit", "rise", "recovered", "round"]: forbidden_events += count_event(sim, event_type)
				var settled: bool = sim.fighters[1].down and sim.fighters[1].down_ko and sim.fighters[1].down_phase == "hold" and sim.fighters[1].y == 0.0
				if double_ko: settled = settled and sim.fighters[0].down_ko and sim.fighters[0].down_phase == "hold"
				check(settled and forbidden_events == 0, label + " lethal roundhouse double=%s remains down with no restart or rise" % double_ko)

func impact_event_height_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			# Independent actual foot-skin peak heights. Symmetric .06 padding
			# cancels in the center; this is world Y, never defender-relative Y.
			var expected_height: float = (0.9193906545639038 + 1.1084436178207397) * 0.5 if kind == 0 else (0.9158888339996337 + 1.1109970092773438) * 0.5
			for outcome in ["hit", "block", "break", "air_hit"]:
				var sim = fixture(kind, face)
				var f: Dictionary = sim.fighters[0]
				var o: Dictionary = sim.fighters[1]
				var defense: Dictionary = {"move":float(face)} if outcome in ["block", "break"] else {}
				if outcome == "break": o.guard = 10.0; o.guard_delay = 10.0
				if outcome == "air_hit": o.y = 0.60; o.vy = 1.0
				sim.begin_attack(f, "roundhouse"); f.clock = 0.35
				sim.step(0.0, [{}, defense])
				var events := 0
				var valid := true
				var expected_event: String = "hit" if outcome == "air_hit" else outcome
				for event: Dictionary in sim.events:
					if event.type == expected_event and event.get("kind", "") == "roundhouse":
						events += 1
						valid = valid and event.has("impact_y") and is_finite(event.get("impact_y", NAN)) and absf(event.get("impact_y", -100.0) - expected_height) < EPS
				check(events == 1 and valid, label + " " + outcome + " event carries finite actual-foot center in absolute world Y")
			var sim = fixture(kind, face)
			var f: Dictionary = sim.fighters[0]
			var o: Dictionary = sim.fighters[1]
			sim.begin_attack(f, "roundhouse"); f.clock = 0.35
			o.y = 0.55; o.vy = 0.0
			sim.begin_attack(o, "punch"); o.clock = 0.19
			var expected_punch_anchor := Vector2(f.x + signf(o.x - f.x) * 0.27, f.y + 1.30)
			sim.step(0.0, [{}, {}])
			var roundhouse_height := -100.0
			var punch_height := -100.0
			var punch_x := INF
			for event: Dictionary in sim.events:
				if event.type != "hit": continue
				if event.kind == "roundhouse": roundhouse_height = event.get("impact_y", -100.0)
				if event.kind == "punch":
					punch_height = event.get("impact_y", -100.0)
					punch_x = event.get("impact_x", INF)
			check(count_event(sim, "hit") == 2 and f.attack == "" and o.attack == "" and f.clock == 0.0 and o.clock == 0.0 and f.hp == 92.0 and o.hp == 87.0, label + " mixed air-jab/ground-roundhouse trade clears clocks without changing contact outcome")
			check(is_finite(roundhouse_height) and is_finite(punch_height) and absf(roundhouse_height - expected_height) < EPS and absf(punch_height - expected_punch_anchor.y) < EPS and absf(punch_x - expected_punch_anchor.x) < EPS, label + " trade events capture roundhouse foot height and jab defender-side visual XY before source attack/clock mutation")

func down_interrupt_and_seeded_stress_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			var sim = fixture(kind, face)
			sim.step(DT, [{"roundhouse": true}, {}])
			var f: Dictionary = sim.fighters[0]
			var o: Dictionary = sim.fighters[1]
			f.clock = 0.10
			sim.begin_attack(o, "kick"); o.clock = 0.36 - DT + EPS
			sim.step(DT, [{"roundhouse": true}, {}])
			check(f.down and f.attack == "" and f.queued == "" and f.queued_attack_id == 0 and f.chain == 0 and f.hp == 87.0, label + " incoming flying kick cancels roundhouse into genuine down")
			var serial: int = sim.attack_serial
			sim.begin_attack(f, "roundhouse")
			check(sim.attack_serial == serial and f.attack == "", label + " public begin cannot restart downed roundhouse")
			tick(sim, 200, {"roundhouse": true})
			check(not f.down and f.attack == "" and f.input_rearm and sim.attack_serial == serial, label + " interrupted held roundhouse never fires during down or after wakeup")
			sim.step(DT, [{}, {}]); sim.step(DT, [{"roundhouse": true}, {}])
			check(f.attack == "roundhouse" and not f.input_rearm, label + " fresh edge after kick interruption recovers control")
	# Additional mixed-input rounds exercise the new command, rather than relying
	# on the unchanged legacy stress suite that did not generate roundhouses.
	for seed_id in range(40):
		var sim = Combat.new()
		sim.reset(seed_id % 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 19091 + seed_id * 1777
		var movement := [1.0, -1.0]
		var valid := true
		var roundhouse_starts := 0
		for frame in range(3650):
			var commands: Array = []
			for index in range(2):
				if frame % 30 == 0: movement[index] = rng.randf_range(-1.0, 1.0)
				commands.append({"move":movement[index], "roundhouse":rng.randf() < 0.04, "punch":rng.randf() < 0.025, "heavy":rng.randf() < 0.014, "kick":rng.randf() < 0.018, "jump":rng.randf() < 0.009})
			sim.step(DT, commands)
			roundhouse_starts += count_event(sim, "attack", "roundhouse")
			for fighter: Dictionary in sim.fighters:
				valid = valid and fighter.x >= Combat.LEFT and fighter.x <= Combat.RIGHT and fighter.y >= 0.0 and fighter.hp >= 0.0 and fighter.hp <= 100.0 and fighter.guard >= 0.0 and fighter.guard <= 100.0 and fighter.chain <= 2
				if fighter.attack == "roundhouse": valid = valid and fighter.y == 0.0 and fighter.vy == 0.0 and fighter.vx == 0.0
				if fighter.down and not fighter.down_ko: valid = valid and fighter.down_age < 3.0
			for event: Dictionary in sim.events:
				if event.type == "down" and event.get("kind", "") == "roundhouse": valid = valid and event.ko
			if sim.round_over: break
		check(sim.round_over and roundhouse_starts > 0 and valid, "mixed roundhouse stress seed %d ends with bounded health/guard/physics, chain <= 2 and no nonlethal roundhouse down" % seed_id)

func _init() -> void:
	config_and_edge_tests()
	measured_surface_tests()
	ground_only_and_busy_tests()
	contact_and_phase_tests()
	spatial_tests()
	interrupt_and_cancellation_tests()
	chain_tests()
	down_and_ko_tests()
	down_interrupt_and_seeded_stress_tests()
	impact_event_height_tests()
	print("Roundhouse checks: ", checks, "; failures: ", failures)
	quit(failures)
