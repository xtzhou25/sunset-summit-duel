extends SceneTree
## Signature-wave logic is fixed-clock and renderer-independent. These checks do
## not certify visual emitter placement; integration tests sample the real GLB.
## godot --headless --path . --script tests/projectile_test.gd
const Combat = preload("res://scripts/combat.gd")
const Brain = preload("res://scripts/ai.gd")
const DT := 1.0 / 60.0
const EPS := 0.00001
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run_tests")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else: failures += 1; printerr("FAIL: ", label)

func fixture(kind: int = 0, face: int = 1):
	var sim = Combat.new()
	sim.reset(kind)
	sim.fighters[0].x = -1.2 * face
	sim.fighters[1].x = 1.2 * face
	sim.fighters[0].face = face
	sim.fighters[1].face = -face
	return sim

func tick(sim, frames: int, first: Dictionary = {}, second: Dictionary = {}) -> void:
	for frame in range(frames): sim.step(DT, [first, second])

func count_event(sim, event_type: String, kind: String = "") -> int:
	var count := 0
	for event: Dictionary in sim.events:
		if event.type == event_type and (kind == "" or event.get("kind", "") == kind): count += 1
	return count

func inject(sim, owner: int, kind: String, position: Vector2, velocity: Vector2, age: float = 0.0, distance: float = 0.0) -> Dictionary:
	sim.projectile_serial += 1
	var projectile := {"id":sim.projectile_serial,"owner":owner,"kind":kind,"pos":position,"previous_pos":position,"velocity":velocity,"face":1 if velocity.x>=0.0 else -1,"age":age,"distance":distance,"target_snapshot":Vector2.ZERO}
	sim.projectiles.append(projectile)
	return projectile

func config_and_cast_tests() -> void:
	check(Combat.SPECIAL_COOLDOWN == 4.0 and Combat.PROJECTILE_CONFIG == {"damage":12.0,"guard":28.0,"stun":0.26,"push":0.24}, "explicit cooldown/damage/guard/stun/push contract")
	check(Combat.PROJECTILE_SPEED == 3.6 and Combat.PROJECTILE_RANGE == 4.5 and Combat.PROJECTILE_LIFETIME == 1.25, "explicit horizontal speed/range/lifetime contract")
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d " % [kind, face]
			var sim = fixture(kind, face)
			var f: Dictionary = sim.fighters[0]
			var emit_time: float = Combat.MEOW_EMIT if kind == 0 else Combat.HEART_EMIT
			var calls: Array = []
			var expected_origin := Vector2(f.x + face * 0.40, 1.72 if kind == 0 else 2.90)
			sim.emitter_provider = func(index: int, age: float) -> Vector2:
				calls.append([index, age])
				return expected_origin
			sim.step(DT, [{"special":true,"move":face}, {}])
			check(f.attack == "special" and f.state == "special" and f.clock == 0.0 and f.special_cooldown == 4.0 and count_event(sim, "attack", "special") == 1, label + "fresh ground press starts once and immediately spends cooldown")
			check(f.chain == 0 and f.queued == "" and f.vx == 0.0 and is_equal_approx(f.duration, 1.0 if kind == 0 else 1.05), label + "signature is stationary, not a jab-chain member, and has authored duration")
			var initial_x: float = f.x
			var spawn_count := 0
			var first_spawn := -1.0
			var actual_spawn: Dictionary = {}
			var stationary := true
			var max_y := 0.0
			for frame in range(300):
				sim.step(DT, [{"special":true}, {}])
				if f.attack == "special": stationary = stationary and f.x == initial_x and f.vx == 0.0
				max_y = maxf(max_y, f.y)
				for event: Dictionary in sim.events:
					if event.type == "projectile_spawn":
						spawn_count += 1
						if first_spawn < 0.0: first_spawn = f.clock; actual_spawn = event
			check(spawn_count == 1 and calls.size() == 1 and calls[0][0] == 0 and absf(calls[0][1] - emit_time) < EPS, label + "held input emits exactly once with exact authored callback age")
			check(first_spawn >= emit_time and first_spawn < emit_time + DT + EPS and actual_spawn.pos == expected_origin and actual_spawn.kind == ("meow" if kind == 0 else "heart") and actual_spawn.fighter == 0, label + "fixed-clock threshold and complete measured-origin spawn event")
			check(stationary and (max_y == 0.0 if kind == 0 else absf(max_y - 0.7875) < EPS), label + "stationary root and correct yellow .7875 m apex")
			check(f.attack == "" and f.special_cooldown == 0.0 and f.special_held and sim.attack_serial == 1, label + "holding beyond recovery and cooldown never repeats")
			sim.step(DT, [{}, {}]); sim.step(DT, [{"special":true}, {}])
			check(f.attack == "special" and sim.attack_serial == 2 and f.special_cooldown == 4.0, label + "release then fresh press works after cooldown")
			sim.emitter_provider = Callable()

