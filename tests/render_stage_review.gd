extends Node
const OUT:="res://exports/qa-stage-native/p6"
var records:Array=[]
func _ready():
 if DisplayServer.get_name()=="headless":get_tree().quit();return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 for dims in [Vector2i(960,600),Vector2i(568,267),Vector2i(375,614)]:
  var viewport:=SubViewport.new();viewport.size=dims;viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
  var game=load("res://main.tscn").instantiate();viewport.add_child(game);game.set_physics_process(false)
  await get_tree().process_frame;await get_tree().process_frame
  for scenario in ["center","left","right","wide","jump","cake"]:
   game.hud.opponent_choice=3;game.hud._choose(4);game.set_physics_process(false)
   var positions:Array=[-1.05,1.05]
   if scenario=="left":positions=[-4.2,-2.2]
   if scenario=="right":positions=[2.2,4.2]
   if scenario in ["wide","jump"]:positions=[-2.9,2.9]
   for i in range(2):game.sim.fighters[i].x=positions[i]
   game.layout_camera()
   if scenario=="jump":
    game.sim.step(1.0/60.0,[{"jump":true},{"jump":true}])
    for n in range(20):game.sim.step(1.0/60.0,[{},{}]);game.render_state(1.0/60.0)
   elif scenario=="cake":
    game.sim.step(1.0/60.0,[{"special":true},{}])
    for n in range(40):game.sim.step(1.0/60.0,[{},{}]);game.render_state(1.0/60.0)
   else:game.render_state(.5)
   game.layout_camera()
   await get_tree().process_frame;await RenderingServer.frame_post_draw
   var img:Image=viewport.get_texture().get_image()
   var path:String=OUT+"/%dx%d_%s.png"%[dims.x,dims.y,scenario]
   img.save_png(path)
   records.append({"viewport":str(dims),"scenario":scenario,"file":path,"camera_x":game.camera.position.x,"camera_size":game.camera.size})
  viewport.queue_free();await get_tree().process_frame
 var f=FileAccess.open(OUT+"/manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "));f.close()
 print("STAGE_NATIVE_COMPLETE ",OUT," captures=",records.size());get_tree().quit()
