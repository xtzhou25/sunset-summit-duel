extends SceneTree
## v4 pure deterministic input/combat contract. No renderer-driven contacts.
## Run: godot --headless --path . --script tests/punch_variation_test.gd
## Explicit phase/contact snapshots below isolate otherwise time-sensitive
## invariants; ordinary chain tests use real input and wall-constrained movement.
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

func attack_events(sim) -> Array:
	var result: Array = []
	for event: Dictionary in sim.events:
		if event.type == "attack": result.append(event.kind)
	return result

func reach_buffer_window(sim, defense: Dictionary = {}) -> void:
	var f: Dictionary = sim.fighters[0]
	for frame in range(60):
		if f.clock + DT >= f.duration - Combat.PUNCH_BUFFER_WINDOW + EPS: return
		sim.step(DT, [{}, defense])

func queue_straight(sim, defense: Dictionary = {}) -> void:
	reach_buffer_window(sim, defense)
	sim.step(DT, [{"punch": true}, defense])

func finish_attack(sim, defense: Dictionary = {}) -> void:
	for frame in range(120):
		if sim.fighters[0].attack == "": return
		sim.step(DT, [{}, defense])

func measured_reach_tests() -> void:
	# Independent anchors copied from the approved actual-GLB curve report.
	# Per move: start seconds/raw hand reach, next sample/raw reach,
	# peak seconds/raw reach, and end seconds/raw reach. Values exclude allowance.
	var anchors: Array = [
		{
			"punch": [0.14,0.3835909795761109,0.421529746055603,0.19,0.506412935256958,0.24,0.4634301710128784],
			"straight": [0.18,0.4009516525268555,0.4477699184417724,0.23,0.5535859107971192,0.28,0.5241165018081665],
			"heavy": [0.34,0.34018012046813983,0.4070424556732178,0.40,0.591771125793457,0.46,0.5669331121444702],
		},
		{
			"punch": [0.14,0.42926260471344,0.4658633708953857,0.19,0.5457331323623658,0.24,0.505417685508728],
			"straight": [0.18,0.44659908771514895,0.4920880651473998,0.23,0.5929101276397705,0.28,0.5650381851196289],
			"heavy": [0.34,0.3852092170715333,0.4509137392044067,0.40,0.6309730768203735,0.46,0.6074573993682861],
		},
	]
	for kind in range(2):
		for face in [-1, 1]:
			for move in ["punch", "straight", "heavy"]:
				var label := "measured kind %d face %d %s" % [kind, face, move]
				var sim = fixture(kind, face, true)
				var f: Dictionary = sim.fighters[0]
				var config: Dictionary = sim.attack_config(f, move)
				var a: Array = anchors[kind][move]
				var start_reach: float = minf(config.reach, a[1] + 0.04)
				var peak_reach: float = minf(config.reach, a[4] + 0.04)
				var end_reach: float = minf(config.reach, a[6] + 0.04)
				check(absf(sim.effective_reach(f, move, a[0]) - start_reach) < EPS and absf(sim.effective_reach(f, move, a[3]) - peak_reach) < EPS and absf(sim.effective_reach(f, move, a[5]) - end_reach) < EPS, label + " matches independent start/peak/end skin reach plus .04, capped by config")
				var halfway: float = minf(config.reach, (a[1] + a[2]) * 0.5 + 0.04)
				check(absf(sim.effective_reach(f, move, a[0] + 0.005) - halfway) < EPS, label + " linearly interpolates between 10ms absolute-time samples")
				check(absf(sim.effective_reach(f, move, 0.0) - start_reach) < EPS and absf(sim.effective_reach(f, move, a[5] + 5.0) - end_reach) < EPS, label + " outside-curve reads safely clamp to endpoints without changing active phase")
				f.clock = a[3]
				check(absf(sim.effective_reach(f, move) - peak_reach) < EPS, label + " renderer/debug default uses fighter clock and excludes HURT_X")
				for offset in [-EPS, 0.0, EPS]:
					sim = fixture(kind, face, true); f = sim.fighters[0]
					f.x = 0.0; sim.fighters[1].x = face * (peak_reach + Combat.HURT_X + offset)
					sim.begin_attack(f, move)
					# Zero-delta contact snapshot tests the exact inclusive spatial
					# boundary, without introducing fixed-step time roundoff.
					f.clock = a[3]; sim.step(0.0, [{}, {}])
					var expected_hit: bool = offset <= 0.0
					check((count_event(sim, "hit", move, 1) == 1) == expected_hit and sim.fighters[1].hp == (100.0 - config.damage if expected_hit else 100.0), label + " exact peak reach + hurtbox boundary offset %f" % offset)
				sim = fixture(kind, face, true); f = sim.fighters[0]
				f.x = 0.0; sim.fighters[1].x = face * ((start_reach + peak_reach) * 0.5 + Combat.HURT_X)
				sim.begin_attack(f, move); f.clock = a[0]
				sim.step(0.0, [{}, {}])
				check(sim.fighters[1].hp == 100.0 and not f.hit, label + " active onset does not instantly receive peak range")
				f.clock = a[3]; sim.step(0.0, [{}, {}])
				check(sim.fighters[1].hp == 100.0 - config.damage and count_event(sim, "hit", move, 1) == 1, label + " same target becomes hittable only when authored hand extends")
			var sim = fixture(kind, face, true)
			var f: Dictionary = sim.fighters[0]
			var kick: Dictionary = sim.attack_config(f, "kick")
			check(sim.effective_reach(f, "kick", 0.0) == kick.reach and sim.effective_reach(f, "kick", 0.42) == kick.reach and sim.effective_reach(f, "kick", 3.0) == kick.reach, "kind %d face %d kick reach remains static and unchanged" % [kind, face])
			# Full real-command heavy at near-maximum reach must wait for its
			# authored extension, not hit on the first active frame.
			f.x = 0.0
			var cap: float = sim.attack_config(f, "heavy").reach
			sim.fighters[1].x = face * (cap + Combat.HURT_X - 0.005)
			sim.step(DT, [{"heavy": true}, {}])
			var first_hit := -1.0
			var early_active_samples := 0
			var early_damage := false
			var hits := 0
			for frame in range(70):
				sim.step(DT, [{}, {}])
				if f.attack == "": break
				if f.clock >= 0.34 and f.clock < 0.39:
					early_active_samples += 1
					early_damage = early_damage or sim.fighters[1].hp < 100.0
				if count_event(sim, "hit", "heavy", 1) > 0:
					hits += 1
					if first_hit < 0.0: first_hit = f.clock
			check(early_active_samples >= 2 and not early_damage and first_hit >= 0.39 and first_hit <= 0.41 and hits == 1 and sim.fighters[1].hp == 84.0, "kind %d face %d real heavy has no early long-range hit and connects once near .40s peak" % [kind, face])