func phase_and_step_tests() -> void:
	var sim = fixture(1)
	var f: Dictionary = sim.fighters[0]
	sim.step(0.0, [{"special":true}, {}])
	sim.step(0.20, [{}, {}])
	check(f.special_phase == "air" and absf(f.special_phase_clock) < EPS and f.y == 0.0 and f.vy == 5.25, "yellow exact .20 takeoff starts at vy 5.25")
	sim.step(0.28, [{}, {}])
	check(f.special_phase == "air" and absf(f.special_phase_clock - 0.28) < EPS and absf(f.y - 0.784) < EPS and absf(f.vy - 0.35) < EPS and count_event(sim, "projectile_spawn") == 1, "yellow exact .48 global/.28 air emission on analytic gravity-17.5 arc")
	sim.step(0.32, [{}, {}])
	check(f.special_phase == "land" and f.y == 0.0 and f.vy == 0.0 and count_event(sim, "land") == 1 and f.attack == "special", "yellow lands at .80, once, without early recovery")
	sim.step(0.249, [{}, {}])
	check(f.attack == "special" and f.special_phase == "land", "yellow cannot act during full .25 landing recovery")
	sim.step(0.001, [{}, {}])
	check(f.attack == "" and f.special_phase == "" and f.y == 0.0, "yellow completes at exactly 1.05 seconds")
	for kind in range(2):
		var large = fixture(kind)
		large.step(0.0, [{"special":true}, {}])
		large.step(1.20, [{}, {}])
		check(count_event(large, "projectile_spawn") == 1 and large.fighters[0].attack == "", "kind %d large step crossing emit and recovery still emits once" % kind)
		large.step(0.20, [{}, {}])
		check(count_event(large, "projectile_spawn") == 0, "kind %d large-step emission cannot repeat" % kind)
		var partial = fixture(kind)
		partial.fighters[1].invuln = 10.0
		partial.step(0.0, [{"special":true}, {}])
		var emit_time: float = Combat.MEOW_EMIT if kind == 0 else Combat.HEART_EMIT
		partial.step(emit_time + 0.01, [{}, {}])
		check(partial.projectiles.size() == 1 and absf(partial.projectiles[0].age - 0.01) < EPS and absf(partial.projectiles[0].distance - 0.036) < EPS, "kind %d new wave advances only time after exact emission" % kind)

