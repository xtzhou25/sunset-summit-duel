extends RefCounted
const Characters = preload("res://tests/tao_legacy_characters.gd")
## Pure deterministic 60 Hz combat. No renderer/input or animation-driven damage.
const LEFT := -2.1
const RIGHT := 2.1
const BODY := 0.35
const HURT_X := 0.26
const GRAVITY := 17.5
const SPEED := 2.4
## Normal locomotion only. Signature casts and committed attack velocities keep
## their authored trajectories; retreat remains slower than forward movement.
const RETREAT_SPEED := 1.45
const JUMP_VELOCITY := 6.5
const AIR_ACCELERATION := 12.0
const AIR_PASS_HEIGHT := 0.55
const CROUCH_TRANSITION := 0.18
## A fresh second jab press may queue only the matching rear straight.
const PUNCH_BUFFER_WINDOW := 0.12
## Heavy, roundhouse and signature casts are ground-only. Air jabs remain supported.
const GROUND_ONLY_ATTACKS := ["heavy", "roundhouse", "special"]
const STATIONARY_ATTACKS := ["punch", "straight", "heavy", "roundhouse", "special"]
## Fixed simulation timing; the optional emitter callback supplies position only.
const SPECIAL_COOLDOWN := 4.0
const MEOW_DURATION := 1.0
const MEOW_EMIT := 0.38
const HEART_START := 0.20
const HEART_AIR := 0.60
const HEART_LAND := 0.25
const HEART_EMIT := 0.48
const HEART_JUMP_VELOCITY := 5.25
const PROJECTILE_SPEED := 3.6
const PROJECTILE_RANGE := 4.5
const PROJECTILE_LIFETIME := 1.25
const HEART_MIN_AIM_DISTANCE := 1.2
const PROJECTILE_CONFIG := {"damage":12.0,"guard":28.0,"stun":0.26,"push":0.24}
## Actual imported 59-clip GLB right-foot skin at game scale 1.2. R/L bounds
## are exactly identical in the source report, so both facings share one curve.
## Rows at .28 + n*.01 seconds: depth min/max, height min/max, forward min/max.
## Source: docs/ROUNDHOUSE-ACTIVE-SURFACE-CURVES.json (no padding included).
const ROUNDHOUSE_PEAK := 0.35
const ROUNDHOUSE_REACH_PROVISIONAL := false
const ROUNDHOUSE_SURFACE_STEP := 0.01
const ROUNDHOUSE_FORWARD_ALLOWANCE := 0.04
const ROUNDHOUSE_VERTICAL_ALLOWANCE := 0.06
const ROUNDHOUSE_DEPTH_HALF := 0.25
const ROUNDHOUSE_SURFACE_CURVES := {
	0: [
		[-0.8796407175064088,-0.6894409418106079,0.8446265172958375,1.047157030105591,0.493953495025635,0.7006715440750124],
		[-0.851524386405945,-0.6662685728073122,0.863855538368225,1.063266592025757,0.6121997594833369,0.8253503179550167],
		[-0.7664946556091309,-0.5937206625938415,0.8794247388839721,1.0757411241531372,0.7288327932357788,0.9536004066467285],
		[-0.6318183088302615,-0.478446092605591,0.8925030326843262,1.086049919128418,0.8418491935729979,1.0795271873474122],
		[-0.4841671800613401,-0.3476577186584471,0.9033422756195069,1.0948991775512695,0.9429758834838868,1.1903383827209473],
		[-0.33833397388458214,-0.21471717238426177,0.9116381120681762,1.1019337320327758,1.0247839450836183,1.2794034290313723],
		[-0.21019244670867893,-0.09174738407134982,0.9170877313613892,1.1065160322189331,1.0817607021331788,1.3394498348236084],
		[-0.11281161904335021,0.004805704951286315,0.9193906545639038,1.1084436178207397,1.1072502136230469,1.365449810028076],
		[-0.03870397567749032,0.07923015832900994,0.917829122543335,1.1068811559677123,1.094315414428711,1.3523322200775147],
		[0.03804438829422005,0.15806405425071726,0.9141509914398193,1.1032054567337035,1.06554762840271,1.3222986888885495],
		[0.11085502266883841,0.23742761492729175,0.9085751295089721,1.0976353454589842,1.0247044515609742,1.2780095386505128],
		[0.1754845583438874,0.3119956004619599,0.9013237810134888,1.0903871726989744,0.9753033971786498,1.2226884555816648],
		[0.22841802835464475,0.3763527274131775,0.8926287174224853,1.0816754579544068,0.9195230484008788,1.1618542671203613],
		[0.2598989653587341,0.4149149966239929,0.8823527383804323,1.071410894393921,0.8632755088806153,1.1012659549713137],
		[0.2703731632232666,0.42844118356704713,0.8698388814926147,1.0591269493103026,0.809941749572754,1.0457826519012452],
	],
	1: [
		[-0.8763877344131471,-0.6852116918563843,0.8402888488769532,1.049556155204773,0.4872935199737551,0.6971189689636234],
		[-0.8480915021896364,-0.6628079080581667,0.8596947097778319,1.0658510828018188,0.6056338834762569,0.8210593700408931],
		[-0.7629375457763672,-0.5897463083267211,0.8754351139068604,1.0788076400756836,0.7223314762115478,0.9492418527603149],
		[-0.6296382236480714,-0.47506721735000623,0.8886664867401123,1.0895075798034668,0.8352838468551635,1.0753626680374144],
		[-0.4817890262603758,-0.34660801649093614,0.8996367931365966,1.0982603073120116,0.9353166246414185,1.186053900718689],
		[-0.3366638803482052,-0.21453658103942844,0.9080360984802246,1.104882102012634,1.0163033723831179,1.2746150779724121],
		[-0.20886224269866915,-0.0926407599449155,0.9135557556152343,1.1091894578933714,1.0730721616744996,1.3345996284484865],
		[-0.11161109805107117,0.0036057472229003903,0.9158888339996337,1.1109970092773438,1.098497700691223,1.3605880737304688],
		[-0.03771460890769967,0.07795059800148002,0.9143271732330323,1.1094343757629395,1.0855696105957031,1.3474739742279054],
		[0.03849659085273751,0.1566308498382569,0.910648956298828,1.105758819580078,1.0568452262878416,1.3174644756317138],
		[0.110232206583023,0.2356033444404601,0.9050728797912597,1.1001888799667359,1.0161190366744994,1.2732402992248535],
		[0.17446649193763739,0.3098599648475648,0.8978213024139404,1.0929408502578735,0.9670187044143675,1.218596076965332],
		[0.22613507509231567,0.37353365421295165,0.8891268968582153,1.0842289924621582,0.912799072265625,1.1577655792236328],
		[0.2561609244346618,0.41278527259826653,0.8788504600524902,1.0739646863937378,0.8564278793334962,1.0970685195922851],
		[0.2660811924934387,0.42642758846282963,0.8663186931610106,1.0617522382736204,0.8030718040466309,1.041544017791748],
	],
}
## Actual imported 57-clip GLB skinned hand reach, game scale 1.2.
## 10 ms samples conservatively take min(R, L). Both world facings share them.
## Source: animation/output/v5/CONSERVATIVE-ACTIVE-REACH-CURVES.json.
const PUNCH_REACH_STEP := 0.01
const PUNCH_REACH_ALLOWANCE := 0.04
const PUNCH_REACH_CURVES := {
	0: {
		"punch": [0.3835909795761109,0.421529746055603,0.4545432043075562,0.48099573612213137,0.49880152702331537,0.506412935256958,0.5040380716323852,0.49617722511291507,0.48930221557617193,0.4810983037948608,0.4634301710128784],
		"straight": [0.4009516525268555,0.4477699184417724,0.49063131809234617,0.5232050371170044,0.5446120119094849,0.5535859107971192,0.552456579208374,0.5463030338287354,0.538798041343689,0.5327125310897827,0.5241165018081665],
		"heavy": [0.34018012046813983,0.4070424556732178,0.4656931972503661,0.5154908466339111,0.5544423580169677,0.5805309963226318,0.591771125793457,0.5899574947357177,0.5860758876800537,0.5809660005569458,0.5754443693161011,0.570265245437622,0.5669331121444702],
	},
	1: {
		"punch": [0.42926260471344,0.4658633708953857,0.497208709716797,0.5220600986480713,0.5386737871170044,0.5457331323623658,0.5435163974761963,0.536191635131836,0.5297467517852783,0.5220313024520874,0.505417685508728],
		"straight": [0.44659908771514895,0.4920880651473998,0.5332800149917603,0.5642739200592041,0.5844836997985839,0.5929101276397705,0.5918587303161621,0.5861055850982666,0.5790057706832886,0.5732231283187865,0.5650381851196289],
		"heavy": [0.3852092170715333,0.4509137392044067,0.5083237266540527,0.5568915939331055,0.5947644281387329,0.6200953245162963,0.6309730768203735,0.6292413568496704,0.6256174707412719,0.6208026266098022,0.615559458732605,0.6106472253799439,0.6074573993682861],
	},
}
## These seconds are shared with the visual Knockdown/Recover phase contract.
## Airborne loss may pose up to AIR_LOSS_END, but never starts floor contact early.
const DOWN_AIR_LOSS_END := 0.20
## Presentation-only catch marker in the authored ground fall clip.
const DOWN_CATCH_TIME := 0.46
const DOWN_FALL_DURATION := 0.80
const DOWN_HOLD_DURATION := 0.25
const DOWN_RISE_DURATION := 1.00
const DOWN_RECOVERY_INVULN := 0.35
var fighters: Array = []
var time_left := 60.0
var round_over := false
var winner := -2
var events: Array = []
## Lifetime event identity survives round/menu resets so feedback cannot replay.
var event_serial := 0
var elapsed := 0.0
var attack_serial := 0
var projectile_serial := 0
var projectiles: Array = []
## Callable(fighter_index, exact_cast_age) -> Vector2 world XY. Never sets timing,
## damage or collision shape. Render code may sample its measured mouth/head pose.
var emitter_provider: Callable

