extends SceneTree
## v3 simulation-only tests. Real commands create normal knockdowns; explicitly
## named snapshots isolate immunity/contact boundaries without renderer state.
## Run with Godot --headless --path . --script tests/knockdown_test.gd.
const Combat = preload("res://scripts/combat.gd")
const DT := 1.0 / 60.0
const EPS := 0.00001
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else: failures += 1; printerr("FAIL: ", label)

func fixture(kind: int = 0, direction: int = 1):
	var sim = Combat.new()
	sim.reset(kind)
	sim.fighters[0].x = -Combat.BODY * direction
	sim.fighters[1].x = Combat.BODY * direction
	sim.fighters[0].face = direction
	sim.fighters[1].face = -direction
	return sim

func count_event(sim, event_type: String, target: int = -1) -> int:
	var result := 0
	for event: Dictionary in sim.events:
		if event.type == event_type and (target < 0 or int(event.get("fighter", -1)) == target):
			result += 1
	return result

func contact(sim, attack: String, defense: Dictionary = {}) -> bool:
	for frame in range(90):
		sim.step(DT, [{attack: true} if frame == 0 else {}, defense])
		if count_event(sim, "hit", 1) + count_event(sim, "break", 1) + count_event(sim, "block", 1) > 0:
			return true
	return false

func active_punch_snapshot(sim) -> void:
	# Deliberate contact snapshot: restart a stationary punch at its measured
	# .19s extension peak, in range. Active onset no longer implies full reach.
	# No defender HP, down flag, phase, or immunity is injected.
	var attacker: Dictionary = sim.fighters[0]
	var defender: Dictionary = sim.fighters[1]
	attacker.x = defender.x - Combat.BODY * 2.0
	if attacker.x < Combat.LEFT:
		attacker.x = defender.x + Combat.BODY * 2.0
	attacker.face = 1 if defender.x > attacker.x else -1
	attacker.y = 0.0
	attacker.vy = 0.0
	attacker.vx = 0.0
	attacker.attack = "punch"
	attacker.state = "punch"
	attacker.hit = false
	attacker.clock = 0.19 - DT + EPS
	attacker.duration = 0.48 if attacker.kind == 0 else 0.52

func legacy_contract_tests() -> void:
	for kind in range(2):
		var sim = fixture(kind)
		var punch: Dictionary = sim.attack_config(sim.fighters[0], "punch")
		var kick: Dictionary = sim.attack_config(sim.fighters[0], "kick")
		check(punch == {"startup":0.14,"active":0.10,"recovery":0.24 if kind==0 else 0.28,"reach":0.55 if kind==0 else 0.59,"damage":8.0,"guard":22.0,"stun":0.24,"push":0.22,"low":0.66,"high":1.80}, "kind %d preserves v2 punch timing/damage with v4 measured reach cap" % kind)
		check(kick == {"startup":0.36,"active":0.13,"recovery":0.40 if kind==0 else 0.46,"reach":0.73 if kind==0 else 0.78,"damage":13.0,"guard":34.0,"stun":0.32,"push":0.42,"low":0.36,"high":1.65}, "kind %d preserves every v2 kick config value" % kind)
		check(contact(sim, "punch") and not sim.fighters[1].down and sim.fighters[1].state == "hurt" and is_equal_approx(sim.fighters[1].stun, 0.24), "kind %d ordinary punch remains original .24s hurt, not knockdown" % kind)
		check(count_event(sim, "down") == 0 and count_event(sim, "hit", 1) == 1, "kind %d punch keeps compatible single hit event" % kind)