func rejected_inputs_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d " % [kind, face]
			var sim = fixture(kind, face)
			var f: Dictionary = sim.fighters[0]
			sim.step(DT, [{"jump":true}, {}]); sim.step(DT, [{"special":true}, {}])
			check(f.y > 0.0 and f.attack == "" and f.special_cooldown == 0.0 and sim.attack_serial == 0, label + "airborne special is rejected without spending cooldown")
			tick(sim, 100, {"special":true})
			check(f.y == 0.0 and f.attack == "" and sim.attack_serial == 0, label + "held airborne rejection cannot auto-fire at landing")
			sim.step(DT, [{}, {}]); sim.step(DT, [{"special":true}, {}])
			check(f.attack == "special", label + "fresh grounded press after rejected air press works")
			sim = fixture(kind, face); f = sim.fighters[0]
			sim.step(DT, [{"punch":true}, {}]); sim.step(DT, [{"special":true}, {}])
			tick(sim, 80, {"special":true})
			check(f.attack == "" and f.queued == "" and f.special_cooldown == 0.0 and sim.projectile_serial == 0, label + "busy special press is consumed, never queued")
			sim = fixture(kind, face); f = sim.fighters[0]
			sim.step(0.0, [{"special":true}, {}]); tick(sim, 90)
			sim.step(DT, [{"special":true}, {}])
			check(f.attack == "" and sim.attack_serial == 1 and f.special_cooldown > 2.0, label + "cooldown rejects otherwise ready fresh press")
			tick(sim, 180, {"special":true})
			check(f.special_cooldown == 0.0 and sim.attack_serial == 1, label + "held cooldown rejection cannot auto-fire at expiration")
			sim = fixture(kind, face); f = sim.fighters[0]
			sim.step(0.0, [{"special":true}, {}]); tick(sim, 239)
			check(f.special_cooldown > 0.0, label + "cooldown remains before exact four seconds")
			sim.step(DT, [{"special":true}, {}])
			check(sim.attack_serial == 2 and f.special_cooldown == 4.0, label + "new press at exactly four seconds is usable without float drift")

func hits_blocks_and_misses_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d " % [kind, face]
			var wave: String = "meow" if kind == 0 else "heart"
			var sim = fixture(kind, face)
			var f: Dictionary = sim.fighters[0]
			var o: Dictionary = sim.fighters[1]
			sim.step(0.0, [{"special":true}, {}])
			var hits := 0
			for frame in range(150):
				sim.step(DT, [{}, {}]); hits += count_event(sim, "hit", wave)
			check(hits == 1 and o.hp == 88.0 and not o.down and f.hp == 100.0, label + "real cast hits opponent once for 12, never owner, no normal knockdown")
			for defense in ["none", "front", "break", "air", "rear"]:
				sim = fixture(kind, face); o = sim.fighters[1]
				var command: Dictionary = {} if defense == "none" else {"move":face}
				if defense == "break": o.guard = 20.0
				if defense == "air": o.y = 0.25
				var direction: int = -face if defense == "rear" else face
				inject(sim, 0, wave, Vector2(o.x - direction * 0.275, 1.2), Vector2(direction * 3.6, 0.0))
				sim.step(DT, [{}, command])
				if defense == "front":
					check(o.hp == 100.0 and absf(o.guard - 71.85) < EPS and count_event(sim, "block", wave) == 1 and sim.projectiles.is_empty(), label + "front ground retreat consumes wave and exactly 28 guard plus normal drain")
				else:
					check(o.hp == 88.0 and sim.projectiles.is_empty() and not o.down and absf(o.stun - (0.43 if defense == "break" else 0.26)) < EPS and absf(o.vx - direction * 0.24 / 0.13) < EPS, label + defense + " collision uses 12 damage/.26 stun/.24 push and existing guard-break rules")
					if defense == "break": check(o.guard == 0.0 and count_event(sim, "break", wave) == 1, label + "insufficient guard breaks rather than partially blocking")
				var swept_point := Vector2.INF
				var feedback: Dictionary = {}
				for event: Dictionary in sim.events:
					if event.type == "projectile_despawn": swept_point = event.pos
					if event.type in ["hit", "block", "break"]: feedback = event
				check(feedback.has("impact_x") and absf(float(feedback.get("impact_x", INF)) - swept_point.x) < EPS and absf(float(feedback.get("impact_y", INF)) - swept_point.y) < EPS, label + defense + " feedback preserves exact swept world XY before pushback")
				tick(sim, 80)
				check(o.hp == (100.0 if defense == "front" else 88.0), label + defense + " consumed wave cannot hit twice after invulnerability ends")
			for height in [0.10, 1.97]:
				sim = fixture(kind, face); o = sim.fighters[1]
				inject(sim, 0, wave, Vector2(o.x - face * 0.40, height), Vector2(face * 3.6, 0.0))
				sim.step(0.20, [{}, {}])
				check(o.hp == 100.0, label + "swept wave misses unchanged hurtbox at height %.2f" % height)
			# A target above a horizontal shot is also missed. This fixture does
			# not claim the ordinary low jump clears every real mouth-height shot.
			sim = fixture(kind, face); o = sim.fighters[1]; o.y = 2.0
			inject(sim, 0, wave, Vector2(o.x - face * 0.30, 1.65), Vector2(face * 3.6, 0.0))
			sim.step(DT, [{}, {}])
			check(o.hp == 100.0 and not sim.projectiles.is_empty(), label + "airborne hurtbox above wave is not invisibly enlarged")