func _init() -> void:
	reset(0)

func fresh(kind: int, x: float, face: int) -> Dictionary:
	return {"kind":kind,"x":x,"y":0.0,"vy":0.0,"vx":0.0,"face":face,"hp":100.0,"guard":100.0,"guard_delay":0.0,"state":"idle","clock":0.0,"duration":0.0,"attack":"","attack_id":0,"hit":false,"swing_emitted":false,"stun":0.0,"hit_age":0.0,"stun_duration":0.0,"hit_kind":"","invuln":0.0,"chain":0,"chain_window":0.0,"blocking":false,"move":0.0,"queued":"","queued_attack_id":0,"jump_held":false,"crouching":false,"crouch_amount":0.0,"punch_held":false,"heavy_held":false,"roundhouse_held":false,"special_held":false,"special_cooldown":0.0,"special_phase":"","special_phase_clock":0.0,"special_emitted":false,"special_pending_emit":false,"special_emit_age":0.0,"special_face":face,"special_step_remaining":0.0,"land_lock":0.0,"down":false,"down_phase":"","down_clock":0.0,"down_age":0.0,"down_ko":false,"down_land_emitted":false,"input_rearm":false}

func reset(player_kind: int, opponent_kind: int = -1) -> void:
	player_kind=Characters.valid_kind(player_kind)
	opponent_kind=Characters.opponent_for(player_kind,opponent_kind)
	fighters = [fresh(player_kind,-1.3,1), fresh(opponent_kind,1.3,-1)]
	time_left=60.0
	round_over=false
	winner=-2
	elapsed=0.0
	attack_serial=0
	projectile_serial=0
	projectiles.clear()
	events.clear()