func ground_lifecycle_tests() -> void:
	for kind in range(2):
		for direction in [-1, 1]:
			var sim = fixture(kind, direction)
			var label := "kind %d direction %d" % [kind, direction]
			check(contact(sim, "kick"), label + " real flying kick makes contact")
			var down: Dictionary = sim.fighters[1]
			check(down.down and down.down_phase == "fall" and down.down_clock == 0.0 and down.down_age == 0.0 and down.state == "down" and down.hp == 87.0, label + " ground contact starts recoverable loss/catch phase")
			check(count_event(sim, "hit", 1) == 1 and count_event(sim, "down", 1) == 1 and not down.down_ko, label + " emits one compatible hit and one non-KO down event")
			var config: Dictionary = sim.attack_config(sim.fighters[0], "kick")
			check(is_equal_approx(sim.fighters[0].duration, config.startup + config.active + config.recovery), label + " knockdown does not shorten or extend attacking kick")
			var start_time: float = sim.elapsed
			var phases: Array = ["fall"]
			var rise_events := 0
			var recovered_events := 0
			var locked := true
			var grounded := true
			var serial: int = sim.attack_serial
			sim.begin_attack(down, "punch")
			check(down.attack == "" and sim.attack_serial == serial, label + " public attack API rejects down fighter")
			for frame in range(150):
				down.queued = "kick"
				sim.step(DT, [{}, {"punch": true, "kick": true, "jump": true, "move": float(direction)}])
				locked = locked and down.attack == "" and not down.blocking and down.queued == "" and down.move == 0.0
				grounded = grounded and down.y == 0.0 and down.vy == 0.0
				if phases.back() != down.down_phase: phases.append(down.down_phase)
				rise_events += count_event(sim, "rise", 1)
				recovered_events += count_event(sim, "recovered", 1)
				if not down.down: break
			check(phases == ["fall", "hold", "rise", ""] and rise_events == 1 and recovered_events == 1, label + " visits loss/catch, settled hold, Recover and FightIdle once")
			check(locked and grounded, label + " repeated attacks/block/jump/queued inputs cannot bypass down or rise or floor")
			var duration: float = sim.elapsed - start_time
			check(duration >= 2.05 - EPS and duration <= 2.05 + DT + EPS and down.state == "idle", label + " ground recovery takes .80 + .25 + 1.00 seconds")
			check(is_equal_approx(down.invuln, 0.35) and down.down_clock == 0.0 and down.down_age == 0.0, label + " recovery clears phase clocks and grants .35s protection")
			for frame in range(30): sim.step(DT, [{}, {"punch": true, "kick": true, "jump": true}])
			check(down.attack == "" and down.y == 0.0 and down.input_rearm, label + " held actions do not auto-fire after recovery")
			sim.step(DT, [{}, {}])
			sim.step(DT, [{}, {"punch": true}])
			check(down.attack == "punch" and not down.input_rearm, label + " release then fresh input restores normal attack")

func guard_and_air_tests() -> void:
	for kind in range(2):
		for direction in [-1, 1]:
			var label := "kind %d direction %d" % [kind, direction]
			var sim = fixture(kind, direction)
			check(contact(sim, "kick", {"move": float(direction)}) and count_event(sim, "block", 1) == 1 and sim.fighters[1].hp == 100.0 and not sim.fighters[1].down, label + " sufficiently guarded kick blocks without knockdown")
			sim = fixture(kind, direction)
			sim.fighters[1].guard = 10.0
			sim.fighters[1].guard_delay = 10.0
			check(contact(sim, "kick", {"move": float(direction)}) and count_event(sim, "break", 1) == 1 and count_event(sim, "down", 1) == 1 and sim.fighters[1].down and sim.fighters[1].guard == 0.0 and sim.fighters[1].hp == 87.0, label + " guard-broken kick deals unchanged damage and knocks down")
			sim = fixture(kind, direction)
			for frame in range(45):
				sim.step(DT, [{"kick": true} if frame == 0 else {}, {"jump": true} if frame == 12 else {}])
				if sim.fighters[1].down: break
			var down: Dictionary = sim.fighters[1]
			check(down.down and down.down_phase == "air" and down.y > 0.35, label + " actual jump receives kick in airborne loss phase")
			var initial_y: float = down.y
			var initial_vy: float = down.vy
			sim.step(DT, [{}, {}])
			check(is_equal_approx(down.vy, initial_vy - Combat.GRAVITY * DT) and is_equal_approx(down.y, initial_y + down.vy * DT), label + " airborne knockdown retains physical velocity and original gravity")
			var airborne_valid := true
			var landing_events := 0
			for frame in range(90):
				sim.step(DT, [{}, {"jump": true}])
				landing_events += count_event(sim, "land", 1)
				if down.down_phase != "air": break
				airborne_valid = airborne_valid and down.y > 0.0 and down.down_clock > 0.0
			check(airborne_valid and landing_events == 1 and down.y == 0.0 and down.down_phase == "fall" and is_equal_approx(down.down_clock, 0.20), label + " actual floor contact starts catch at clip .20 without penetration")

