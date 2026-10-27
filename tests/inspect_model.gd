extends SceneTree
func _init():
	var m=load("res://assets/purple.glb").instantiate()
	root.add_child(m)
	inspect(m)
	quit()
func inspect(n):
	if n is MeshInstance3D:
		for i in range(n.mesh.get_surface_count()):
			var m=n.get_active_material(i)
			if m: print(m.resource_name," albedo=",m.albedo_color," rough=",m.roughness," emission=",m.emission_enabled," shading=",m.shading_mode)
	if n is AnimationPlayer: print("ANIMS",n.get_animation_list())
	for c in n.get_children(): inspect(c)
