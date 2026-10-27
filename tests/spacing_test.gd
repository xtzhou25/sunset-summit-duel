extends SceneTree
## Pure 60 Hz spacing / directional control regression. Uses ordinary commands
## except explicit initial positions and the AI's intentionally stale chase plan.
## godot --headless --path . --script tests/spacing_test.gd
const Combat = preload("res://scripts/combat.gd")
const Brain = preload("res://scripts/ai.gd")
const DT := 1.0 / 60.0
const EPS := 0.00001
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else: failures += 1; printerr("FAIL: ", label)

func fixture(kind: int, direction: int = 1, gap: float = 0.7):
	var sim = Combat.new()
	sim.reset(kind)
	sim.fighters[0].x = -direction * gap * 0.5
	sim.fighters[1].x = direction * gap * 0.5
	sim.fighters[0].face = direction
	sim.fighters[1].face = -direction
	return sim

func bounds_ok(sim) -> bool:
	for f: Dictionary in sim.fighters:
		if not is_finite(f.x) or not is_finite(f.y) or f.x < Combat.LEFT - EPS or f.x > Combat.RIGHT + EPS or f.y < 0.0: return false
	if sim.fighters[0].y == 0.0 and sim.fighters[1].y == 0.0:
		return absf(sim.fighters[0].x - sim.fighters[1].x) >= Combat.BODY * 2.0 - EPS
	return true

func jump_and_landing_tests() -> void:
	for kind in range(2):
		for direction in [-1, 1]:
			for gap in [0.7, 0.9, 1.1]:
				var sim = fixture(kind, direction, gap)
				var peak := 0.0
				var air_frames := 0
				var clear_frames := 0
				var crossed_air := false
				var landed_far_side := false
				var max_step := 0.0
				var valid := true
				for frame in range(70):
					var before: float = sim.fighters[0].x
					var moving: bool = frame == 0 or sim.fighters[0].y > 0.0
					sim.step(DT, [{"move":float(direction) if moving else 0.0, "jump":frame == 0}, {}])
					var f: Dictionary = sim.fighters[0]
					peak = maxf(peak, f.y)
					max_step = maxf(max_step, absf(f.x - before))
					valid = valid and bounds_ok(sim)
					if f.y > 0.0: air_frames += 1
					if f.y >= Combat.AIR_PASS_HEIGHT: clear_frames += 1
					if f.y > 0.0 and (f.x - sim.fighters[1].x) * direction > 0.0: crossed_air = true
					if frame > 0 and f.y == 0.0: landed_far_side = (f.x - sim.fighters[1].x) * direction >= 0.7 - EPS
				var label := "kind %d direction %d gap %.1f" % [kind, direction, gap]
				check(crossed_air and landed_far_side and valid, label + " ordinary diagonal jump clears stationary opponent and lands naturally on far side")
				check(peak > 1.10 and peak < 1.20 and air_frames * DT >= 0.70 and clear_frames * DT >= 0.50, label + " bounded jump has generous measurable crossing window")
				check(max_step <= 0.075 and sim.fighters[0].face == -direction and sim.fighters[1].face == direction, label + " landing has no root teleport and both fighters reacquire crossed facing")
				print("SPACING JUMP ", label, " peak=", peak, " airtime=", (air_frames + 1) * DT, " clear_window=", clear_frames * DT, " max_root_step=", max_step)
			# Escape from either wall, then test landing against a wall with no
			# available space beyond the opponent. Neither route may leave arena.
			for escape in [true, false]:
				var sim = fixture(kind, direction)
				var wall: float = Combat.LEFT if direction > 0 else Combat.RIGHT
				if escape:
					sim.fighters[0].x = wall
					sim.fighters[1].x = wall + direction * 0.7
				else:
					wall = Combat.RIGHT if direction > 0 else Combat.LEFT
					sim.fighters[0].x = wall - direction * 0.7
					sim.fighters[1].x = wall
				var valid := true
				var max_step := 0.0
				for frame in range(90):
					var before: float = sim.fighters[0].x
					sim.step(DT, [{"move":float(direction), "jump":frame == 0}, {}])
					valid = valid and bounds_ok(sim)
					max_step = maxf(max_step, absf(sim.fighters[0].x - before))
				check(valid and sim.fighters[0].y == 0.0 and max_step < 0.15, "kind %d direction %d wall escape=%s stays bounded and smoothly re-separates after landing" % [kind, direction, str(escape)])
				if escape: check((sim.fighters[0].x - sim.fighters[1].x) * direction >= 0.7 - EPS, "wall jump escapes to opponent's far side")