func config_tests() -> void:
	for kind in range(2):
		var sim = fixture(kind)
		var punch: Dictionary = sim.attack_config(sim.fighters[0], "punch")
		var straight: Dictionary = sim.attack_config(sim.fighters[0], "straight")
		var heavy: Dictionary = sim.attack_config(sim.fighters[0], "heavy")
		check(punch == {"startup":0.14,"active":0.10,"recovery":0.24 if kind==0 else 0.28,"reach":0.55 if kind==0 else 0.59,"damage":8.0,"guard":22.0,"stun":0.24,"push":0.22,"low":0.66,"high":1.80}, "kind %d first jab changes only measured reach, preserves RC3 timing/damage" % kind)
		check(straight == {"startup":0.18,"active":0.10,"recovery":0.28 if kind==0 else 0.32,"reach":0.60 if kind==0 else 0.64,"damage":10.0,"guard":26.0,"stun":0.26,"push":0.27,"low":0.66,"high":1.80}, "kind %d measured straight cap and unchanged timing/damage config are explicit" % kind)
		check(heavy == {"startup":0.34,"active":0.12,"recovery":0.42 if kind==0 else 0.48,"reach":0.63 if kind==0 else 0.67,"damage":16.0,"guard":38.0,"stun":0.30,"push":0.52,"low":0.66,"high":1.80}, "kind %d measured heavy cap and unchanged timing/damage config are explicit" % kind)
		check(is_equal_approx(straight.startup + straight.active + straight.recovery, 0.56 if kind == 0 else 0.60) and is_equal_approx(heavy.startup + heavy.active + heavy.recovery, 0.88 if kind == 0 else 0.94), "kind %d distinct anticipation/recovery totals match authoring contract" % kind)
		check(is_equal_approx(Combat.PUNCH_BUFFER_WINDOW, 0.12), "kind %d buffer admission window is exactly 120 ms" % kind)