func _emit_event(event: Dictionary) -> void:
	event_serial+=1
	event.event_id=event_serial
	events.append(event)

func _clear_attack_buffer(f: Dictionary) -> void:
	f.queued=""
	f.queued_attack_id=0

func cancel_pending_inputs() -> void:
	# Pause/background/menu callers clear their own held keys and one-frame taps
	# first. The very first fresh resume press must remain immediately usable.
	for f: Dictionary in fighters:
		_clear_attack_buffer(f)
		f.punch_held=false
		f.jump_held=false
		f.heavy_held=false
		f.roundhouse_held=false
		f.special_held=false

func attack_config(f: Dictionary, kind: String) -> Dictionary:
	var profile:int=Characters.get_character(int(f.kind)).combat_profile
	if kind == "punch":
		return {"startup":0.14,"active":0.10,"recovery":0.24 if profile==0 else 0.28,"reach":0.55 if profile==0 else 0.59,"damage":8.0,"guard":22.0,"stun":0.24,"push":0.22,"low":0.66,"high":1.80}
	if kind == "straight":
		return {"startup":0.18,"active":0.10,"recovery":0.28 if profile==0 else 0.32,"reach":0.60 if profile==0 else 0.64,"damage":10.0,"guard":26.0,"stun":0.26,"push":0.27,"low":0.66,"high":1.80}
	if kind == "heavy":
		return {"startup":0.34,"active":0.12,"recovery":0.42 if profile==0 else 0.48,"reach":0.63 if profile==0 else 0.67,"damage":16.0,"guard":38.0,"stun":0.30,"push":0.52,"low":0.66,"high":1.80}
	if kind == "roundhouse":
		# Config stores the overall measured envelope; actual contacts use each
		# interpolated foot sample's depth/height below, never this whole envelope.
		var config:Dictionary={"startup":0.28,"active":0.14,"recovery":0.48 if profile==0 else 0.54,"reach":1.40,"damage":13.0,"guard":30.0,"stun":0.28,"push":0.30,"low":0.7846265172958375 if profile==0 else 0.7802888488769532,"high":1.1684436178207398 if profile==0 else 1.1709970092773438}
		if int(f.kind)==2:
			config.low=INF; config.high=-INF
			for bounds:Array in Characters.QI_ROUNDHOUSE_SURFACE_CURVES:
				config.low=minf(config.low,bounds[2]-ROUNDHOUSE_VERTICAL_ALLOWANCE)
				config.high=maxf(config.high,bounds[3]+ROUNDHOUSE_VERTICAL_ALLOWANCE)
		return config
	return {"startup":0.36,"active":0.13,"recovery":0.40 if profile==0 else 0.46,"reach":0.73 if profile==0 else 0.78,"damage":13.0,"guard":34.0,"stun":0.32,"push":0.42,"low":0.36,"high":1.65}

func effective_reach(f: Dictionary, kind: String, attack_time: float = -1.0) -> float:
	# Public contact/debug contract: absolute attack seconds, not normalized
	# animation time. Endpoint samples clamp; callers still gate active phase.
	# Returned metres exclude HURT_X. Kick retains its original static reach.
	# Roundhouse shares its measured forward surface with full XYZ contact QA.
	if kind=="roundhouse": return _roundhouse_geometry(f,attack_time).reach
	var config:=attack_config(f,kind)
	var curves:Dictionary=Characters.QI_PUNCH_REACH_CURVES if int(f.kind)==2 else PUNCH_REACH_CURVES[f.kind]
	if not curves.has(kind): return config.reach
	var samples: Array=curves[kind]
	var sample_time:float=f.clock if attack_time<0.0 else attack_time
	var position:float=clampf((sample_time-config.startup)/PUNCH_REACH_STEP,0.0,float(samples.size()-1))
	var lower:int=floori(position)
	var upper:int=mini(lower+1,samples.size()-1)
	var measured:float=lerpf(samples[lower],samples[upper],position-float(lower))
	return minf(config.reach,measured+PUNCH_REACH_ALLOWANCE)

func _roundhouse_surface_bounds(f: Dictionary, attack_time: float = -1.0) -> Array:
	# Sample all six bounds together at absolute attack seconds. Interpolating
	# endpoints is deterministic and independent of AnimationPlayer playback.
	var samples: Array=Characters.QI_ROUNDHOUSE_SURFACE_CURVES if int(f.kind)==2 else ROUNDHOUSE_SURFACE_CURVES[f.kind]
	var sample_time:float=f.clock if attack_time<0.0 else attack_time
	if sample_time<=0.28: return samples.front().duplicate()
	if sample_time>=0.42: return samples.back().duplicate()
	var position:float=clampf((sample_time-0.28)/ROUNDHOUSE_SURFACE_STEP,0.0,float(samples.size()-1))
	var lower:int=floori(position)
	var upper:int=mini(lower+1,samples.size()-1)
	var bounds:Array=[]
	for axis in range(6):
		bounds.append(lerpf(samples[lower][axis],samples[upper][axis],position-float(lower)))
	return bounds

func _roundhouse_geometry(f: Dictionary, attack_time: float = -1.0) -> Dictionary:
	var bounds:=_roundhouse_surface_bounds(f,attack_time)
	return {"reach":minf(attack_config(f,"roundhouse").reach,bounds[5]+ROUNDHOUSE_FORWARD_ALLOWANCE),"low":bounds[2]-ROUNDHOUSE_VERTICAL_ALLOWANCE,"high":bounds[3]+ROUNDHOUSE_VERTICAL_ALLOWANCE,"depth_overlap":bounds[0]<=ROUNDHOUSE_DEPTH_HALF and bounds[1]>=-ROUNDHOUSE_DEPTH_HALF}