func directional_control_tests() -> void:
	for direction in [-1, 1]:
		var sim = fixture(0, direction, 3.0)
		var f: Dictionary = sim.fighters[0]
		sim.step(DT, [{"jump":true, "move":float(direction)}, {}])
		check(f.vx == direction * Combat.SPEED and f.y > 0.0, "direction %d simultaneous up + lateral produces diagonal launch" % direction)
		for frame in range(5): sim.step(DT, [{"move":float(direction)}, {}])
		var old_vx: float = f.vx
		sim.step(DT, [{"move":float(-direction)}, {}])
		check(f.vx * direction > 0.0 and absf(f.vx - old_vx) <= Combat.AIR_ACCELERATION * DT + EPS, "direction %d first airborne reverse accelerates, never snaps velocity" % direction)
		var gradual := true
		for frame in range(23):
			old_vx = f.vx
			sim.step(DT, [{"move":float(-direction)}, {}])
			gradual = gradual and absf(f.vx - old_vx) <= Combat.AIR_ACCELERATION * DT + EPS
		check(gradual and f.y > 0.0 and is_equal_approx(f.vx, -direction * Combat.SPEED), "direction %d held reverse changes airborne trajectory within bounded acceleration" % direction)
		old_vx = f.vx
		sim.step(DT, [{}, {}])
		check(absf(f.vx) < absf(old_vx) and absf(f.vx) > 0.0, "direction %d releasing airborne movement smoothly decelerates" % direction)
	var sim = fixture(0, 1, 3.0)
	var landings := 0
	for frame in range(150):
		sim.step(DT, [{"jump":true}, {}])
		for event: Dictionary in sim.events:
			if event.type == "land" and event.fighter == 0: landings += 1
	check(landings == 1 and sim.fighters[0].y == 0.0, "holding up through landing produces one jump, not automatic bunny hopping")
	sim.step(DT, [{}, {}]); sim.step(DT, [{"jump":true}, {}])
	check(sim.fighters[0].y > 0.0, "release and fresh up re-arms the next jump")
	sim.cancel_pending_inputs()
	check(not sim.fighters[0].jump_held, "pause/input cancellation also clears the jump edge latch")

func retreat_and_crouch_tests() -> void:
	for kind in range(2):
		for direction in [-1, 1]:
			var sim = fixture(kind, direction)
			var f: Dictionary = sim.fighters[0]
			var initial_x: float = f.x
			for frame in range(18): sim.step(DT, [{"move":float(-direction)}, {}])
			check(absf(absf(f.x - initial_x) - 0.435) < EPS and f.blocking and f.guard < 100.0, "kind %d direction %d retreat travels .435 m in .30 s while retaining frontal guard cost" % [kind, direction])
			check(Combat.RETREAT_SPEED > 0.66 * 2.0 and Combat.RETREAT_SPEED < Combat.SPEED, "retreat is clearly faster than RC7 but remains slower than forward approach")
			initial_x = f.x
			for frame in range(18): sim.step(DT, [{"crouch":true, "move":float(-direction)}, {}])
			check(f.crouching and f.state == "crouch" and f.crouch_amount == 1.0 and f.x == initial_x and not f.blocking, "kind %d direction %d held down reaches stable crouch without walking or extra shield" % [kind, direction])
			sim.step(DT, [{"move":float(direction)}, {}])
			check(not f.crouching and f.crouch_amount > 0.0 and f.crouch_amount < 1.0 and f.x != initial_x, "crouch release begins smooth stand without adding a movement lock")
			for frame in range(12): sim.step(DT, [{}, {}])
			check(f.crouch_amount == 0.0, "crouch release completes within .18 seconds plus fixed-step rounding")
			sim.step(DT, [{"crouch":true}, {}]); sim.step(DT, [{"crouch":true,"punch":true}, {}])
			check(f.attack == "punch" and not f.crouching and f.crouch_amount == 0.0, "fresh existing ground attack immediately takes priority over crouch")
			sim = fixture(kind, direction, 3.0); f = sim.fighters[0]
			sim.step(DT, [{"crouch":true}, {}]); sim.step(DT, [{"crouch":true,"jump":true}, {}])
			check(f.y > 0.0 and not f.crouching and f.crouch_amount == 0.0, "fresh up exits crouch immediately with no extra recovery")
			for frame in range(12): sim.step(DT, [{"crouch":true}, {}])
			check(f.y > 0.0 and not f.crouching and f.crouch_amount == 0.0 and not f.blocking, "down held airborne adds neither crouch nor guard")
			sim.reset(kind)
			check(not sim.fighters[0].crouching and sim.fighters[0].crouch_amount == 0.0 and not sim.fighters[0].jump_held, "round reset clears new locomotion-only state")

