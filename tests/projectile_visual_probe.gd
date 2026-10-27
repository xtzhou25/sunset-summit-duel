extends SceneTree
## Visual primitive fixture only, not a live match or animation acceptance.
var main
var elapsed:=0.0
func _initialize() -> void:
	root.size=Vector2i(960,600)
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	call_deferred("configure")
func configure() -> void:
	root.size=Vector2i(960,600)
	main.hud._choose(0)
	main.paused=true
	main.sim.projectiles=[{"id":100,"kind":"meow","pos":Vector2(-0.3,1.65)}, {"id":101,"kind":"heart","pos":Vector2(0.45,2.40)}]
	main.render_state(0.0)
func _process(delta:float) -> bool:
	elapsed+=delta
	if elapsed>1.0:
		root.get_texture().get_image().save_png("res://exports/qa-v6/projectile-visual-probe.png")
		quit()
	return false