func immunity_and_wall_tests() -> void:
	for kind in range(2):
		var sim = fixture(kind)
		contact(sim, "kick")
		var down: Dictionary = sim.fighters[1]
		var protected := true
		var saw_rise := false
		for frame in range(160):
			active_punch_snapshot(sim)
			sim.step(DT, [{}, {}])
			protected = protected and down.hp == 87.0 and count_event(sim, "hit", 1) == 0 and count_event(sim, "down", 1) == 0
			saw_rise = saw_rise or down.down_phase == "rise"
			if not down.down: break
		check(protected and saw_rise and not down.down, "kind %d repeated active contacts cannot damage, interrupt or restart down/rise" % kind)
		var protected_samples := 0
		for frame in range(30):
			var before: float = down.invuln
			active_punch_snapshot(sim)
			sim.step(DT, [{}, {}])
			if before > DT + EPS:
				protected_samples += 1
				protected = protected and down.hp == 87.0 and count_event(sim, "hit", 1) == 0
			if down.hp < 87.0: break
		check(protected and protected_samples >= 19, "kind %d fresh active contacts cannot damage during .35s post-rise protection" % kind)
		check(down.hp == 79.0 and not down.down and down.state == "hurt", "kind %d protection expires and normal punch hurts again, not infinite invulnerability" % kind)
		for direction in [-1, 1]:
			sim = fixture(kind, direction)
			sim.fighters[1].x = Combat.RIGHT if direction == 1 else Combat.LEFT
			sim.fighters[0].x = sim.fighters[1].x - direction * Combat.BODY * 2.0
			check(contact(sim, "kick") and sim.fighters[1].down, "kind %d wall %d kick still knocks down" % [kind, direction])
			var valid := true
			for frame in range(130):
				sim.step(DT, [{"move": float(direction)}, {"jump": true}])
				var a: Dictionary = sim.fighters[0]
				var b: Dictionary = sim.fighters[1]
				valid = valid and a.x >= Combat.LEFT and a.x <= Combat.RIGHT and b.x >= Combat.LEFT and b.x <= Combat.RIGHT and a.y >= 0.0 and b.y >= 0.0
				if absf(a.y - b.y) < 0.55: valid = valid and absf(a.x - b.x) >= Combat.BODY * 2.0 - EPS
			check(valid, "kind %d wall %d maintains physical bounds/pushboxes through recovery" % [kind, direction])