func contact_geometry(f: Dictionary, kind: String, attack_time: float = -1.0) -> Dictionary:
	# Simulation-owned contact/debug contract, in game metres relative to the
	# attacking root. Excludes target HURT_X / height, which the collector adds.
	if kind=="roundhouse": return _roundhouse_geometry(f,attack_time)
	var config:=attack_config(f,kind)
	return {"reach":effective_reach(f,kind,attack_time),"low":config.low,"high":config.high,"depth_overlap":true}

func begin_attack(f: Dictionary, kind: String) -> void:
	if round_over or f.hp<=0.0 or f.down or f.input_rearm: return
	if kind=="special":
		begin_special(f)
		return
	if kind in GROUND_ONLY_ATTACKS and (f.y>0.001 or f.vy>0.0): return
	_clear_attack_buffer(f)
	attack_serial+=1
	f.attack_id=attack_serial
	f.attack=kind
	f.state=kind
	f.clock=0.0
	var c:=attack_config(f,kind)
	f.duration=c.startup+c.active+c.recovery
	f.hit=false
	f.swing_emitted=false
	f.chain+=1
	f.chain_window=0.0
	f.blocking=false
	f.crouching=false
	f.crouch_amount=0.0
	if kind=="kick" and f.y<=0.001:
		f.vy=4.6
		f.vx=f.face*1.9
	elif kind=="kick":
		f.vx=f.face*2.1
	else:
		f.vx=0.0
	var index:int=fighters.find(f)
	_emit_event({"type":"attack","kind":kind,"source":index,"fighter":index,"attack_id":f.attack_id})

func begin_special(f: Dictionary) -> void:
	# Rejected airborne, busy, cooldown or held commands never enter a buffer.
	if round_over or f.hp<=0.0 or f.down or f.input_rearm or f.stun>0.0 or f.attack!="" or f.land_lock>0.0: return
	if f.y>0.001 or f.vy>0.0 or f.special_cooldown>0.0: return
	_clear_attack_buffer(f)
	attack_serial+=1
	f.attack_id=attack_serial
	f.attack="special"; f.state="special"; f.clock=0.0
	var character:Dictionary=Characters.get_character(int(f.kind))
	f.duration=float(character.special_duration)
	f.special_cooldown=SPECIAL_COOLDOWN
	f.special_phase="start" if character.special_airborne else "cast"
	f.special_phase_clock=0.0
	f.special_emitted=false; f.special_pending_emit=false
	f.special_emit_age=float(character.special_emit)
	f.special_face=f.face
	f.special_step_remaining=0.0
	f.hit=false; f.chain=0; f.chain_window=0.0
	f.blocking=false; f.crouching=false; f.crouch_amount=0.0; f.move=0.0; f.vx=0.0
	var index:int=fighters.find(f)
	_emit_event({"type":"attack","kind":"special","source":index,"fighter":index,"attack_id":f.attack_id})

func _clear_special(f: Dictionary) -> void:
	# Cooldown intentionally survives interruption and completion.
	f.special_phase=""; f.special_phase_clock=0.0
	f.special_pending_emit=false

func special_root_height(kind: int, cast_age: float) -> float:
	if not Characters.get_character(kind).special_airborne: return 0.0
	var air_age:float=clampf(cast_age-HEART_START,0.0,HEART_AIR)
	return maxf(0.0,HEART_JUMP_VELOCITY*air_age-GRAVITY*air_age*air_age*0.5)

func _advance_special(f: Dictionary, index: int) -> void:
	if not f.special_emitted and f.clock+0.0000001>=f.special_emit_age:
		f.special_emitted=true; f.special_pending_emit=true
		# A newly emitted projectile advances only the portion after its exact
		# emission, not a whole tick. Large steps still emit exactly once.
		f.special_step_remaining=maxf(0.0,f.clock-f.special_emit_age)
	if not Characters.get_character(int(f.kind)).special_airborne:
		f.special_phase="cast"; f.special_phase_clock=f.clock
		return
	var previous_phase:String=f.special_phase
	if f.clock+0.0000001<HEART_START:
		f.special_phase="start"; f.special_phase_clock=f.clock
		f.y=0.0; f.vy=0.0
	elif f.clock+0.0000001<HEART_START+HEART_AIR:
		f.special_phase="air"; f.special_phase_clock=maxf(0.0,f.clock-HEART_START)
		# Exact special-only parabola, with the same gravity as normal jumps.
		# Interruption preserves these y/vy values for existing airborne physics.
		f.y=special_root_height(1,f.clock)
		f.vy=HEART_JUMP_VELOCITY-GRAVITY*f.special_phase_clock
	else:
		f.special_phase="land"; f.special_phase_clock=maxf(0.0,f.clock-HEART_START-HEART_AIR)
		f.y=0.0; f.vy=0.0
		if previous_phase!="land": _emit_event({"type":"land","fighter":index,"down":false})

