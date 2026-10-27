extends RefCounted
## Observes delayed public world state only, never user input.
const Physics=preload("res://tests/ha_legacy_combat.gd")
const HEAVY_REASSESS := 0.24
# Shared combat uses point projectiles and a ground hurtbox lower edge of .15m.
# Keep a small conservative margin; this is a feasibility gate, not an oracle.
const HURTBOX_LOWER := 0.15
const JUMP_CLEARANCE_MARGIN := 0.03
const MAX_JUMP_CLEAR_HEIGHT := Physics.JUMP_VELOCITY*Physics.JUMP_VELOCITY/(2.0*Physics.GRAVITY)+HURTBOX_LOWER-JUMP_CLEARANCE_MARGIN
var reaction := 0.24
var reassess_remaining := 0.0
var remaining := 0.0
var held := 0.0
var snapshots: Array = []
var rng := RandomNumberGenerator.new()
var observed_face := 0
var last_projectile_id := -1
var intent := "observe"
var combo_attack_id := -1
var combo_wanted := false
var combo_sent := false
func _init() -> void:
	rng.seed=607122
func reset() -> void:
	remaining=0.25; held=0.0; reassess_remaining=0.0; snapshots.clear()
	observed_face=0; last_projectile_id=-1; intent="observe"
	combo_attack_id=-1; combo_wanted=false; combo_sent=false
func act(sim: RefCounted, delta: float) -> Dictionary:
	var enemy:Dictionary=sim.fighters[0]
	var self_f:Dictionary=sim.fighters[1]
	# Only visible, already emitted projectiles enter the delayed history.
	var threat_id := -1
	var threat_distance := 100.0
	var threat_y := 0.0
	var threat_vx := 0.0
	var threat_vy := 0.0
	if "projectiles" in sim and sim.projectiles is Array:
		for p in sim.projectiles:
			var dx:float=self_f.x-p.pos.x
			if p.owner==0 and dx*p.velocity.x>0.0 and absf(dx)<threat_distance and p.pos.y>0.25 and p.pos.y<2.6:
				threat_id=int(p.id); threat_distance=absf(dx)
				threat_y=float(p.pos.y); threat_vx=float(p.velocity.x); threat_vy=float(p.velocity.y)
	snapshots.append({"threat_id":threat_id,"threat_distance":threat_distance,"threat_y":threat_y,"threat_vx":threat_vx,"threat_vy":threat_vy,"age":0.0,"enemy_x":enemy.x,"enemy_y":enemy.y,"enemy_attack":enemy.attack,"x":self_f.x,"face":self_f.face})
	for s in snapshots: s.age+=delta
	while snapshots.size()>1 and snapshots[1].age>=reaction: snapshots.pop_front()
	# Our own public heavy-hit reaction cancels stale chase intent. Reassess
	# for one bounded reaction interval after stun, while snapshots keep aging.
	# No player input, private buffer, future position or extra invulnerability.
	if float(self_f.get("stun",0.0))>0.0 and self_f.get("hit_kind","")=="heavy":
		held=0.0
		intent="heavy_reassess"
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
	if observed_face!=0 and observed_face!=int(face):
		# A mature public side change cancels old chase intent, not our animation.
		observed_face=int(face); held=0.0; remaining=0.12; intent="cross_reassess"
		return {"move":0.0}
	observed_face=int(face)
	if int(seen.threat_id)>0 and int(seen.threat_id)!=last_projectile_id and float(seen.threat_distance)<2.6:
		# One imperfect choice per visible projectile. No future cast/input access.
		last_projectile_id=int(seen.threat_id)
		var response:=rng.randf()
		if self_f.y<=0.001 and response<0.32 and self_f.guard>30:
			held=-face; remaining=0.32; intent="projectile_guard"
			return {"move":held}
		if self_f.y<=0.001 and response<0.55:
			remaining=0.28
			if jump_clearance_feasible(seen):
				held=face; intent="projectile_jump"
				return {"move":held,"jump":true}
			# Do not convert the old jump roll into a guaranteed guard. The same
			# imperfect choice now hesitates instead of attempting impossible clearance.
			held=0.0; intent="projectile_hesitate"
			return {"move":0.0}
	intent="neutral"
	if seen.enemy_attack!="" and dist<1.2 and self_f.guard>30 and rng.randf()<0.66:
		held=-face
	elif dist>=1.35 and dist<=3.8 and self_f.y<=0.001 and float(self_f.get("special_cooldown",0.0))<=0.0 and rng.randf()<0.20:
		# Public delayed distance plus our own cooldown, never opponent inputs.
		held=0.0
		out.special=true
	elif dist>0.95:
		# Mid-range is a decision space, not an unconditional chase command.
		var approach_roll:=rng.randf()
		if dist<1.75 and approach_roll<0.22:
			held=-face; intent="space_retreat"
		elif dist<1.75 and approach_roll<0.42:
			held=0.0; intent="space_wait"
		else:
			held=face; intent="approach"
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

func jump_clearance_feasible(seen: Dictionary) -> bool:
	# Public delayed trajectory only. A descending heart may enter the reachable
	# envelope by the estimated near-edge crossing; target movement and old data
	# still make this fallible. Never query unobserved live projectile state.
	var speed:float=absf(float(seen.get("threat_vx",0.0)))
	if speed<0.00001: return false
	var travel:float=maxf(0.0,float(seen.get("threat_distance",0.0))-Physics.HURT_X)/speed
	var height:float=float(seen.get("threat_y",0.0))+float(seen.get("threat_vy",0.0))*travel
	return height>=HURTBOX_LOWER and height<=MAX_JUMP_CLEAR_HEIGHT