func heavy_fixture(kind: int, direction: int, defense: String = "hit", wall: bool = false):
	var sim = fixture(kind, direction)
	if wall:
		sim.fighters[1].x = Combat.RIGHT if direction > 0 else Combat.LEFT
		sim.fighters[0].x = sim.fighters[1].x - direction * 0.7
	if defense == "break":
		sim.fighters[1].guard = 10.0
		sim.fighters[1].guard_delay = 10.0
	return sim

func heavy_spacing_tests() -> void:
	for kind in range(2):
		for direction in [-1, 1]:
			var distances: Dictionary = {}
			for defense in ["hit", "block", "break", "air"]:
				var sim = heavy_fixture(kind, direction, defense)
				var start: float = sim.fighters[1].x
				var contacts := 0
				var travel := 0.0
				var contact_shift := 0.0
				var valid := true
				for frame in range(90):
					var other: Dictionary = {}
					if defense in ["block", "break"] and sim.fighters[0].clock >= 0.31 and contacts == 0: other.move = float(direction)
					if defense == "air" and frame == 0: other.jump = true
					var previous_x: float = sim.fighters[1].x
					sim.step(DT, [{"heavy":frame == 0}, other])
					for event: Dictionary in sim.events:
						if event.type in ["hit", "block", "break"] and event.kind == "heavy":
							contacts += 1
							start = previous_x if defense == "block" else sim.fighters[1].x
							contact_shift = absf(sim.fighters[1].x - previous_x) - (Combat.RETREAT_SPEED * DT if defense == "block" else 0.0)
					if contacts > 0: travel = maxf(travel, (sim.fighters[1].x - start) * direction)
					valid = valid and bounds_ok(sim)
				distances[defense] = travel
				var label := "kind %d direction %d heavy %s" % [kind, direction, defense]
				check(contacts == 1 and valid and not sim.fighters[1].down and sim.fighters[1].y == 0.0 and sim.fighters[1].hp == (100.0 if defense == "block" else 84.0), label + " resolves once with unchanged damage, no new knockdown, and bounded landing")
				if defense == "hit": check(absf(travel - 0.82) < EPS, label + " produces .82 m measured ground knockback during original .30 s stun")
				if defense == "block": check(absf(contact_shift - 0.182) < EPS and sim.fighters[1].stun_duration == 0.0, label + " has distinct .182 m block impulse, no hitstun or damage")
				if defense == "break": check(travel > 0.82 and travel < 1.0 and is_equal_approx(sim.fighters[1].stun_duration, 0.47), label + " stronger guard-break drift stays below 1 m and keeps .47 s stun")
				print("SPACING HEAVY ", label, " travel=", travel, " block_impulse=", contact_shift)
			check(distances.hit > distances.block * 3.5 and distances.air > 0.8 and distances.air < 1.0, "heavy unblocked hit clearly separates more than block; airborne hit remains bounded")
			var sim = heavy_fixture(kind, direction, "hit", true)
			var valid := true
			for frame in range(120):
				sim.step(DT, [{"heavy":frame == 0}, {}])
				valid = valid and bounds_ok(sim)
			check(valid and sim.fighters[1].hp == 84.0 and sim.fighters[1].x == (Combat.RIGHT if direction > 0 else Combat.LEFT), "kind %d direction %d heavy at wall clamps without penetration or repeated damage" % [kind, direction])

