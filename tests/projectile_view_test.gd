extends SceneTree
var failures:=0
func _initialize() -> void:
	call_deferred("run")
func check(ok:bool,label:String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func run() -> void:
	var view=load("res://scripts/projectile_view.gd").new()
	root.add_child(view)
	await process_frame
	view.note_emission(1,0.18)
	view.note_emission(2,-0.12)
	view.sync_projectiles([{"id":1,"kind":"meow","pos":Vector2(-0.7,1.5)}, {"id":2,"kind":"heart","pos":Vector2(1.0,2.4)}])
	check(view.views.size()==2,"two independently owned visual projectiles")
	check(view.views[1] is Label3D and view.views[1].text=="喵","actual Chinese glyph, not a placeholder image")
	check(view.font.has_char("喵".unicode_at(0)),"packaged font includes 喵")
	check(view.views[1].billboard==BaseMaterial3D.BILLBOARD_ENABLED,"text faces camera without fighter mirroring")
	check(view.views[1].scale==Vector3.ONE,"no negative text scale")
	check(view.views[1].position==Vector3(-0.7,1.5,0.18),"mouth emission depth preserved")
	check(view.views[2] is MeshInstance3D and view.heart_mesh.get_surface_count()==1,"heart is actual extruded polygon mesh")
	check(view.heart_mesh.get_aabb().size.z>0.10,"heart has visible solid thickness")
	view.sync_projectiles([{"id":1,"kind":"meow","pos":Vector2(0.1,1.5)}])
	check(view.views.size()==1 and not view.depths.has(2),"consumed projectile visual and depth removed")
	view.clear()
	check(view.views.is_empty() and view.depths.is_empty(),"reset clears all projectile visuals")
	quit(failures)
