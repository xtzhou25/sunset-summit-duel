extends SceneTree
const Combat=preload("res://scripts/combat.gd")
var failures:=0
func check(ok:bool,label:String) -> void:
	if not ok: failures+=1; printerr("FAIL: "+label)
	else: print("PASS: "+label)
func tick(s,n:int,a:Dictionary={},b:Dictionary={}) -> void:
	for j in range(n): s.step(1.0/60.0,[a,b])
func _init() -> void:
	var s=Combat.new()
	s.fighters[0].x=-0.35; s.fighters[1].x=0.35
	s.step(1.0/60.0,[{"punch":true},{}]); tick(s,35)
	check(s.fighters[1].hp==92.0,"One hit per punch")
	# Pin retreat at the wall to test guard, not escape from measured hand reach.
	s.reset(0); s.fighters[0].x=Combat.RIGHT-Combat.BODY*2.0; s.fighters[1].x=Combat.RIGHT
	s.step(1.0/60.0,[{"punch":true},{"move":1.0}]); tick(s,20,{}, {"move":1.0})
	check(s.fighters[1].hp==100.0 and s.fighters[1].guard<80.0,"Frontal ground retreat blocks, consumes guard")
	s.reset(0); tick(s,900,{}, {"move":1.0})
	check(s.fighters[1].guard<5.0,"Guard cannot turtle indefinitely")
	s.reset(0); tick(s,400,{"move":1.0},{"move":-1.0})
	check(s.fighters[0].x<s.fighters[1].x and absf(s.fighters[0].x-s.fighters[1].x)>=0.699,"Ground pushboxes do not cross")
	s.reset(0); tick(s,500,{"move":-1.0},{"move":1.0})
	check(s.fighters[0].x>=Combat.LEFT and s.fighters[1].x<=Combat.RIGHT,"Arena edge clamps")
	s.reset(0); s.time_left=0.01; tick(s,2)
	check(s.round_over and s.winner==-1,"Equal health timeout is draw")
	s.reset(1); check(s.fighters[0].hp==100 and s.time_left==60 and not s.round_over and s.fighters[0].attack=="","Reset clears complete combat state")
	s.fighters[0].x=-0.35; s.fighters[1].x=0.35; s.fighters[1].y=0.5; s.fighters[1].vy=1.0
	s.step(1.0/60.0,[{"punch":true},{"move":1.0}]); check(not s.fighters[1].blocking,"No blocking in air")
	print("Combat tests failures: ",failures)
	quit(failures)