func ai_reassessment_tests() -> void:
	for kind in range(2):
		for direction in [-1, 1]:
			var sim = fixture(kind, direction)
			sim.step(DT, [{"heavy":true}, {}])
			for frame in range(40):
				sim.step(DT, [{}, {}])
				if sim.fighters[1].hp < 100.0: break
			var brain = Brain.new(); brain.reset(); brain.rng.seed = 19
			# Exact stale chase fixture: a previously held approach must not be
			# replayed on the first frame of recovery from the public heavy hit.
			brain.held = float(-direction)
			brain.remaining = 0.30
			var neutral := true
			var recovered_at := -1.0
			var resumed_at := -1.0
			var attacker_recovery_gap := -1.0
			var bounded_history := true
			for frame in range(120):
				if sim.fighters[1].stun <= 0.0 and recovered_at < 0.0: recovered_at = frame * DT
				var output: Dictionary = brain.act(sim, DT)
				var active: bool = output.get("move",0.0) != 0.0 or output.get("punch",false) or output.get("heavy",false) or output.get("kick",false) or output.get("roundhouse",false) or output.get("special",false) or output.get("jump",false)
				if recovered_at < 0.0 or frame * DT - recovered_at < 0.20: neutral = neutral and not active
				if recovered_at >= 0.0 and active and resumed_at < 0.0: resumed_at = frame * DT
				bounded_history = bounded_history and brain.snapshots.size() <= 16
				sim.step(DT, [{}, output])
				if sim.fighters[0].attack == "" and attacker_recovery_gap < 0.0: attacker_recovery_gap = absf(sim.fighters[1].x - sim.fighters[0].x)
			check(neutral and recovered_at > 0.0 and resumed_at - recovered_at >= 0.20 and resumed_at - recovered_at <= 0.30, "kind %d direction %d AI cancels stale chase for a bounded public-state post-heavy reassessment" % [kind, direction])
			check(attacker_recovery_gap >= 1.35 and bounded_history, "kind %d direction %d heavy leaves actionable gap when attacker recovers; AI history stays bounded" % [kind, direction])
			brain.reset()
			check(brain.reassess_remaining == 0.0 and brain.held == 0.0 and brain.snapshots.is_empty(), "AI round reset clears spacing reassessment and stale input")
			print("SPACING AI kind=", kind, " direction=", direction, " recovery_gap=", attacker_recovery_gap, " poststun_pause=", resumed_at - recovered_at)

func repeated_crossups() -> void:
	for kind in [0,1]:
		for direction in [-1,1]:
			for attempt in range(20):
				var gap:float=0.7+float(attempt%5)*0.1
				var sim=fixture(kind,direction,gap)
				var crossed:=false
				var valid:=true
				for frame in range(70):
					var f:Dictionary=sim.fighters[0]
					var moving:bool=frame==0 or f.y>0.0
					sim.step(DT,[{"jump":frame==0,"move":float(direction) if moving else 0.0},{}])
					valid=valid and bounds_ok(sim)
					if f.y>0.0 and (f.x-sim.fighters[1].x)*direction>0.0:crossed=true
				var f:Dictionary=sim.fighters[0]
				check(valid and crossed and f.y==0.0 and (f.x-sim.fighters[1].x)*direction>=Combat.BODY*2.0-EPS and f.face==-direction,"repeated cross kind%d direction%d attempt%d succeeds without rebound"%[kind,direction,attempt+1])

func _init() -> void:
	repeated_crossups()
	jump_and_landing_tests()
	directional_control_tests()
	retreat_and_crouch_tests()
	heavy_spacing_tests()
	ai_reassessment_tests()
	check(Combat.HEART_JUMP_VELOCITY == 5.25 and Combat.GRAVITY == 17.5 and is_equal_approx(Combat.new().special_root_height(1,0.50),0.7875), "signature heart trajectory and all gravity stay unchanged by ordinary jump tuning")
	print("Spacing checks: ", checks, "; failures: ", failures)
	quit(mini(failures, 255))