func first_press_and_hold_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			for move in ["punch", "heavy"]:
				var sim = fixture(kind, face, true)
				sim.step(DT, [{move: true, "move": float(face)}, {}])
				check(sim.fighters[0].attack == move and sim.fighters[0].clock == 0.0 and sim.attack_serial == 1 and attack_events(sim) == [move], label + " " + move + " starts immediately on first press, without charge delay")
				var starts := 1
				var stationary := true
				var start_x: float = sim.fighters[0].x
				for frame in range(200):
					sim.step(DT, [{move: true}, {}])
					starts += count_event(sim, "attack")
					stationary = stationary and sim.fighters[0].vx == 0.0 and sim.fighters[0].x == start_x
				check(starts == 1 and sim.fighters[0].attack == "" and sim.fighters[0].queued == "", label + " held " + move + " never repeats or queues")
				check(stationary, label + " " + move + " has zero root velocity throughout attack/recovery")
				sim.step(DT, [{}, {}])
				sim.step(DT, [{move: true}, {}])
				check(sim.fighters[0].attack == move and sim.attack_serial == 2, label + " release then fresh " + move + " restarts normally")
			var sim = fixture(kind, face, true)
			sim.step(DT, [{"straight": true}, {}])
			check(sim.attack_serial == 0 and sim.fighters[0].attack == "", label + " straight is internal, not a direct player command")

func actual_chain_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for outcome in ["hit", "block", "miss"]:
				var label := "kind %d face %d %s" % [kind, face, outcome]
				var sim = fixture(kind, face, outcome == "miss")
				var defense: Dictionary = {"move": float(face)} if outcome == "block" else {}
				var target: Dictionary = sim.fighters[1]
				sim.step(DT, [{"punch": true}, defense])
				var first_duration: float = sim.fighters[0].duration
				queue_straight(sim, defense)
				var f: Dictionary = sim.fighters[0]
				check(f.attack == "punch" and f.queued == "straight" and f.queued_attack_id == f.attack_id and f.clock >= first_duration - 0.12 and f.clock < first_duration, label + " fresh late press queues exactly the matching first-jab follow-up")
				var queue_time: float = sim.elapsed
				var straight_starts := 0
				var transition_time := -1.0
				var straight_contacts := 0
				var stationary := true
				var maximum_chain := 1
				for frame in range(100):
					sim.step(DT, [{}, defense])
					if count_event(sim, "attack", "straight") > 0:
						straight_starts += 1
						transition_time = sim.elapsed
						check(f.clock == 0.0 and f.queued == "" and f.queued_attack_id == 0 and f.chain == 2, label + " transition begins complete straight startup and clears queue")
					straight_contacts += count_event(sim, outcome, "straight", 1)
					maximum_chain = maxi(maximum_chain, f.chain)
					stationary = stationary and (f.attack == "" or f.vx == 0.0)
					if f.attack == "": break
				check(straight_starts == 1 and transition_time >= DT + first_duration - EPS and transition_time - queue_time <= 0.12 + DT + EPS and maximum_chain == 2 and sim.attack_serial == 2, label + " straight waits for full jab recovery, buffer lifetime is bounded, maximum chain is two")
				check(f.land_lock >= 0.19 - EPS and f.chain == 0 and f.queued == "" and stationary, label + " completed two-hit chain retains .19s extra recovery and stationary roots")
				if outcome == "hit":
					check(straight_contacts == 1 and target.hp == 82.0 and not target.down, label + " jab plus straight deals 8 + 10 once each, never knocks down")
				elif outcome == "block":
					check(straight_contacts == 1 and target.hp == 100.0 and target.guard < 52.0 and not target.down, label + " jab and straight can both be blocked with bounded guard cost")
				else:
					check(target.hp == 100.0 and target.guard == 100.0 and straight_contacts == 0, label + " both attacks can miss without damage or guard cost")

