extends RefCounted
## Observes delayed public world state only, never user input.
const HEAVY_REASSESS := 0.24
var reaction := 0.24
var reassess_remaining := 0.0
var remaining := 0.0
var held := 0.0
var snapshots: Array = []
var rng := RandomNumberGenerator.new()
var combo_attack_id := -1
var combo_wanted := false
var combo_sent := false
func _init() -> void:
	rng.seed=607122
func reset() -> void:
	remaining=0.25; held=0.0; reassess_remaining=0.0; snapshots.clear()
	combo_attack_id=-1; combo_wanted=false; combo_sent=false
func act(sim: RefCounted, delta: float) -> Dictionary:
	var enemy:Dictionary=sim.fighters[0]
	var self_f:Dictionary=sim.fighters[1]
	snapshots.append({"age":0.0,"enemy_x":enemy.x,"enemy_y":enemy.y,"enemy_attack":enemy.attack,"x":self_f.x,"face":self_f.face})
	for s in snapshots: s.age+=delta
	while snapshots.size()>1 and snapshots[1].age>=reaction: snapshots.pop_front()
	# Our own public heavy-hit reaction cancels stale chase intent. Reassess
	# for one bounded reaction interval after stun, while snapshots keep aging.
	# No player input, private buffer, future position or extra invulnerability.
	if float(self_f.get("stun",0.0))>0.0 and self_f.get("hit_kind","")=="heavy":
		held=0.0
		reassess_remaining=HEAVY_REASSESS
		remaining=0.0
		combo_attack_id=-1; combo_wanted=false; combo_sent=false
		return {"move":0.0}
	if reassess_remaining>0.0:
		reassess_remaining=maxf(0.0,reassess_remaining-delta)
		held=0.0
		if reassess_remaining>0.0000001: return {"move":0.0}
	var out:Dictionary={"move":held}
	# Planning our own follow-up does not inspect opponent input or future state.
	if self_f.attack=="punch":
		if combo_attack_id!=int(self_f.attack_id):
			combo_attack_id=int(self_f.attack_id); combo_wanted=rng.randf()<0.55; combo_sent=false
		if combo_wanted and not combo_sent and self_f.duration-self_f.clock<=0.10:
			out.punch=true; combo_sent=true
			return out
	remaining-=delta
	if self_f.attack!="": return out
	if remaining>0.0 or snapshots[0].age<reaction: return out
	remaining=rng.randf_range(0.17,0.32)
	var seen:Dictionary=snapshots[0]
	var dist:float=absf(seen.enemy_x-seen.x)
	var face:float=1.0 if seen.enemy_x>seen.x else -1.0
	if seen.enemy_attack!="" and dist<1.2 and self_f.guard>30 and rng.randf()<0.66:
		held=-face
	elif dist>=1.35 and dist<=3.8 and self_f.y<=0.001 and float(self_f.get("special_cooldown",0.0))<=0.0 and rng.randf()<0.20:
		# Public delayed distance plus our own cooldown, never opponent inputs.
		held=0.0
		out.special=true
	elif dist>0.95:
		held=face
		if dist>2.8 and rng.randf()<0.12: out.jump=true
	elif dist<0.76 and rng.randf()<0.30:
		held=-face
	else:
		held=0.0
		var roll:=rng.randf()
		if dist<0.83 and roll<0.38: out.punch=true
		elif dist<0.83 and roll<0.58 and self_f.y<=0.001: out.heavy=true
		elif dist<0.90 and roll<0.73 and self_f.y<=0.001: out.roundhouse=true
		elif roll<0.87: out.kick=true
		elif roll>0.96: out.jump=true
	out.move=held
	return out
