extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var scene=load("res://main.tscn").instantiate();root.add_child(scene)
 await process_frame
 assert(scene.audio_pool.assets_ready)
 assert(scene.audio_pool.players.size()==10)
 assert(scene.audio_pool.cue_streams.size()==16)
 assert(scene.audio_pool.cue_streams.meow.size()==1)
 for cue in scene.audio_pool.CUE_SPECS:
  assert(scene.audio_pool.cue_streams[cue].size()==(1 if cue=="meow" else 2))
 assert(scene.sim.fighters.size()==2)
 scene.hud._choose(1);scene.set_physics_process(false);scene.render_state(0)
 assert(scene.hud._names[0].text=="鱼" and scene.hud._names[1].text=="因 AI")
 print("P2 EXPORTED PACK PASS: 10 fixed voices / 31 imported streams / selected fish identity")
 scene.queue_free();await process_frame;quit()