func early_repeated_and_third_press_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			var sim = fixture(kind, face, true)
			sim.step(DT, [{"punch": true}, {}])
			tick(sim, 5)
			tick(sim, 100, {"punch": true})
			check(sim.attack_serial == 1 and sim.fighters[0].attack == "" and sim.fighters[0].queued == "", label + " too-early second press held through the window is discarded, not delayed")
			sim = fixture(kind, face, true)
			sim.step(DT, [{"punch": true}, {}])
			queue_straight(sim)
			var locked_samples := 0
			var illegal_start := false
			for frame in range(100):
				var before_lock: float = sim.fighters[0].land_lock
				# Do not send a legitimate new press on the first unlocked tick;
				# only inputs before that boundary are intentionally discarded.
				if locked_samples > 0 and before_lock <= DT + EPS:
					sim.step(DT, [{}, {}])
					break
				sim.step(DT, [{"punch": frame % 2 == 0}, {}])
				if before_lock > DT + EPS:
					locked_samples += 1
					illegal_start = illegal_start or count_event(sim, "attack") > 0
				if sim.fighters[0].attack == "" and sim.fighters[0].land_lock <= 0.0: break
			check(sim.attack_serial == 2 and sim.fighters[0].queued == "" and not illegal_start and locked_samples >= 10, label + " repeated second/third presses never duplicate straight or bypass two-hit recovery")
			sim.step(DT, [{}, {}])
			sim.step(DT, [{"punch": true}, {}])
			check(sim.attack_serial == 3 and sim.fighters[0].attack == "punch" and sim.fighters[0].chain == 1, label + " fresh post-lock press starts a new lead jab, never a stale straight")
			sim = fixture(kind, face, true)
			sim.step(DT, [{"punch": true}, {}]); queue_straight(sim)
			tick(sim, 160, {"punch": true})
			check(sim.attack_serial == 2 and sim.fighters[0].attack == "" and sim.fighters[0].queued == "", label + " held second press cannot become a third attack after lock expires")
			# Exact admission boundaries are deliberate clock snapshots, not claims
			# that 60 Hz input can resolve sub-frame differences.
			for offset in [-EPS, EPS]:
				sim = fixture(kind, face, true)
				sim.step(DT, [{"punch": true}, {}]); sim.step(DT, [{}, {}])
				var f: Dictionary = sim.fighters[0]
				f.clock = f.duration - Combat.PUNCH_BUFFER_WINDOW - DT + offset
				sim.step(DT, [{"punch": true}, {}])
				check((f.queued == "straight") == (offset > 0.0), label + " exact buffer boundary snapshot offset %f" % offset)
			# A press after full recovery is a new immediate jab, not a buffered
			# straight. The legacy short chain window still counts the second hit.
			sim = fixture(kind, face, true)
			sim.step(DT, [{"punch": true}, {}]); finish_attack(sim)
			sim.step(DT, [{"punch": true}, {}])
			check(sim.fighters[0].attack == "punch" and sim.fighters[0].chain == 2 and sim.fighters[0].queued == "", label + " post-recovery press stays immediate lead jab and retains legacy two-hit cap")
			finish_attack(sim)
			check(sim.fighters[0].land_lock >= 0.19 - EPS, label + " two separate quick jabs also pay the legacy chain recovery")

func crossup_and_landing_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			var sim = fixture(kind, face, true)
			sim.step(DT, [{"punch": true}, {}]); queue_straight(sim)
			var f: Dictionary = sim.fighters[0]
			# Explicit cross-up snapshot after jab commitment, before handoff.
			f.x = 0.0; sim.fighters[1].x = -face * 1.3
			var committed := true
			for frame in range(20):
				committed = committed and f.face == face
				sim.step(DT, [{}, {}])
				if f.attack != "punch": break
			check(committed and f.attack == "straight" and f.face == -face, label + " jab keeps facing through recovery, straight reacquires only at new attack boundary")
			# Actual jump and late-air jab land shortly before the jab ends.
			# A queued follow-up must not bypass the existing landing lock.
			sim = fixture(kind, face, true)
			sim.step(DT, [{"jump": true}, {}]); tick(sim, 17 if kind == 0 else 14)
			sim.step(DT, [{"punch": true}, {}]); queue_straight(sim)
			f = sim.fighters[0]
			check(f.queued == "straight", label + " late-air jab can receive the same finite input buffer")
			var lock_at_end := 0.0
			for frame in range(40):
				sim.step(DT, [{}, {}])
				if f.attack != "punch":
					lock_at_end = f.land_lock
					break
			check(f.attack == "" and f.y == 0.0 and lock_at_end > 0.0 and f.queued == "" and sim.attack_serial == 1, label + " landing lock discards queued straight instead of bypassing protection")
			tick(sim, 60)
			check(sim.attack_serial == 1, label + " discarded landing follow-up never fires late")