func interruption_and_snapshot_tests() -> void:
	for kind in range(2):
		for face in [-1, 1]:
			var label := "kind %d face %d " % [kind, face]
			var sim = fixture(kind, face)
			var f: Dictionary = sim.fighters[0]
			sim.step(0.0, [{"special":true}, {}])
			sim.step(0.30, [{}, {}])
			var y_before: float = f.y
			var vy_before: float = f.vy
			inject(sim, 1, "meow", Vector2(f.x + face * 0.20, f.y + 1.0), Vector2(-face * 3.6, 0.0))
			sim.step(0.0, [{}, {}])
			check(f.attack == "" and f.special_phase == "" and absf(f.special_cooldown - 3.7) < EPS and f.hp == 88.0, label + "pre-emission hit interrupts cast without refund")
			check(f.y == y_before and f.vy == vy_before, label + "interruption preserves analytic root position and velocity")
			tick(sim, 100)
			check(sim.projectile_serial == 1 and f.y == 0.0, label + "interrupted startup never emits later and airborne yellow still lands")
			# Once emitted, a wave remains independent of its owner taking a hit.
			sim = fixture(kind, face); f = sim.fighters[0]
			sim.fighters[1].invuln = 10.0
			sim.step(0.0, [{"special":true}, {}])
			sim.step(0.39 if kind == 0 else 0.49, [{}, {}])
			var existing_id: int = sim.projectiles[0].id
			inject(sim, 1, "meow", Vector2(f.x + face * 0.20, f.y + 1.0), Vector2(-face * 3.6, 0.0))
			sim.step(0.0, [{}, {}])
			check(f.hp == 88.0 and sim.projectiles.size() == 1 and sim.projectiles[0].id == existing_id, label + "emitted wave survives owner interruption")
	for face in [-1, 1]:
		var sim = fixture(1, face)
		sim.fighters[1].invuln = 10.0
		sim.step(0.0, [{"special":true}, {}]); sim.step(0.48, [{}, {}])
		var p: Dictionary = sim.projectiles[0]
		var original_velocity: Vector2 = p.velocity
		var target_snapshot: Vector2 = p.target_snapshot
		check(absf(original_velocity.x - face * 3.6) < EPS and original_velocity.y < 0.0 and target_snapshot == Vector2(sim.fighters[1].x, 1.2), "heart face %d snapshots opponent upper body and travels forward/down" % face)
		sim.fighters[1].x = 0.0; sim.fighters[1].y = 1.0
		sim.step(DT, [{}, {}])
		check(p.velocity == original_velocity and p.target_snapshot == target_snapshot, "heart face %d never homes after target moves" % face)
		# A head/hand position sufficiently forward creates an authentic close
		# overshoot with the same 1.2m aim floor and unmodified .26/1.92 hurtbox.
		sim = fixture(1, face)
		sim.fighters[0].x = 0.0; sim.fighters[1].x = face * 0.70
		sim.emitter_provider = func(_index: int, _age: float) -> Vector2: return Vector2(face * 0.50, 2.90)
		sim.step(0.0, [{"special":true}, {}]); tick(sim, 100)
		check(sim.fighters[1].hp == 100.0, "heart face %d close target naturally whiffs beneath descending wave without a special immunity rule" % face)
		sim.emitter_provider = Callable()