func ending_tests() -> void:
	for kind in range(2):
		for direction in [-1, 1]:
			for attack in ["punch", "kick"]:
				var sim = fixture(kind, direction)
				sim.fighters[1].hp = sim.attack_config(sim.fighters[0], attack).damage
				check(contact(sim, attack) and sim.round_over and sim.winner == 0 and sim.fighters[1].down_ko, "kind %d direction %d lethal %s enters permanent KO" % [kind, direction, attack])
				var frozen: Array = sim.fighters.duplicate(true)
				var time: float = sim.time_left
				var elapsed: float = sim.elapsed
				sim.step(0.5, [{"kick": true}, {"punch": true}])
				check(sim.fighters == frozen and sim.time_left == time and sim.elapsed == elapsed and sim.events.is_empty(), "kind %d direction %d %s ordinary step freezes finished combat" % [kind, direction, attack])
				var finish_events := 0
				for frame in range(240):
					sim.step_post_round(DT)
					finish_events += count_event(sim, "rise") + count_event(sim, "recovered") + count_event(sim, "round") + count_event(sim, "hit") + count_event(sim, "attack")
				check(sim.fighters[1].down_phase == "hold" and sim.fighters[1].down_ko and sim.fighters[1].y == 0.0 and finish_events == 0, "kind %d direction %d %s post-round KO settles forever, never rises or repeats result" % [kind, direction, attack])
				var frozen_combat := true
				for key: String in frozen[0]:
					if key not in ["x", "y", "vx", "vy", "land_lock"]:
						frozen_combat = frozen_combat and sim.fighters[0][key] == frozen[0][key]
				check(frozen_combat and sim.time_left == time and sim.elapsed == elapsed and sim.fighters[1].hp == 0.0 and sim.fighters[0].y == 0.0, "kind %d direction %d %s post-round settles flight but freezes living combat, timer and damage" % [kind, direction, attack])
		var sim = fixture(kind)
		sim.fighters[0].hp = 8.0
		sim.fighters[1].hp = 8.0
		for frame in range(25):
			sim.step(DT, [{"punch": true} if frame == 0 else {}, {"punch": true} if frame == 0 else {}])
			if sim.round_over: break
		check(sim.winner == -1 and count_event(sim, "down") == 2 and count_event(sim, "round") == 1 and sim.fighters[0].down_ko and sim.fighters[1].down_ko, "kind %d simultaneous lethal punches create two KOs and one draw" % kind)
		for frame in range(180): sim.step_post_round(DT)
		check(sim.fighters[0].down_phase == "hold" and sim.fighters[1].down_phase == "hold", "kind %d double KO settles both fighters without recovery" % kind)
		# Real airborne KO must keep falling even though normal combat has stopped.
		sim = fixture(kind)
		sim.fighters[1].hp = 13.0
		for frame in range(45):
			sim.step(DT, [{"kick": true} if frame == 0 else {}, {"jump": true} if frame == 12 else {}])
			if sim.round_over: break
		check(sim.round_over and sim.fighters[1].down_phase == "air" and sim.fighters[1].y > 0.0, "kind %d aerial KO enters post-round still airborne" % kind)
		var lands := 0
		for frame in range(180):
			sim.step_post_round(DT)
			lands += count_event(sim, "land", 1)
		check(lands == 1 and sim.fighters[1].down_phase == "hold" and sim.fighters[1].y == 0.0, "kind %d aerial KO gravity lands exactly once during result delay" % kind)

func timeout_and_reset_tests() -> void:
	for leading_down in [false, true]:
		var sim = fixture()
		contact(sim, "kick")
		if leading_down: sim.fighters[0].hp = 40.0
		sim.time_left = DT * 0.5
		sim.step(DT, [{}, {}])
		var expected_winner := 1 if leading_down else 0
		check(sim.round_over and sim.winner == expected_winner and sim.fighters[1].down and not sim.fighters[1].down_ko, "timeout uses health, not down state; leading down=%s" % leading_down)
		var frozen_hp: Array = [sim.fighters[0].hp, sim.fighters[1].hp]
		var elapsed: float = sim.elapsed
		var fresh_rounds := 0
		for frame in range(180):
			sim.step_post_round(DT)
			fresh_rounds += count_event(sim, "round")
		check(not sim.fighters[1].down and sim.fighters[1].state == "idle" and sim.fighters[0].hp == frozen_hp[0] and sim.fighters[1].hp == frozen_hp[1] and sim.elapsed == elapsed and sim.time_left == 0.0 and fresh_rounds == 0, "timeout finishes already-started living recovery without new combat/KO; leading down=%s" % leading_down)
	var sim = fixture()
	contact(sim, "kick")
	var frozen: Array = sim.fighters.duplicate(true)
	sim.step_post_round(1.0)
	check(sim.fighters == frozen and not sim.round_over, "post-round API is inert before a result")
	sim.reset(1)
	var clean := true
	for f: Dictionary in sim.fighters:
		clean = clean and not f.down and not f.down_ko and f.down_phase == "" and f.down_clock == 0.0 and f.down_age == 0.0 and not f.input_rearm and f.queued == "" and f.invuln == 0.0 and f.hit_kind == ""
	check(clean and sim.attack_serial == 0 and sim.events.is_empty() and sim.time_left == 60.0 and not sim.round_over, "reset/rematch clears all down/protection/input/event state")
	sim.time_left = DT * 0.5
	sim.step(DT, [{}, {}])
	for frame in range(120): sim.step_post_round(DT)
	check(sim.winner == -1 and sim.fighters[0].hp == 100.0 and sim.fighters[1].hp == 100.0 and not sim.fighters[0].down and not sim.fighters[1].down, "healthy equal timeout stays draw and never fabricates a KO")

