extends SceneTree
## P2 simulation-owned feedback only. Real fixed-step acceptance, active markers,
## contact metadata and down catches; no damage/hitbox/timing changes.
## Run: godot --headless --path . --script tests/feedback_events_test.gd
const Combat = preload("res://scripts/combat.gd")
const DT := 1.0 / 60.0
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func count(events: Array, kind: String) -> int:
	var result := 0
	for e: Dictionary in events:
		if e.type == kind: result += 1
	return result
func interruption_and_provenance_tests() -> void:
	var sim = Combat.new()
	sim.fighters[0].x = -0.35; sim.fighters[1].x = 0.35
	var heavy_swings := 0
	var punch_swings := 0
	for frame in range(80):
		sim.step(DT,[{"heavy":true} if frame == 0 else {}, {"punch":true} if frame == 0 else {}])
		for event: Dictionary in sim.events:
			if event.type == "swing":
				if event.kind == "heavy": heavy_swings += 1
				if event.kind == "punch": punch_swings += 1
	check(sim.fighters[0].hp == 92.0 and heavy_swings == 0 and punch_swings == 1,"interrupted heavy startup never emits a phantom swing")
	sim.reset(0)
	sim.fighters[0].x = -2.1; sim.fighters[1].x = 2.1 # Keep original 4.2m provenance distance, independent of arena size.
	sim.begin_special(sim.fighters[0])
	var cast_id: int = sim.fighters[0].attack_id
	var later_attack := false
	var original_cast_contacts := 0
	for frame in range(110):
		if frame >= 61 and not later_attack and sim.fighters[0].attack == "":
			sim.begin_attack(sim.fighters[0],"punch")
			later_attack = true
		sim.step(DT,[{},{}])
		for event: Dictionary in sim.events:
			if event.type == "hit" and event.kind == "meow":
				original_cast_contacts += 1
				check(later_attack and sim.fighters[0].attack_id != cast_id and event.attack_id == cast_id and event.source == 0 and event.fighter == 1,"projectile contact keeps original cast identity after source starts another attack")
	check(original_cast_contacts == 1 and sim.fighters[1].hp == 88.0,"provenance fixture makes exactly one genuine unchanged projectile hit")
	for character in range(2):
		sim.reset(character)
		sim.fighters[0].x = Combat.RIGHT - Combat.BODY * 2.0; sim.fighters[1].x = Combat.RIGHT
		sim.fighters[1].hp = 8.0; sim.fighters[1].guard = 10.0; sim.fighters[1].guard_delay = 10.0
		var breaks := 0
		for frame in range(40):
			sim.step(DT,[{"punch":true} if frame == 0 else {}, {"move":1.0}])
			for event: Dictionary in sim.events:
				if event.type == "break":
					breaks += 1
					check(event.ko and event.source == 0 and event.fighter == 1 and event.attack_id == 1,"guard break reports KO after real HP subtraction")
			if sim.round_over: break
		check(breaks == 1 and sim.fighters[1].hp == 0.0,"guard break KO fixture preserves existing damage")

func _init() -> void:
	var highwater := 0
	var sim = Combat.new()
	for character in range(2):
		for move in ["punch","straight","heavy","kick","roundhouse","special"]:
			sim.reset(character)
			sim.fighters[0].x = Combat.LEFT; sim.fighters[1].x = Combat.RIGHT
			sim.begin_attack(sim.fighters[0],move)
			check(sim.events.size() == 1 and sim.events[0].type == "attack" and sim.events[0].source == 0 and sim.events[0].fighter == 0 and sim.events[0].attack_id == sim.fighters[0].attack_id, "typed acceptance " + move)
			check(sim.events[0].event_id > highwater, "monotonic across reset")
			highwater = sim.events[0].event_id
			var swings := 0
			var spawns := 0
			for frame in range(100):
				sim.step(DT,[{},{}])
				for event: Dictionary in sim.events:
					check(event.event_id > highwater, "strict event identity")
					highwater = event.event_id
					if event.type == "swing":
						swings += 1
						var start: float = sim.attack_config(sim.fighters[0],move).startup
						check(sim.fighters[0].clock >= start and sim.fighters[0].clock < start + DT + 0.00001, "swing startup " + move)
						check(event.source == 0 and event.fighter == 0 and event.attack_id == sim.fighters[0].attack_id, "swing identity " + move)
					if event.type == "projectile_spawn": spawns += 1
			check(swings == (0 if move == "special" else 1), "exact swing count " + move)
			check(spawns == (1 if move == "special" else 0), "exact emission count " + move)
		sim.reset(character)
		var jumps := 0
		var lands := 0
		for frame in range(160):
			sim.step(DT,[{"jump":true},{}])
			jumps += count(sim.events,"jump"); lands += count(sim.events,"land")
		check(jumps == 1 and lands == 1,"held normal jump once")
		for airborne in [false,true]:
			for ko in [false,true]:
				sim.reset(character)
				sim.fighters[0].x = -0.35; sim.fighters[1].x = 0.35
				if ko: sim.fighters[1].hp = 13.0
				var catches := 0
				var physical_lands := 0
				var down_seen := false
				for frame in range(200):
					if sim.round_over: sim.step_post_round(DT)
					else: sim.step(DT,[{"kick":true} if frame == 0 else {}, {"jump":true} if airborne and frame == 12 else {}])
					var f: Dictionary = sim.fighters[1]
					for event: Dictionary in sim.events:
						if event.type == "hit": check(event.ko == ko and event.attack_id == 1 and event.source == 0 and event.fighter == 1 and event.has("impact_x") and event.has("impact_y"),"typed actual hit")
						if event.type == "down": down_seen = true
						if event.type == "land" and event.fighter == 1 and event.down:
							physical_lands += 1
							check(count(sim.events,"down_land") == 0,"root ground touch not visual catch")
						if event.type == "down_land":
							catches += 1
							check(f.down_phase == "fall" and f.down_clock >= 0.46 and f.down_clock < 0.46 + DT + 0.00001,"catch occurs at .46 clip seconds")
							check(event.ko == ko,"catch KO preserved")
				check(down_seen and catches == 1 and physical_lands == (1 if airborne else 0),"one catch ground/air/KO")
	interruption_and_provenance_tests()
	print("Feedback event contract checks: ",checks,"; failures: ",failures)
	quit(failures)