func sweep_owner_and_lifetime_tests() -> void:
	for kind in ["meow", "heart"]:
		for face in [-1, 1]:
			var label := "%s face %d " % [kind, face]
			var sim = fixture(0, face)
			inject(sim, 0, kind, Vector2(-1.8 * face, 1.2), Vector2(face * 3.6, 0.0))
			sim.step(1.0, [{}, {}])
			check(sim.fighters[1].hp == 88.0 and sim.fighters[0].hp == 100.0 and sim.projectiles.is_empty(), label + "large swept segment hits despite endpoint beyond opponent, owner ignored")
			for ignored in ["invulnerable", "down"]:
				sim = fixture(0, face)
				var o: Dictionary = sim.fighters[1]
				if ignored == "invulnerable": o.invuln = 10.0
				else: sim._enter_down(o, 1, "kick")
				inject(sim, 0, kind, Vector2(o.x - face * 0.30, 1.2), Vector2(face * 3.6, 0.0))
				sim.step(0.10, [{}, {}])
				check(o.hp == 100.0 and sim.projectiles.size() == 1 and count_event(sim, "projectile_despawn") == 0, label + ignored + " target is intangible and does not consume projectile")
			sim = fixture(0, face)
			inject(sim, 0, kind, Vector2((Combat.RIGHT - 0.10) if face > 0 else (Combat.LEFT + 0.10), 3.0), Vector2(face * 3.6, 0.0))
			sim.step(0.10, [{}, {}])
			check(sim.projectiles.is_empty() and count_event(sim, "projectile_despawn") == 1 and sim.events[0].reason == "boundary", label + "arena wall consumes wave")
			sim = fixture(0, face)
			inject(sim, 0, kind, Vector2(0.0, 0.10), Vector2(face * 3.6, -3.6))
			sim.step(0.10, [{}, {}])
			check(sim.projectiles.is_empty() and count_event(sim, "projectile_despawn") == 1, label + "descending wave consumes at floor boundary")
			sim = fixture(0, face)
			inject(sim, 0, kind, Vector2(0.0, 3.0), Vector2(face * 3.6, 0.0), 1.24)
			sim.step(0.03, [{}, {}])
			check(sim.projectiles.is_empty() and sim.events[0].reason == "lifetime" and absf(sim.events[0].pos.x - face * 0.036) < EPS, label + "lifetime clips final segment rather than over-travelling")
			sim = fixture(0, face)
			inject(sim, 0, kind, Vector2(0.0, 3.0), Vector2(face * 3.6, 0.0), 0.0, 4.49)
			sim.step(0.03, [{}, {}])
			check(sim.projectiles.is_empty() and sim.events[0].reason == "range" and absf(sim.events[0].pos.x - face * 0.01) < EPS, label + "4.5 horizontal metre range clips final segment")

	# Invalid/out-of-bounds starting points must not exploit a hurtbox extending
	# beyond the stage or hit on the zero-length segment of an expired wave.
	for reason in ["outside", "expired", "range"]:
		var sim = fixture()
		sim.fighters[1].x = Combat.RIGHT
		var position := Vector2(Combat.RIGHT + 0.10 if reason == "outside" else Combat.RIGHT - 0.10, 1.2)
		inject(sim, 0, "meow", position, Vector2(3.6, 0.0), 1.26 if reason == "expired" else 0.0, 4.51 if reason == "range" else 0.0)
		sim.step(0.0, [{}, {}])
		check(sim.fighters[1].hp == 100.0 and sim.projectiles.is_empty(), reason + " wave cannot hit with a zero-length clipped segment")