func phase_and_contact_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			for move in ["punch", "straight", "heavy"]:
				var label := "kind %d face %d %s" % [kind, face, move]
				var sim = fixture(kind, face)
				var f: Dictionary = sim.fighters[0]
				var config: Dictionary = sim.attack_config(f, move)
				# Internal begin_attack isolates each move's complete contact phase;
				# the real-command straight admission is tested separately above.
				sim.begin_attack(f, move)
				var hits := 0
				var premature := false
				var correctly_timed := true
				var moving := false
				for frame in range(100):
					sim.step(DT, [{"move": float(face)}, {}])
					if f.attack == "": break
					moving = moving or f.vx != 0.0
					if f.clock < config.startup: premature = premature or sim.fighters[1].hp < 100.0
					var contact_count := count_event(sim, "hit", move, 1)
					if contact_count > 0: correctly_timed = correctly_timed and f.clock >= config.startup and f.clock < config.startup + config.active
					hits += contact_count
				check(hits == 1 and not premature and correctly_timed and sim.fighters[1].hp == 100.0 - config.damage and not sim.fighters[1].down, label + " startup/recovery cannot damage, one active contact gives normal nonlethal hitstun")
				check(not moving, label + " move command cannot slide committed ground punch")
				sim = fixture(kind, face, true)
				f = sim.fighters[0]
				sim.begin_attack(f, move)
				while f.clock < config.startup + config.active + DT: sim.step(DT, [{}, {}])
				# Move the opponent into range only once the hitbox has expired.
				sim.fighters[1].x = f.x + face * Combat.BODY * 2.0
				finish_attack(sim)
				check(sim.fighters[1].hp == 100.0, label + " missed attack cannot damage target entering only during recovery")
				sim = fixture(kind, face)
				sim.fighters[1].invuln = 1.0
				sim.begin_attack(sim.fighters[0], move); finish_attack(sim)
				check(sim.fighters[1].hp == 100.0, label + " respects existing hit/wakeup invulnerability")
				sim = fixture(kind, face)
				sim.begin_attack(sim.fighters[0], move)
				sim.fighters[1].x = sim.fighters[0].x - face * Combat.BODY * 2.0
				var stable := true
				while sim.fighters[0].attack != "":
					stable = stable and sim.fighters[0].face == face
					sim.step(DT, [{}, {}])
				check(stable and sim.fighters[1].hp == 100.0 and sim.fighters[0].face == -face, label + " committed facing never retargets opponent behind")

