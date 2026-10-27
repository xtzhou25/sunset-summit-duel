extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var scene=load("res://main.tscn").instantiate(); root.add_child(scene)
 await process_frame
 scene.set_physics_process(false)
 for player in range(3):
  for opponent in range(3):
   if player==opponent: continue
   scene.start_match(player,opponent)
   scene.render_state(0)
   assert(scene.sim.fighters[0].kind==player and scene.sim.fighters[1].kind==opponent)
   assert(scene.audio_pool.players.size()==10 and scene.audio_pool.cue_streams.size()==16)
   assert(scene.hud._names[0].text==["因","鱼","七"][player])
 assert(scene.audio_pool.cue_streams.rifle_emit.size()==2)
 print("QI EXPORTED PACK PASS: six pairs, three identities, two rifle streams, fixed ten voices")
 scene.queue_free(); await process_frame; quit()