func owner_crossup_impact_test() -> void:
	for kind in ["meow", "heart"]:
		for face in [-1, 1]:
			var sim = fixture(0, face)
			var opponent: Dictionary = sim.fighters[1]
			var expected_x: float = opponent.x - face * Combat.HURT_X
			inject(sim, 0, kind, Vector2(opponent.x - face * 0.30, 1.2), Vector2(face * 3.6, 0.0))
			# The old projectile keeps travelling while its owner crosses behind
			# the target. Feedback must not choose the owner's new side.
			sim.fighters[0].x = opponent.x + face * 0.70
			sim.step(DT, [{}, {}])
			var hit: Dictionary = {}
			for event: Dictionary in sim.events:
				if event.type == "hit": hit = event
			check(opponent.hp == 88.0 and hit.has("impact_x") and absf(float(hit.get("impact_x", INF)) - expected_x) < EPS and absf(float(hit.get("impact_y", INF)) - 1.2) < EPS and (float(hit.get("impact_x", INF)) - opponent.x) * face < 0.0, "%s face %d owner cross-up preserves old wave's exact swept impact side and position" % [kind, face])
	var melee = fixture()
	melee.fighters[0].x = 0.0; melee.fighters[1].x = 0.70
	melee.begin_attack(melee.fighters[0], "punch"); melee.fighters[0].clock = 0.20
	melee.step(0.0, [{}, {}])
	var immutable_melee_anchor := false
	for event: Dictionary in melee.events:
		if event.type == "hit":
			immutable_melee_anchor = event.has("impact_x") and event.has("impact_y") and absf(float(event.impact_x) - 0.43) < EPS and absf(float(event.impact_y) - 1.30) < EPS
	check(immutable_melee_anchor, "ordinary melee feedback captures immutable defender-side visual XY without changing hitbox geometry")