func trade_and_late_timeout_tests() -> void:
	for kind in range(2):
		var sim = fixture(kind)
		sim.fighters[0].hp = 13.0
		sim.fighters[1].hp = 13.0
		for frame in range(40):
			sim.step(DT, [{"kick": true} if frame == 0 else {}, {"kick": true} if frame == 0 else {}])
			if sim.round_over: break
		check(sim.round_over and sim.winner == -1 and count_event(sim, "hit") == 2 and count_event(sim, "down") == 2 and sim.fighters[0].down_phase == "air" and sim.fighters[1].down_phase == "air", "kind %d simultaneous lethal kicks preserve two airborne contacts without index priority" % kind)
		for frame in range(180): sim.step_post_round(DT)
		check(sim.fighters[0].y == 0.0 and sim.fighters[1].y == 0.0 and sim.fighters[0].down_phase == "hold" and sim.fighters[1].down_phase == "hold", "kind %d aerial double KO settles both bodies" % kind)
		for kicker in range(2):
			sim = fixture(kind)
			for frame in range(50):
				var commands: Array = [{}, {}]
				if frame == 0: commands[kicker] = {"kick": true}
				if frame == 13: commands[1 - kicker] = {"punch": true}
				sim.step(DT, commands)
				if count_event(sim, "hit") > 0: break
			check(count_event(sim, "hit") == 2 and sim.fighters[kicker].hp == 92.0 and not sim.fighters[kicker].down and sim.fighters[kicker].state == "hurt" and sim.fighters[1 - kicker].hp == 87.0 and sim.fighters[1 - kicker].down, "kind %d mixed trade kicker %d preserves punch hurt plus kick down regardless of contact order" % [kind, kicker])
		for phase in ["hold", "rise"]:
			sim = fixture(kind)
			contact(sim, "kick")
			for frame in range(100):
				if sim.fighters[1].down_phase == phase: break
				sim.step(DT, [{}, {}])
			sim.time_left = DT * 0.5
			sim.step(DT, [{}, {}])
			for frame in range(150): sim.step_post_round(DT)
			check(sim.round_over and sim.winner == 0 and not sim.fighters[1].down and sim.fighters[1].hp == 87.0, "kind %d timeout during %s finishes living recovery without KO" % [kind, phase])
		# External result-state snapshot, used by integration tests when forcing a KO.
		sim = fixture(kind)
		contact(sim, "kick")
		for frame in range(100):
			if sim.fighters[1].down_phase == "rise": break
			sim.step(DT, [{}, {}])
		sim.fighters[1].hp = 0.0
		sim.step(DT, [{}, {}])
		for frame in range(150): sim.step_post_round(DT)
		check(sim.round_over and sim.fighters[1].down_ko and sim.fighters[1].down_phase == "hold", "kind %d zero-health result snapshot converts existing recovery to permanent KO" % kind)

