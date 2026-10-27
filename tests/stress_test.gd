extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const AI=preload("res://scripts/ai.gd")
func _init() -> void:
	var result=[0,0,0]
	for match_id in range(80):
		var s=Combat.new(); s.reset(match_id%2)
		var bot=AI.new(); bot.rng.seed=match_id*1237+7
		var rng=RandomNumberGenerator.new();rng.seed=match_id+123
		var held=0.0
		for frame in range(3650):
			if frame%15==0: held=rng.randf_range(-1,1)
			var cmd={"move":held,"punch":rng.randf()<0.025,"heavy":rng.randf()<0.014,"kick":rng.randf()<0.018,"jump":rng.randf()<0.009}
			s.step(1.0/60.0,[cmd,bot.act(s,1.0/60.0)])
			for f in s.fighters:
				assert(f.x>=Combat.LEFT and f.x<=Combat.RIGHT and f.y>=0.0)
				assert(f.hp>=0 and f.hp<=100 and f.guard>=0 and f.guard<=100)
				assert(not(f.blocking and f.y>0.001))
			if s.round_over: break
		assert(s.round_over)
		result[s.winner+1]+=1
	print("80 deterministic full rounds pass. Draw/player/AI: ",result)
	quit()