func _emit_projectile(index: int) -> void:
	var f:Dictionary=fighters[index]
	f.special_pending_emit=false
	var cast_age:float=f.special_emit_age
	var character:Dictionary=Characters.get_character(int(f.kind))
	var muzzle_forward:float=character.fallback_forward
	var muzzle_height:float=character.fallback_height
	var origin:=Vector2(f.x+f.special_face*muzzle_forward,special_root_height(f.kind,cast_age)+muzzle_height)
	if emitter_provider.is_valid():
		var measured:Variant=emitter_provider.call(index,cast_age)
		if measured is Vector2 and measured.is_finite(): origin=measured
	var velocity:=Vector2(f.special_face*PROJECTILE_SPEED,0.0)
	var target:Dictionary=fighters[1-index]
	var target_snapshot:=Vector2(target.x,target.y+1.2)
	if character.special_airborne:
		# Snapshot at emission, never homing. Short-range overshoot is genuine:
		# do not enlarge either fighter's existing hurtbox to guarantee a hit.
		var aim_distance:float=maxf(HEART_MIN_AIM_DISTANCE,(target_snapshot.x-origin.x)*f.special_face)
		velocity.y=minf(0.0,(target_snapshot.y-origin.y)/aim_distance*PROJECTILE_SPEED)
	projectile_serial+=1
	var kind:String=character.special_kind
	projectiles.append({"id":projectile_serial,"owner":index,"attack_id":f.attack_id,"kind":kind,"pos":origin,"previous_pos":origin,"velocity":velocity,"face":f.special_face,"age":0.0,"distance":0.0,"target_snapshot":target_snapshot,"step_remaining":f.special_step_remaining})
	_emit_event({"type":"projectile_spawn","source":index,"fighter":index,"attack_id":f.attack_id,"kind":kind,"id":projectile_serial,"pos":origin})

func _segment_box_fraction(start: Vector2, finish: Vector2, minimum: Vector2, maximum: Vector2) -> float:
	# Slab intersection of a swept POINT with the unchanged fighter AABB.
	# Visual wave width never adds an invisible gameplay radius/hurtbox padding.
	var movement:=finish-start
	var near_t:=0.0
	var far_t:=1.0
	for axis in range(2):
		if absf(movement[axis])<0.00000001:
			if start[axis]<minimum[axis] or start[axis]>maximum[axis]: return -1.0
			continue
		var first:float=(minimum[axis]-start[axis])/movement[axis]
		var second:float=(maximum[axis]-start[axis])/movement[axis]
		near_t=maxf(near_t,minf(first,second))
		far_t=minf(far_t,maxf(first,second))
		if near_t>far_t: return -1.0
	return near_t

func _collect_projectile_contacts(delta: float, contacts: Array) -> void:
	var remaining:Array=[]
	for p:Dictionary in projectiles:
		var step_time:float=float(p.get("step_remaining",delta))
		p.erase("step_remaining")
		var origin:Vector2=p.pos
		var velocity:Vector2=p.velocity
		var travel_time:float=maxf(0.0,minf(step_time,minf(PROJECTILE_LIFETIME-p.age,(PROJECTILE_RANGE-p.distance)/maxf(absf(velocity.x),0.000001))))
		var outside_arena:bool=origin.x<LEFT or origin.x>RIGHT or origin.y<0.0
		var already_expired:bool=p.age>=PROJECTILE_LIFETIME or p.distance>=PROJECTILE_RANGE
		var boundary_time:float=INF
		if outside_arena: boundary_time=0.0
		elif velocity.x>0.0: boundary_time=(RIGHT-origin.x)/velocity.x
		elif velocity.x<0.0: boundary_time=(LEFT-origin.x)/velocity.x
		if velocity.y<0.0: boundary_time=minf(boundary_time,origin.y/-velocity.y)
		travel_time=minf(travel_time,maxf(0.0,boundary_time))
		var finish:Vector2=origin+velocity*travel_time
		p.previous_pos=origin; p.pos=finish
		p.age+=travel_time; p.distance+=absf(velocity.x)*travel_time
		var opponent:Dictionary=fighters[1-int(p.owner)]
		# Down/invulnerable targets are intangible: pass through, do not consume.
		# No owner or projectile-projectile collision is ever queried.
		var hit_fraction:float=-1.0
		if not outside_arena and not already_expired and not opponent.down and opponent.invuln<=0.0:
			hit_fraction=_segment_box_fraction(origin,finish,Vector2(opponent.x-HURT_X,opponent.y+0.15),Vector2(opponent.x+HURT_X,opponent.y+1.92))
		if hit_fraction>=0.0:
			var impact:Vector2=origin.lerp(finish,hit_fraction)
			contacts.append({"source":int(p.owner),"attack_id":int(p.get("attack_id",0)),"config":PROJECTILE_CONFIG,"kind":p.kind,"impact_x":impact.x,"impact_y":impact.y,"projectile_id":p.id,"face":p.face,"frontal":-float(p.face)*opponent.face>0.0})
			_emit_event({"type":"projectile_despawn","id":p.id,"reason":"contact","pos":impact})
		elif travel_time+0.0000001>=boundary_time or p.age+0.0000001>=PROJECTILE_LIFETIME or p.distance+0.0000001>=PROJECTILE_RANGE:
			var reason:String="boundary" if travel_time+0.0000001>=boundary_time else ("range" if p.distance+0.0000001>=PROJECTILE_RANGE else "lifetime")
			_emit_event({"type":"projectile_despawn","id":p.id,"reason":reason,"pos":finish})
		else:
			remaining.append(p)
	projectiles=remaining

func _enter_down(f: Dictionary, index: int, kind: String) -> void:
	f.down=true
	f.down_ko=f.hp<=0.0
	f.down_phase="air" if f.y>0.001 or f.vy>0.0 else "fall"
	f.down_clock=0.0
	f.down_age=0.0
	f.down_land_emitted=false
	f.state="down"
	f.crouching=false
	f.crouch_amount=0.0
	f.clock=0.0
	f.stun=0.0
	f.attack=""
	_clear_special(f)
	f.duration=0.0
	f.chain=0
	f.chain_window=0.0
	_clear_attack_buffer(f)
	f.blocking=false
	f.move=0.0
	# Down samples consume actions rather than queue them. Neutral samples during
	# down/rise may re-arm the next fresh input, but a held wake-up action may not.
	f.input_rearm=true
	if f.down_phase=="fall": f.y=0.0; f.vy=0.0
	_emit_event({"type":"down","fighter":index,"kind":kind,"ko":f.down_ko,"phase":f.down_phase})