func trade_round_and_pause_tests() -> void:
	var sim = fixture()
	inject(sim, 0, "meow", Vector2(-0.20, 3.0), Vector2(3.6, 0.0))
	inject(sim, 1, "heart", Vector2(0.20, 3.0), Vector2(-3.6, 0.0))
	sim.step(0.10, [{}, {}])
	check(sim.projectiles.size() == 2 and sim.projectiles[0].pos.x > sim.projectiles[1].pos.x, "opposing projectiles pass through each other without cancellation")
	for ko in [false, true]:
		sim = fixture()
		if ko: sim.fighters[0].hp = 12.0; sim.fighters[1].hp = 12.0
		inject(sim, 0, "meow", Vector2(sim.fighters[1].x - 0.30, 1.2), Vector2(3.6, 0.0))
		inject(sim, 1, "heart", Vector2(sim.fighters[0].x + 0.30, 1.2), Vector2(-3.6, 0.0))
		sim.step(DT, [{}, {}])
		check(sim.fighters[0].hp == (0.0 if ko else 88.0) and sim.fighters[1].hp == (0.0 if ko else 88.0) and count_event(sim, "hit") == 2, "simultaneous opposite waves trade fairly, including double KO=%s" % ko)
		if ko: check(sim.round_over and sim.winner == -1 and sim.fighters[0].down_ko and sim.fighters[1].down_ko and sim.projectiles.is_empty(), "double wave KO clears projectiles and enters existing KO/down path")
	# Melee + projectile contact collection is also simultaneous.
	sim = fixture(); sim.fighters[0].x = 0.0; sim.fighters[1].x = 0.70
	sim.begin_attack(sim.fighters[0], "punch"); sim.fighters[0].clock = 0.20
	inject(sim, 1, "heart", Vector2(0.20, 1.2), Vector2(-3.6, 0.0))
	sim.step(0.0, [{}, {}])
	check(sim.fighters[0].hp == 88.0 and sim.fighters[1].hp == 92.0, "melee/projectile simultaneous contact trades before interruption clears attack")
	# Pausing means no simulation step. Input cleanup must not advance any timer.
	sim = fixture(1); sim.step(0.0, [{"special":true}, {}]); sim.step(0.49, [{}, {}])
	var paused_projectiles: Array = sim.projectiles.duplicate(true)
	var paused_clock: float = sim.fighters[0].clock
	var paused_cooldown: float = sim.fighters[0].special_cooldown
	var paused_time: float = sim.time_left
	sim.cancel_pending_inputs()
	check(sim.projectiles == paused_projectiles and sim.fighters[0].clock == paused_clock and sim.fighters[0].special_cooldown == paused_cooldown and sim.time_left == paused_time and not sim.fighters[0].special_held, "pause cleanup freezes wave/cast/cooldown/round time and rearms fresh input only")
	sim.step(DT, [{}, {}])
	check(sim.projectiles[0].age > paused_projectiles[0].age and sim.fighters[0].special_cooldown < paused_cooldown, "resuming simulation advances frozen projectiles and cooldown normally")
	sim.time_left = DT / 2.0; sim.step(DT, [{}, {}])
	check(sim.round_over and sim.projectiles.is_empty(), "timeout clears airborne waves immediately")
	var ended_hp: Array = [sim.fighters[0].hp, sim.fighters[1].hp]
	sim.step_post_round(0.5)
	check(sim.projectiles.is_empty() and ended_hp == [sim.fighters[0].hp, sim.fighters[1].hp], "post-round settling never deals projectile damage")
	sim.reset(0)
	check(sim.projectiles.is_empty() and sim.projectile_serial == 0 and sim.attack_serial == 0 and not sim.round_over and sim.fighters[0].special_cooldown == 0.0 and sim.fighters[0].special_phase == "", "rematch/reset clears waves, cooldown, cast state, ids and round state")

func ai_tests() -> void:
	var special_choices := 0
	var cooling_choices := 0
	var early_choices := 0
	var private_independent := true
	for seed_value in range(1, 25):
		var first = Brain.new(); first.rng.seed = seed_value; first.reset()
		var second = Brain.new(); second.rng.seed = seed_value; second.reset()
		var a = fixture(); var b = fixture()
		for frame in range(120):
			b.fighters[0].special_held = frame % 2 == 0
			b.fighters[0].punch_held = frame % 3 == 0
			b.fighters[0].queued = "straight" if frame % 2 == 0 else ""
			var command: Dictionary = first.act(a, DT)
			private_independent = private_independent and command == second.act(b, DT)
			if command.get("special", false):
				special_choices += 1
				if frame < 14: early_choices += 1
		check(first.snapshots.size() <= 16 and first.reaction >= 0.20, "seed %d AI observations remain finite and delayed" % seed_value)
		var cooling = Brain.new(); cooling.rng.seed = seed_value; cooling.reset()
		a.fighters[1].special_cooldown = 2.0
		for frame in range(120):
			if cooling.act(a, DT).get("special", false): cooling_choices += 1
	check(special_choices > 0 and special_choices < 200 and early_choices == 0, "AI occasionally chooses signature at distance only after public reaction delay")
	check(cooling_choices == 0 and private_independent, "AI respects own public cooldown and never reads private player input/queues")

func run_tests() -> void:
	config_and_cast_tests()
	phase_and_step_tests()
	rejected_inputs_tests()
	hits_blocks_and_misses_tests()
	interruption_and_snapshot_tests()
	sweep_owner_and_lifetime_tests()
	owner_crossup_impact_test()
	trade_round_and_pause_tests()
	ai_tests()
	print("Projectile checks: ", checks, "; failures: ", failures)
	quit(mini(failures, 255))
