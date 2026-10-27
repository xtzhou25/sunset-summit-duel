extends SceneTree
func _init(): call_deferred('run')
func run():
 var scene=load('res://main.tscn').instantiate();root.add_child(scene);scene.set_physics_process(false)
 await process_frame
 for kind in [0,1]:
  scene.hud._choose(kind)
  var rounds:=0;var was_over:=false
  for frame in range(22000):
   var f=scene.sim.fighters[0];var o=scene.sim.fighters[1]
   scene.held.left=o.x<f.x and abs(o.x-f.x)>.78
   scene.held.right=o.x>f.x and abs(o.x-f.x)>.78
   scene.on_command("punch",frame%61==0 or (f.attack=="punch" and f.duration-f.clock<=.09 and f.duration-f.clock>.06))
   scene.on_command("heavy",frame%137==43)
   scene.on_command("roundhouse",frame%113==50)
   scene.on_command("kick",frame%80==0)
   scene._physics_process(1.0/60.0)
   if scene.sim.round_over and not was_over: rounds+=1
   was_over=scene.sim.round_over
   if not scene.playing: break
  assert(not scene.playing,'Full match must reach result')
  assert(scene.wins.max()==2 and rounds>=2,'Best of three must award two wins')
  print('Full live integration match kind=',kind,' rounds=',rounds,' score=',scene.wins)
  scene.start_match(kind)
  assert(scene.playing and scene.wins==[0,0] and scene.sim.fighters[0].hp==100)
 scene.queue_free();await process_frame;quit()