func heavy_guard_air_and_interrupt_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			for broken in [false, true]:
				var sim = fixture(kind, face)
				if broken: sim.fighters[1].guard = 10.0; sim.fighters[1].guard_delay = 10.0
				sim.step(DT, [{"heavy": true}, {"move": float(face)}])
				var contacts := 0
				var contact_stun := 0.0
				var protection := 0.0
				for frame in range(60):
					sim.step(DT, [{}, {"move": float(face)}])
					if count_event(sim, "break" if broken else "block", "heavy", 1) > 0:
						contacts += 1; contact_stun = sim.fighters[1].stun; protection = sim.fighters[1].invuln
				check(contacts == 1 and not sim.fighters[1].down and sim.fighters[1].hp == (84.0 if broken else 100.0), label + " heavy %s resolves once without knockdown" % ("guard break" if broken else "frontal block"))
				if broken: check(is_equal_approx(contact_stun, 0.47) and is_equal_approx(protection, 0.65) and sim.fighters[1].guard == 0.0, label + " heavy low-guard break keeps bounded .47s stun/.65s protection")
			var sim = fixture(kind, face, true)
			sim.step(DT, [{"jump": true, "move": float(face)}, {}])
			sim.step(DT, [{"heavy": true}, {}])
			check(sim.fighters[0].attack == "" and sim.attack_serial == 0 and sim.fighters[0].y > 0.0, label + " heavy is explicitly ground-only and airborne press is consumed")
			tick(sim, 100, {"heavy": true})
			check(sim.fighters[0].attack == "" and sim.fighters[0].y == 0.0 and sim.attack_serial == 0, label + " rejected airborne heavy cannot fire when held through landing")
			sim.step(DT, [{}, {}]); sim.step(DT, [{"heavy": true}, {}])
			check(sim.fighters[0].attack == "heavy", label + " fresh grounded heavy works after airborne rejection")
			sim = fixture(kind, face, true)
			sim.step(DT, [{"jump": true, "move": float(face)}, {}])
			sim.step(DT, [{"punch": true}, {}])
			check(sim.fighters[0].attack == "punch" and sim.fighters[0].y > 0.0 and sim.fighters[0].vx == 0.0, label + " ordinary air jab preserves original zero-horizontal-velocity behavior")
			for phase in ["startup", "active", "recovery"]:
				sim = fixture(kind, face)
				sim.step(DT, [{"heavy": true}, {}])
				var attacker: Dictionary = sim.fighters[0]
				var defender: Dictionary = sim.fighters[1]
				# Explicit clock snapshots place the incoming jab on the next
				# active frame. Heavy's active phase may trade fairly, not win by
				# index. Its startup/recovery cannot hurt the interrupter.
				attacker.clock = {"startup":0.10,"active":0.35,"recovery":0.60}[phase] - DT
				sim.begin_attack(defender, "punch")
				defender.clock = 0.19 - DT + EPS
				sim.step(DT, [{"heavy": true}, {}])
				check(attacker.attack == "" and attacker.state == "hurt" and attacker.hp == 92.0 and not attacker.down and attacker.queued == "", label + " heavy can be interrupted in " + phase)
				check(defender.hp == (84.0 if phase == "active" else 100.0) and not defender.down, label + " heavy " + phase + " interruption preserves correct trade/no-contact outcome")
				tick(sim, 100, {"heavy": true})
				check(sim.attack_serial == 2 and attacker.attack == "", label + " held interrupted heavy never restarts after hitstun")

func queue_cancellation_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			for incoming in ["punch", "kick"]:
				var sim = fixture(kind, face, true)
				sim.step(DT, [{"punch": true}, {}]); queue_straight(sim)
				var f: Dictionary = sim.fighters[0]
				var opponent: Dictionary = sim.fighters[1]
				# Explicit incoming-contact snapshot while a real input-created
				# straight is pending. No state/damage/queue outcome is injected.
				opponent.x = f.x + face * Combat.BODY * 2.0
				sim.begin_attack(opponent, incoming)
				opponent.clock = (0.19 if incoming == "punch" else sim.attack_config(opponent, incoming).startup) - DT + EPS
				sim.step(DT, [{}, {}])
				check(f.queued == "" and f.queued_attack_id == 0 and f.attack == "" and f.chain == 0 and f.down == (incoming == "kick"), label + " incoming " + incoming + " cancels queued straight on hit/down")
				tick(sim, 180)
				check(sim.attack_serial == 2 and f.attack == "" and not f.down, label + " no stale straight after " + incoming + " hitstun or complete wakeup")
			var sim = fixture(kind, face, true)
			sim.step(DT, [{"punch": true}, {}]); queue_straight(sim)
			var f: Dictionary = sim.fighters[0]
			sim.cancel_pending_inputs()
			check(f.queued == "" and f.queued_attack_id == 0 and not f.punch_held and not f.heavy_held, label + " pause/background/menu cancellation clears buffers and prior edges")
			finish_attack(sim); tick(sim, 30)
			check(sim.attack_serial == 1 and f.attack == "", label + " cancelled queue never restarts on resume")
			# Upstream clears held/taps before cancellation. No extra neutral
			# simulation step may be required for first-ready/first-resume input.
			sim.cancel_pending_inputs(); sim.step(DT, [{"punch": true}, {}])
			check(f.attack == "punch" and sim.attack_serial == 2, label + " first fresh resume press remains immediate without neutral frame")
			sim = fixture(kind, face, true)
			sim.step(DT, [{"punch": true}, {}]); queue_straight(sim)
			sim.time_left = DT * 0.5; sim.step(DT, [{}, {}])
			check(sim.round_over and sim.fighters[0].queued == "" and sim.fighters[0].queued_attack_id == 0, label + " timeout clears pending follow-up")
			var serial: int = sim.attack_serial
			for frame in range(120): sim.step_post_round(DT)
			check(sim.attack_serial == serial, label + " post-round cannot launch buffered attack")
			sim.reset(kind)
			var clean := true
			for fighter: Dictionary in sim.fighters: clean = clean and fighter.queued == "" and fighter.queued_attack_id == 0 and not fighter.punch_held and not fighter.heavy_held and not fighter.input_rearm
			check(clean and sim.attack_serial == 0 and sim.time_left == 60.0 and not sim.round_over, label + " rematch/character reset clears all new input state")
			sim.step(DT, [{"heavy": true}, {}])
			check(sim.fighters[0].attack == "heavy", label + " first ready heavy press after reset is immediate")