func _move_and_land(f: Dictionary, index: int, delta: float) -> bool:
	f.x=clampf(f.x+f.vx*delta,LEFT,RIGHT)
	if f.y>0.0 or f.vy>0.0:
		f.vy-=GRAVITY*delta
		f.y+=f.vy*delta
		if f.y<=0.0:
			f.y=0.0
			f.vy=0.0
			f.land_lock=maxf(f.land_lock,0.09)
			_emit_event({"type":"land","fighter":index,"down":f.down})
			return true
	return false

func _step_down(f: Dictionary, index: int, delta: float) -> void:
	f.down_age+=delta
	f.down_clock+=delta
	f.blocking=false
	f.move=0.0
	_clear_attack_buffer(f)
	f.vx=move_toward(f.vx,0.0,delta*8.0)
	var landed:=_move_and_land(f,index,delta)
	if f.down_phase=="air":
		if landed:
			f.down_phase="fall"
			f.down_clock=DOWN_AIR_LOSS_END
		return
	# Root height is physical ground height, never animation hip height.
	f.y=0.0
	f.vy=0.0
	# Physical root landing starts the fall at .20, not the visual catch.
	# The same marker runs in post-round settling and fires once even on KO.
	if f.down_phase=="fall" and not f.down_land_emitted and f.down_clock>=DOWN_CATCH_TIME:
		f.down_land_emitted=true
		_emit_event({"type":"down_land","fighter":index,"kind":f.hit_kind,"ko":f.down_ko})
	if f.down_phase=="fall" and f.down_clock>=DOWN_FALL_DURATION:
		f.down_clock-=DOWN_FALL_DURATION
		f.down_phase="hold"
	if f.down_phase=="hold" and not f.down_ko and f.down_clock>=DOWN_HOLD_DURATION:
		f.down_clock-=DOWN_HOLD_DURATION
		f.down_phase="rise"
		f.state="recover"
		f.vx=0.0
		_emit_event({"type":"rise","fighter":index})
	if f.down_phase=="rise" and not f.down_ko and f.down_clock>=DOWN_RISE_DURATION:
		f.down=false
		f.down_phase=""
		f.down_clock=0.0
		f.down_age=0.0
		f.down_ko=false
		f.state="idle"
		f.clock=0.0
		f.vx=0.0
		f.stun=0.0
		f.land_lock=0.0
		f.invuln=maxf(f.invuln,DOWN_RECOVERY_INVULN)
		_emit_event({"type":"recovered","fighter":index})

func _resolve_pushboxes(post_round: bool = false, airborne_before: Array = []) -> void:
	# Pushboxes remain physical while down; deliberate aerial passes still work.
	var a:Dictionary=fighters[0]; var b:Dictionary=fighters[1]
	# Taper the lateral body footprint continuously with vertical separation.
	# Restoring a full .70 m box abruptly at .55 m used to pop a descending
	# fighter back to its takeoff side. This bevel permits natural cross-ups
	# and settles to the unchanged full ground spacing without teleporting.
	var height_gap:float=absf(a.y-b.y)
	if height_gap>=AIR_PASS_HEIGHT: return
	var minimum_gap:float=BODY*2.0
	# Keep authored kick/special/down physical contracts intact. The bevel is
	# only for a deliberate free jump (including its existing aerial jab).
	var free_air_a:bool=a.y>0.001 and a.attack in ["","punch","straight"]
	var free_air_b:bool=b.y>0.001 and b.attack in ["","punch","straight"]
	if not a.down and not b.down and (free_air_a or free_air_b):
		minimum_gap*=clampf(1.0-height_gap/AIR_PASS_HEIGHT,0.0,1.0)
	if absf(a.x-b.x)>=minimum_gap: return
	var dir:float=1.0 if b.x>=a.x else -1.0
	var overlap:float=minimum_gap-absf(a.x-b.x)
	if post_round:
		var a_settling:bool=a.down or (airborne_before.size()==2 and airborne_before[0])
		var b_settling:bool=b.down or (airborne_before.size()==2 and airborne_before[1])
		if not a_settling and not b_settling: return
		if not a_settling or not b_settling:
			# Standing fighters freeze; already-down or landing bodies still separate.
			var moving:Dictionary=a if a_settling else b
			var fixed:Dictionary=b if a_settling else a
			var moving_dir:float=-dir if a_settling else dir
			var target:float=fixed.x+moving_dir*minimum_gap
			if target<LEFT or target>RIGHT: target=fixed.x-moving_dir*minimum_gap
			moving.x=clampf(target,LEFT,RIGHT)
			return
	a.x=clampf(a.x-dir*overlap*0.5,LEFT,RIGHT)
	b.x=clampf(b.x+dir*overlap*0.5,LEFT,RIGHT)
	if absf(a.x-b.x)<minimum_gap:
		if a.x==LEFT or a.x==RIGHT: b.x=clampf(a.x+dir*minimum_gap,LEFT,RIGHT)
		else: a.x=clampf(b.x-dir*minimum_gap,LEFT,RIGHT)

func step_post_round(delta: float) -> void:
	events.clear()
	if not round_over: return
	projectiles.clear()
	var airborne_before:Array=[]
	for i in range(2):
		var f:Dictionary=fighters[i]
		airborne_before.append(f.y>0.0 or f.vy>0.0)
		# Preserve the existing short landing settle for result animation, then
		# release it even after physical motion has stopped at the floor.
		if not f.down: f.land_lock=maxf(0.0,f.land_lock-delta)
		# A timeout can leave a living winner down. Finish only its already-started
		# visual sequence too; no timers, regeneration, input, contacts, or new KO.
		if f.down:
			f.hit_age+=delta
			f.clock+=delta
			_step_down(f,i,delta)
		elif f.y>0.0 or f.vy>0.0:
			# A winning kick or timeout jump must finish its existing flight. This
			# changes physical settling only, never attack clock/state or contacts.
			f.vx=move_toward(f.vx,0.0,delta*8.0)
			if _move_and_land(f,i,delta): f.vx=0.0
	_resolve_pushboxes(true,airborne_before)

