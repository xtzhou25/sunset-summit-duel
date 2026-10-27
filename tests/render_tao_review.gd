extends Node
## Actual native scene and exact mobile viewports. Controlled demonstration, not human playtesting.
const DT:=1.0/60.0
const OUT:="res://exports/qa-v13/native-tao"
class PassiveAI extends RefCounted:
 var command:Dictionary={}
 func reset():command={}
 func act(_s,_d):return command.duplicate()
var records:Array=[]
var robot:=PassiveAI.new()
func _ready():
 if DisplayServer.get_name()=="headless":print("TAO_REVIEW_PARSE_OK");get_tree().quit();return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 for dims in [Vector2i(1280,800),Vector2i(375,614),Vector2i(568,267)]:
  var vp:=SubViewport.new();vp.size=dims;vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
  var game=load("res://main.tscn").instantiate();vp.add_child(game);game.set_physics_process(false);game.auto_demo=false;game.brain=robot
  await get_tree().process_frame;await get_tree().process_frame
  await capture(vp,game,dims,"menu")
  for face in [-1,1]:
   for mode in ["hit","block","interrupt"]:
    game.show_menu();game.hud.opponent_choice=2;game.hud._choose(3);game.set_physics_process(false);robot.command={}
    var f:Dictionary=game.sim.fighters[0];var o:Dictionary=game.sim.fighters[1]
    f.x=-1.1*face;o.x=1.3*face;f.face=face;o.face=-face
    if mode=="block":robot.command.move=float(face)
    if mode=="interrupt":
     f.x=-.35*face;o.x=.35*face;robot.command.heavy=true
     for i in range(9):game._physics_process(DT)
    game.render_state(0);game.on_command("special",true)
    for frame in range(84):
     game._physics_process(DT)
     if frame==1:game.on_command("special",false)
     if frame in [0,12,24,25,30,45,65,83]:
      await capture(vp,game,dims,"%s_face%s_f%02d"%[mode,face,frame])
  # Actual exported common attack at critical authored times in game camera.
  for face in [-1,1]:
   game.start_match(3,0);game.set_physics_process(false);robot.command={}
   game.sim.fighters[0].x=-.6*face;game.sim.fighters[1].x=2.2*face
   game.sim.fighters[0].face=face;game.sim.fighters[1].face=-face
   game.on_command("roundhouse",true)
   for frame in range(65):
    game._physics_process(DT)
    if frame==1:game.on_command("roundhouse",false)
    if frame in [10,12,16,20,28,30,48,64]:await capture(vp,game,dims,"roundhouse_face%s_f%02d"%[face,frame])
  vp.queue_free();await get_tree().process_frame
 write_manifest(true);print("TAO_REVIEW_COMPLETE captures=",records.size())
 var label:=Label.new();label.text="TAO REVIEW COMPLETE / native exact viewport images";add_child(label)
func capture(vp:SubViewport,game,dims:Vector2i,key:String):
 await get_tree().process_frame;await RenderingServer.frame_post_draw
 var img:Image=vp.get_texture().get_image();var path:String=OUT+"/%dx%d_%s.png"%[dims.x,dims.y,key];var err:int=img.save_png(path)
 records.append({"path":path,"key":key,"requested":str(dims),"actual":str(img.get_size()),"size_matches":img.get_size()==dims,"save_error":err,"playing":game.playing,"pair":[game.sim.fighters[0].kind,game.sim.fighters[1].kind],"elapsed":game.sim.elapsed,"clip":game.current_clips[0],"clock":game.sim.fighters[0].clock,"projectiles":game.sim.projectiles.duplicate(true),"emitter":str(game.emitter_positions.get(0))})
 write_manifest(false)
func write_manifest(done:bool):
 var f=FileAccess.open(OUT+"/manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify({"complete":done,"records":records,"scope":"actual Godot native game SubViewports; scripted positions/actions; not browser or hardware"},"  "));f.close()