func down_protection_and_ending_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d" % [kind, face]
			var sim = fixture(kind, face)
			sim.step(DT, [{"kick": true}, {}])
			for frame in range(60):
				if sim.fighters[1].down: break
				sim.step(DT, [{}, {}])
			var defender: Dictionary = sim.fighters[1]
			var protected: bool = defender.down
			var reached_rise := false
			for frame in range(180):
				var attacker: Dictionary = sim.fighters[0]
				# Repeated active-heavy contact snapshots stress the existing
				# down/rise immunity without injecting defender phases or health.
				attacker.x = defender.x - face * Combat.BODY * 2.0
				attacker.face = face; attacker.y = 0.0; attacker.vy = 0.0
				attacker.attack = "heavy"; attacker.hit = false
				attacker.clock = 0.40 - DT + EPS; attacker.duration = 0.88 if kind == 0 else 0.94
				sim.step(DT, [{}, {"heavy": true}])
				protected = protected and defender.hp == 87.0 and count_event(sim, "hit", "heavy", 1) == 0
				reached_rise = reached_rise or defender.down_phase == "rise"
				if not defender.down: break
			check(protected and reached_rise and not defender.down and defender.input_rearm and is_equal_approx(defender.invuln, 0.35), label + " heavy cannot hit-lock, damage or restart down/rise and held heavy remains disarmed")
			tick(sim, 30, {}, {"heavy": true})
			check(defender.attack == "", label + " held wakeup heavy does not auto-fire")
			sim.step(DT, [{}, {}]); sim.step(DT, [{}, {"heavy": true}])
			check(defender.attack == "heavy" and not defender.input_rearm, label + " neutral then fresh wakeup heavy works normally")
			for move in ["punch", "straight", "heavy"]:
				sim = fixture(kind, face)
				var damage: float = sim.attack_config(sim.fighters[0], move).damage
				for fighter: Dictionary in sim.fighters:
					fighter.hp = damage
					sim.begin_attack(fighter, move)
				for frame in range(50):
					sim.step(DT, [{}, {}])
					if sim.round_over: break
				check(sim.round_over and sim.winner == -1 and count_event(sim, "hit", move) == 2 and count_event(sim, "down") == 2 and count_event(sim, "round") == 1, label + " simultaneous lethal " + move + " fairly creates double KO and one draw")
				for frame in range(180): sim.step_post_round(DT)
				check(sim.fighters[0].down_ko and sim.fighters[1].down_ko and sim.fighters[0].down_phase == "hold" and sim.fighters[1].down_phase == "hold" and sim.fighters[0].queued == "" and sim.fighters[1].queued == "", label + " lethal " + move + " stays down and never buffers/restarts")

func _init() -> void:
	measured_reach_tests()
	config_tests()
	first_press_and_hold_tests()
	actual_chain_tests()
	early_repeated_and_third_press_tests()
	crossup_and_landing_tests()
	phase_and_contact_tests()
	heavy_guard_air_and_interrupt_tests()
	queue_cancellation_tests()
	down_protection_and_ending_tests()
	print("Punch variation checks: ", checks, "; failures: ", failures)
	quit(failures)
