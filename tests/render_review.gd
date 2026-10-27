extends Node
## QA-only finite rendered review; F6 this scene. No production changes.
const DT:=1.0/60.0
const OUT:="res://exports/qa-v11/native-review"
class PassiveAI extends RefCounted:
 var command:Dictionary={}
 func reset():command.clear()
 func act(_s,_d):return command.duplicate()
var game
var robot:=PassiveAI.new()
var caption:Label
var records:Array=[]
var serial:=0
var scenario:=""
var started:int
func _ready():
 if DisplayServer.get_name()=="headless":
  print("RENDER_REVIEW_PARSE_OK: requires editor F6 graphical renderer")
  get_tree().quit();return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 get_window().size=Vector2i(1280,800)
 game=load("res://main.tscn").instantiate();add_child(game);game.set_physics_process(false);game.auto_demo=false;game.brain=robot
 var layer:=CanvasLayer.new();layer.layer=100;add_child(layer)
 caption=Label.new();layer.add_child(caption);caption.position=Vector2(8,2);caption.add_theme_font_size_override("font_size",12);caption.add_theme_color_override("font_color",Color.WHITE);caption.add_theme_color_override("font_shadow_color",Color.BLACK);caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
 started=Time.get_ticks_msec()
 await get_tree().process_frame
 for kind in range(3):
  for face in [-1,1]:
   for mode in ["roundhouse_guard","roundhouse_hit","special_hit","sideflip"]:
    scenario=["因","鱼","七"][kind]+" / "+str(face)+" / "+mode
    fresh(kind,face,mode)
    var checkpoints:Array=[10,11,17,27,29,64] if mode=="roundhouse_guard" else [1,8,14,24,36,48]
    for frame in range(66 if mode=="roundhouse_guard" else 49):
     if mode=="roundhouse_guard" and frame==40:game.on_command("left" if face>0 else "right",true)
     if mode=="sideflip" and frame==12:
      game.sim.fighters[0].x=1.1*face;game.sim.fighters[1].x=-1.1*face
     game._physics_process(DT)
     caption.text=scenario+" | frame "+str(frame)+" | "+str(game.current_clips[0])+" | 0.25×"
     if frame in checkpoints:
      await capture("f%02d"%frame)
      await get_tree().create_timer(.55).timeout
     await get_tree().create_timer(DT*4).timeout
 for wanted in [Vector2i(568,267),Vector2i(375,614)]:
  get_window().size=wanted
  await get_tree().create_timer(.35).timeout
  scenario="UI requested "+str(wanted);game.show_menu();caption.text=scenario+" / menu";await get_tree().create_timer(.2).timeout;await capture("menu")
  game.hud.opponent_choice=0;game.hud._choose(2);game.render_state(0);game.layout_camera();caption.text=scenario+" / 七 vs 因";await get_tree().create_timer(.3).timeout;await capture("selected")
 caption.text="QA COMPLETE / "+str(records.size())+" PNG / no loop"
 write_manifest(true)
 print("NATIVE_REVIEW_COMPLETE frames=",records.size()," seconds=",(Time.get_ticks_msec()-started)/1000.0)
func fresh(kind:int,face:int,mode:String):
 game.show_menu();game.hud.opponent_choice=(kind+1)%3;game.hud._choose(kind);game.set_physics_process(false);robot.reset()
 var f:Dictionary=game.sim.fighters[0];var o:Dictionary=game.sim.fighters[1]
 f.x=-1.1*face;o.x=1.1*face;f.face=face;o.face=-face;game.render_state(0)
 if mode in ["roundhouse_hit","special_hit"]:
  f.x=-.35*face;o.x=.35*face;robot.command={"heavy":true}
  for n in range(9):game._physics_process(DT)
 if mode.begins_with("roundhouse"):game.on_command("roundhouse",true)
 elif mode=="special_hit":game.on_command("special",true)
 else:game.on_command("right" if face>0 else "left",true)
func capture(key:String):
 await RenderingServer.frame_post_draw
 var image:Image=get_viewport().get_texture().get_image()
 var path:String=OUT+"/%03d_%s.png"%[serial,key];serial+=1
 var err:int=image.save_png(path)
 var f:Dictionary=game.sim.fighters[0]
 records.append({"path":path,"scenario":scenario,"key":key,"save_error":err,"actual_window_size":str(get_window().size),"actual_viewport_size":str(get_viewport().get_visible_rect().size),"image_size":str(image.get_size()),"clip":game.current_clips[0],"attack":f.attack,"clock":f.clock,"elapsed":game.sim.elapsed,"hp":f.hp,"face":f.face,"down":f.down})
 write_manifest(false)
func write_manifest(done:bool):
 var file=FileAccess.open(OUT+"/manifest.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"complete":done,"records":records,"duration_seconds":(Time.get_ticks_msec()-started)/1000.0,"scope":"native actual viewport rendering; fixtures set starting distances/HP and crossover positions, combat advances real main at 1/60; not device QA"},"  "));file.close()