func step(delta: float, commands: Array) -> void:
	events.clear()
	if round_over:
		projectiles.clear()
		return
	elapsed+=delta
	time_left=maxf(0.0,time_left-delta)
	for i in range(2):
		var f:Dictionary=fighters[i]
		var opponent:Dictionary=fighters[1-i]
		var cmd:Dictionary=commands[i]
		var punch_down:bool=bool(cmd.get("punch",false))
		var heavy_down:bool=bool(cmd.get("heavy",false))
		var roundhouse_down:bool=bool(cmd.get("roundhouse",false))
		var special_down:bool=bool(cmd.get("special",false))
		var jump_down:bool=bool(cmd.get("jump",false))
		var jump_pressed:bool=jump_down and not f.jump_held
		var punch_pressed:bool=punch_down and not f.punch_held
		var heavy_pressed:bool=heavy_down and not f.heavy_held
		var roundhouse_pressed:bool=roundhouse_down and not f.roundhouse_held
		var special_pressed:bool=special_down and not f.special_held
		f.jump_held=jump_down
		f.punch_held=punch_down
		f.heavy_held=heavy_down
		f.roundhouse_held=roundhouse_down
		f.special_held=special_down
		var action_down:bool=punch_down or heavy_down or roundhouse_down or special_down or bool(cmd.get("kick",false)) or jump_down
		f.hit_age+=delta
		f.special_cooldown=maxf(0.0,f.special_cooldown-delta)
		if f.special_cooldown<0.0000001: f.special_cooldown=0.0
		f.stun=maxf(0.0,f.stun-delta)
		f.invuln=maxf(0.0,f.invuln-delta)
		f.land_lock=maxf(0.0,f.land_lock-delta)
		f.guard_delay=maxf(0.0,f.guard_delay-delta)
		f.chain_window=maxf(0.0,f.chain_window-delta)
		f.move=clampf(float(cmd.get("move",0.0)),-1,1)
		f.clock+=delta
		if f.down:
			f.input_rearm=action_down
			_step_down(f,i,delta)
			continue
		if f.input_rearm and not action_down:
			f.input_rearm=false
		# The queue belongs to exactly this first jab and lives only until its
		# completion, at most 120 ms (plus fixed-step quantization) after input.
		# Early/held/third presses are consumed, never carried into another move.
		if punch_pressed and f.attack=="punch" and f.chain==1 and f.stun<=0.0 and not f.input_rearm and f.clock>=f.duration-PUNCH_BUFFER_WINDOW and f.clock<f.duration:
			f.queued="straight"
			f.queued_attack_id=f.attack_id
		if f.attack=="special": _advance_special(f,i)
		elif f.attack!="" and not f.swing_emitted and f.stun<=0.0:
			# Accepted attack time drives the cue even if the attack never contacts.
			# Interrupted startup never reaches this marker; signatures have no swing.
			if f.clock>=float(attack_config(f,f.attack).startup):
				f.swing_emitted=true
				_emit_event({"type":"swing","kind":f.attack,"source":i,"fighter":i,"attack_id":f.attack_id})
		if f.attack!="" and (f.clock>=f.duration or (f.attack=="special" and f.clock+0.0000001>=f.duration)):
			var completed_special:bool=f.attack=="special"
			var followup:bool=f.queued=="straight" and f.queued_attack_id==f.attack_id and f.attack=="punch" and f.chain==1 and f.stun<=0.0 and f.land_lock<=0.0 and not f.input_rearm
			_clear_attack_buffer(f)
			f.attack=""
			f.state="idle"
			if completed_special:
				f.special_phase=""; f.special_phase_clock=0.0
			if followup:
				# Facing is committed per attack, not across an entire chain.
				f.face=1 if opponent.x>=f.x else -1
				begin_attack(f,"straight")
			else:
				f.chain_window=0.16 if f.chain<2 else 0.0
				if f.chain>=2: f.land_lock=maxf(f.land_lock,0.19); f.chain=0
		if f.attack=="" and f.chain_window<=0.0: f.chain=0
		if f.attack=="":
			f.face=1 if opponent.x>=f.x else -1
		f.crouching=bool(cmd.get("crouch",false)) and f.attack=="" and f.stun<=0.0 and f.y<=0.001 and f.vy<=0.0 and not f.input_rearm
		f.blocking=not f.crouching and f.attack=="" and f.stun<=0.0 and f.y<=0.001 and f.land_lock<=0.0 and f.move*f.face< -0.2 and f.guard>1.0
		if f.blocking:
			f.guard=maxf(0.0,f.guard-delta*9.0)
			f.guard_delay=0.65
		elif f.guard_delay<=0.0:
			f.guard=minf(100.0,f.guard+delta*18.0)
		if f.stun<=0.0 and f.attack=="" and f.land_lock<=0.0 and not f.input_rearm:
			if punch_pressed: begin_attack(f,"punch")
			elif heavy_pressed: begin_attack(f,"heavy")
			elif roundhouse_pressed: begin_attack(f,"roundhouse")
			elif special_pressed: begin_special(f)
			elif cmd.get("kick",false): begin_attack(f,"kick")
			elif jump_pressed and f.y<=0.001:
				f.vy=JUMP_VELOCITY
				# Ground launch accepts diagonals immediately. Later air changes
				# accelerate towards the held direction instead of snapping vx.
				f.vx=f.move*SPEED
				f.blocking=false
				f.crouching=false
				f.crouch_amount=0.0
				f.state="jump"
				_emit_event({"type":"jump","fighter":i})
		if f.stun>0.0:
			f.state="hurt"
			f.vx=move_toward(f.vx,0.0,delta*8.0)
		elif f.attack=="":
			if f.y>0.001 or f.vy>0.0:
				f.vx=move_toward(f.vx,f.move*SPEED,AIR_ACCELERATION*delta)
				f.state="jump"
			elif f.crouching:
				f.vx=0.0
				f.state="crouch"
			else:
				f.vx=f.move*(RETREAT_SPEED if f.blocking else SPEED) if f.land_lock<=0.0 else 0.0
				f.state="guard" if f.blocking else ("move" if absf(f.move)>0.1 else "idle")
		elif f.attack in STATIONARY_ATTACKS: f.vx=0.0
		# Presentation samples simulation-owned crouch progress. Releasing down
		# never adds a movement lock; attacks/jumps/hits take immediate priority.
		if f.crouching:
			f.crouch_amount=minf(1.0,f.crouch_amount+delta/CROUCH_TRANSITION)
		elif f.attack=="" and f.stun<=0.0 and f.y<=0.001 and f.vy<=0.0:
			f.crouch_amount=maxf(0.0,f.crouch_amount-delta/CROUCH_TRANSITION)
		else:
			f.crouch_amount=0.0
		if f.attack!="special": _move_and_land(f,i,delta)
	_resolve_pushboxes()
	for i in range(2):
		if fighters[i].special_pending_emit: _emit_projectile(i)
	var a:Dictionary=fighters[0]; var b:Dictionary=fighters[1]
	# Collect contacts before applying to allow fair simultaneous trades.
	var contacts:Array=[]
	for i in range(2):
		var f:Dictionary=fighters[i]; var o:Dictionary=fighters[1-i]
		if f.attack=="" or f.attack=="special" or f.hit or f.stun>0.0 or f.down or o.down: continue
		var c:=attack_config(f,f.attack)
		# Authored decimal endpoints must not gain an extra contact from binary
		# addition drift (notably .28 + .14 > the exact authored .42 boundary).
		var active_end:float=snappedf(c.startup+c.active,0.000001)
		if f.clock<c.startup or f.clock>=active_end: continue
		var geometry:=contact_geometry(f,f.attack)
		var forward:float=(o.x-f.x)*f.face
		if not geometry.depth_overlap or forward<0.0 or forward>geometry.reach+HURT_X: continue
		if f.y+geometry.high<o.y+0.15 or f.y+geometry.low>o.y+1.92: continue
		if o.invuln>0.0: continue
		# Capture presentation coordinates and attack identity before either
		# contact is applied: a simultaneous hit can clear this source's move.
		# These retain the existing visual anchors, never alter contact geometry.
		var impact_y:float=f.y+(geometry.low+geometry.high)*0.5 if f.attack=="roundhouse" else o.y+(0.65 if f.attack=="kick" else 1.30)
		contacts.append({"source":i,"attack_id":f.attack_id,"config":c,"kind":f.attack,"impact_x":o.x+signf(f.x-o.x)*0.27,"impact_y":impact_y})
	_collect_projectile_contacts(delta,contacts)
	for contact in contacts:
		var i:int=contact.source
		var f:Dictionary=fighters[i]; var o:Dictionary=fighters[1-i]
		var c:Dictionary=contact.config
		if not contact.has("projectile_id"): f.hit=true
		var hit_face:int=int(contact.get("face",f.face))
		var frontal:bool=bool(contact.get("frontal",(f.x-o.x)*o.face>0.0))
		if o.blocking and frontal and o.guard>=c.guard:
			o.guard-=c.guard
			o.guard_delay=1.0
			o.x=clampf(o.x+hit_face*c.push*0.35,LEFT,RIGHT)
			var block_event:Dictionary={"type":"block","source":i,"fighter":1-i,"attack_id":contact.attack_id,"kind":contact.kind,"impact_y":contact.impact_y,"ko":false}
			if contact.has("impact_x"): block_event.impact_x=contact.impact_x
			_emit_event(block_event)
		else:
			var broken:bool=o.blocking and frontal
			if broken: o.guard=0.0; o.guard_delay=1.8
			o.hp=maxf(0.0,o.hp-c.damage)
			o.stun=c.stun+(0.17 if broken else 0.0)
			o.stun_duration=o.stun; o.hit_age=0.0; o.hit_kind=contact.kind
			o.invuln=o.stun+0.18
			o.vx=hit_face*(c.push/0.13)
			o.attack=""; o.chain=0; o.chain_window=0.0; o.blocking=false; o.crouching=false; o.crouch_amount=0.0; o.state="hurt"; o.clock=0.0
			_clear_attack_buffer(o)
			_clear_special(o)
			var hit_event:Dictionary={"type":"break" if broken else "hit","source":i,"fighter":1-i,"attack_id":contact.attack_id,"damage":c.damage,"kind":o.hit_kind,"impact_y":contact.impact_y,"ko":o.hp<=0.0}
			if contact.has("impact_x"): hit_event.impact_x=contact.impact_x
			_emit_event(hit_event)
			if contact.kind=="kick" or o.hp<=0.0:
				_enter_down(o,1-i,contact.kind)
	if a.hp<=0.0 or b.hp<=0.0 or time_left<=0.0:
		for i in range(2):
			if fighters[i].hp<=0.0 and (not fighters[i].down or not fighters[i].down_ko):
				_enter_down(fighters[i],i,fighters[i].hit_kind)
		for f: Dictionary in fighters:
			_clear_attack_buffer(f)
			_clear_special(f)
		projectiles.clear()
		round_over=true
		winner=-1 if is_equal_approx(a.hp,b.hp) else (0 if a.hp>b.hp else 1)
		_emit_event({"type":"round","winner":winner})
