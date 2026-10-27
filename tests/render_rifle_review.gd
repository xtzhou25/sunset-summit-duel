extends Node
## QA-only full rifle cast; F6. Native root resizing recorded, never assumed.
const DT:=1.0/60.0
const OUT:="res://exports/qa-v11/native-rifle-review"
class PassiveAI extends RefCounted:
	func reset():pass
	func act(_s,_d):return {}
var game
var caption:Label
var records:Array=[]
var started:int
func _ready():
	if DisplayServer.get_name()=="headless":print("RIFLE_REVIEW_PARSE_OK");get_tree().quit();return
	started=Time.get_ticks_msec();DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_window().size=Vector2i(1280,800)
	game=load("res://main.tscn").instantiate();add_child(game);game.set_physics_process(false);game.auto_demo=false;game.brain=PassiveAI.new()
	var layer:=CanvasLayer.new();layer.layer=100;add_child(layer);caption=Label.new();layer.add_child(caption);caption.position=Vector2(8,2);caption.add_theme_font_size_override("font_size",12);caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame
	for face in [-1,1]:
		game.show_menu();game.hud.opponent_choice=0;game.hud._choose(2);game.set_physics_process(false)
		var f:Dictionary=game.sim.fighters[0];var o:Dictionary=game.sim.fighters[1]
		f.x=-1.5*face;o.x=2.1*face;f.face=face;o.face=-face;game.render_state(0)
		game.on_command("special",true)
		# Capture immediately around reveal/fire/recoil/hide, then complete idle. Exact simulated clocks in manifest.
		for frame in range(70):
			game._physics_process(DT)
			if frame==1:game.on_command("special",false)
			caption.text="七 RifleCast / face "+str(face)+" / age "+str(snappedf(game.sim.elapsed,.001))+" / "+str(game.current_clips[0])
			if frame in [4,17,23,28,55,56,65,69]:
				await capture("face_%s_frame_%02d"%[face,frame])
				await get_tree().create_timer(.45).timeout
			await get_tree().create_timer(DT*3).timeout
	for wanted in [Vector2i(568,267),Vector2i(375,614)]:
		get_window().size=wanted;await get_tree().create_timer(.4).timeout
		game.show_menu();caption.text="requested "+str(wanted)+" actual "+str(get_window().size);await get_tree().create_timer(.15).timeout;await capture("menu_"+str(wanted))
		game.hud.opponent_choice=0;game.hud._choose(2);game.layout_camera();game.render_state(0);await get_tree().create_timer(.15).timeout;await capture("match_"+str(wanted))
	caption.text="RIFLE REVIEW COMPLETE / no loop";write_manifest(true)
	print("RIFLE_REVIEW_COMPLETE seconds=",(Time.get_ticks_msec()-started)/1000.0)
func capture(key:String):
	await RenderingServer.frame_post_draw
	var image:Image=get_viewport().get_texture().get_image();var path:String=OUT+"/%02d.png"%records.size();var err:int=image.save_png(path)
	records.append(capture_metadata(path,key,err,image.get_size(),get_window().size,get_viewport().get_visible_rect().size))
	write_manifest(false)
func capture_metadata(path:String,key:String,error:int,image_size:Vector2i,window_size:Vector2i,viewport_size:Vector2)->Dictionary:
	var f:Dictionary=game.sim.fighters[0]
	var has_marker:bool=game.emitter_positions.has(0)
	return {"path":path,"key":key,"save_error":error,"actual_window_size":str(window_size),"actual_viewport_size":str(viewport_size),"image_size":str(image_size),"sim_elapsed":game.sim.elapsed,"cast_clock":f.clock,"attack":f.attack,"clip":game.current_clips[0],"prop_visible":game.rifle_props[0].visible,"prop_origin":str(game.rifle_props[0].global_position),"has_emitted_marker":has_marker,"muzzle":str(game.emitter_positions.get(0)) if has_marker else null,"projectiles":game.sim.projectiles.duplicate(true)}
func write_manifest(done:bool):
	var file=FileAccess.open(OUT+"/manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify({"complete":done,"records":records,"duration_seconds":(Time.get_ticks_msec()-started)/1000.0,"scope":"actual native viewport; 1/60 simulation, nearest >= keypoint frame; not physical mobile"},"  "));file.close()
