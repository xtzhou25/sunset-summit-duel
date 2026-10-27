extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame
 game.set_physics_process(false)
 assert(game.audio_pool.assets_ready)
 assert(game.audio_pool.players.size()==10 and game.audio_pool.cue_streams.size()==22)
 var streams:=0
 for cue in game.audio_pool.CUE_SPECS:
  assert(game.audio_pool.cue_streams[cue].size()==(1 if cue=="meow" else 2))
  streams+=game.audio_pool.cue_streams[cue].size()
 assert(streams==43)
 for role in range(5):
  game.hud.set_opponent_choice(-1);game.hud._choose(role)
  assert(game.opponent_selected!=role and game.opponent_selection.requested==-1)
  assert(game.hud._opponent_button.text.contains("随机"))
  for other in range(5):
   if role==other:continue
   game.start_match(role,other);game.render_state(0)
   assert(game.sim.fighters[1].kind==other)
   assert(game.hud._names[0].text==game.Characters.get_character(role).name)
 game.audio_pool.suspend(true);await create_timer(.35).timeout
 game.queue_free();await process_frame
 print("RANDOM_AUDIO_PACK_PASS five random roles,20 manual pairs,22 cues,43 streams,10 voices")
 quit()
