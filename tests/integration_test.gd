extends SceneTree
var failures:=0
func check(ok:bool,label:String):
	if not ok: failures+=1;printerr("FAIL ",label)
	else: print("PASS ",label)
func _init(): call_deferred("run")
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_physics_process(false)
	await process_frame
	game.hud._choose(0)
	check(game.playing and game.sim.fighters[0].kind==0,"Purple selectable")
	game.held.right=true;game.taps.kick=true;game.toggle_pause()
	var before=game.sim.time_left;game._physics_process(0.5)
	check(game.paused and game.sim.time_left==before and game.held.is_empty() and game.taps.is_empty(),"Pause freezes time and clears input")
	game.toggle_pause();game._physics_process(0.01)
	check(not game.paused and game.sim.fighters[0].attack=="","Resume does not repeat stale attack")
	game.hud._choose(1)
	check(game.sim.fighters[0].kind==1 and game.sim.fighters[0].hp==100 and game.wins==[0,0],"Yellow selection resets match")
	game.sim.time_left=0.001;game._physics_process(0.02)
	check(game.sim.winner==-1 and game.wins==[0,0],"Draw awards no round")
	game._physics_process(2.5)
	check(not game.sim.round_over and game.sim.time_left==60.0,"Draw replays fresh round")
	for i in range(2):
		game.sim.fighters[1].hp=0;game._physics_process(0.02);game._physics_process(2.5)
	check(game.wins==[2,0] and not game.playing,"Best of three ends at two wins")
	game.hud._request_rematch()
	check(game.playing and game.wins==[0,0] and game.sim.fighters[1].hp==100 and game.round_delay==0,"Rematch clears KO result and scoreboard")
	game.held.left=true;game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.paused and game.held.is_empty(),"Background loses held inputs and pauses")
	game.show_menu();game.hud._choose(0)
	check(not game.paused and game.sim.fighters[0].kind==0 and game.sim.time_left==60,"Return menu and switch are clean")
	game.brain.reset();var acts=[]
	for i in range(10): acts.append(game.brain.act(game.sim,1.0/60.0))
	check(acts.all(func(c):return not c.get("punch",false) and not c.get("kick",false) and c.move==0),"AI initial reaction delay is real")
	print("Integration failures: ",failures);quit(failures)