func airborne_winner_tests() -> void:
	for kind in range(2):
		for direction in [-1, 1]:
			var sim = fixture(kind, direction)
			sim.fighters[1].hp = 13.0
			check(contact(sim, "kick") and sim.round_over and sim.winner == 0 and not sim.fighters[0].down and sim.fighters[0].y > 0.0, "kind %d direction %d winning kick is still physically airborne at result" % [kind, direction])
			var fighter: Dictionary = sim.fighters[0]
			var before: Dictionary = fighter.duplicate(true)
			var time: float = sim.time_left
			var elapsed: float = sim.elapsed
			sim.step_post_round(DT)
			check(is_equal_approx(fighter.vy, before.vy - Combat.GRAVITY * DT) and is_equal_approx(fighter.y, before.y + fighter.vy * DT) and absf(fighter.vx) < absf(before.vx), "kind %d direction %d post-round winner uses original gravity and horizontal deceleration" % [kind, direction])
			var lands := count_event(sim, "land", 0)
			var clean := true
			for frame in range(90):
				sim.step_post_round(DT)
				lands += count_event(sim, "land", 0)
				clean = clean and count_event(sim, "attack") == 0 and count_event(sim, "hit") == 0 and count_event(sim, "round") == 0 and fighter.x >= Combat.LEFT and fighter.x <= Combat.RIGHT and fighter.y >= 0.0 and sim.fighters[1].hp == 0.0
				if fighter.y == 0.0: break
			check(clean and lands == 1 and fighter.y == 0.0 and fighter.vy == 0.0 and fighter.vx == 0.0 and is_equal_approx(fighter.land_lock, 0.09) and sim.time_left == time and sim.elapsed == elapsed and fighter.clock == before.clock and fighter.attack == before.attack, "kind %d direction %d winning kick lands exactly once with .09s settle and no new combat or attack clock" % [kind, direction])
			var grounded: Dictionary = fighter.duplicate(true)
			sim.step_post_round(DT)
			check(is_equal_approx(fighter.land_lock, 0.09 - DT) and fighter.y == 0.0, "kind %d direction %d result landing animation interval counts down on ground" % [kind, direction])
			for frame in range(120): sim.step_post_round(DT)
			grounded.land_lock = 0.0
			check(fighter == grounded and count_event(sim, "land", 0) == 0, "kind %d direction %d landed winner finishes settle then freezes without continued sliding" % [kind, direction])
		# Both living fighters can be airborne when a timeout draw occurs.
		var sim = fixture(kind)
		sim.step(DT, [{"jump": true}, {"jump": true}])
		sim.time_left = DT * 0.5
		sim.step(DT, [{}, {}])
		var lands: Array = [0, 0]
		for frame in range(100):
			sim.step_post_round(DT)
			for i in range(2): lands[i] += count_event(sim, "land", i)
		check(sim.winner == -1 and lands == [1, 1] and sim.fighters[0].y == 0.0 and sim.fighters[1].y == 0.0 and not sim.fighters[0].down and not sim.fighters[1].down and sim.fighters[0].hp == 100.0 and sim.fighters[1].hp == 100.0, "kind %d timeout lets both already-airborne living fighters land without fabricating KO" % kind)

func fresh_wake_input_tests() -> void:
	for kind in range(2):
		for action in ["punch", "kick", "jump"]:
			var sim = fixture(kind)
			contact(sim, "kick")
			var fighter: Dictionary = sim.fighters[1]
			sim.step(DT, [{}, {action: true}])
			check(fighter.down and fighter.input_rearm and fighter.attack == "" and fighter.y == 0.0, "kind %d down consumes %s press without executing or queueing it" % [kind, action])
			sim.step(DT, [{}, {}])
			check(fighter.down and not fighter.input_rearm, "kind %d neutral during down re-arms fresh %s input" % [kind, action])
			for frame in range(150):
				sim.step(DT, [{}, {}])
				if not fighter.down: break
			check(not fighter.down and not fighter.input_rearm and fighter.attack == "" and fighter.y == 0.0, "kind %d earlier down %s tap is not buffered onto recovery" % [kind, action])
			sim.step(DT, [{}, {action: true}])
			check((fighter.y > 0.0 if action == "jump" else fighter.attack == action), "kind %d first ready-frame fresh %s press executes immediately" % [kind, action])
			# Isolate the final rise sample using real preceding down progression.
			sim = fixture(kind)
			contact(sim, "kick")
			fighter = sim.fighters[1]
			for frame in range(150):
				if fighter.down_phase == "rise" and fighter.down_clock + DT >= Combat.DOWN_RISE_DURATION: break
				sim.step(DT, [{}, {}])
			sim.step(DT, [{}, {action: true}])
			check(not fighter.down and fighter.input_rearm and fighter.attack == "" and fighter.y == 0.0, "kind %d %s on recovery-completing sample is consumed, not a wake-up buffer" % [kind, action])
			for frame in range(12): sim.step(DT, [{}, {action: true}])
			check(fighter.input_rearm and fighter.attack == "" and fighter.y == 0.0, "kind %d %s held across recovery remains rejected" % [kind, action])
			sim.step(DT, [{}, {}])
			sim.step(DT, [{}, {action: true}])
			check((fighter.y > 0.0 if action == "jump" else fighter.attack == action), "kind %d released then fresh %s works after completion-frame rejection" % [kind, action])

func _init() -> void:
	legacy_contract_tests()
	ground_lifecycle_tests()
	guard_and_air_tests()
	immunity_and_wall_tests()
	ending_tests()
	timeout_and_reset_tests()
	trade_and_late_timeout_tests()
	airborne_winner_tests()
	fresh_wake_input_tests()
	print("Knockdown checks: ", checks, "; failures: ", failures)
	quit(failures)
