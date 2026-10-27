extends Node
const DT:=1.0/10.0
var phase:String
var out:String
var game
var records:Array=[]
class PassiveAI extends RefCounted:
 func reset():pass
 func act(_s,_d):return {}
func _ready():
 phase=FileAccess.get_file_as_string("res://tests/idle-phase.txt").strip_edges()
 out="res://exports/qa-idle-native/"+phase
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
 get_window().size=Vector2i(960,600)
 game=load("res://main.tscn").instantiate();add_child(game);game.set_physics_process(false);game.auto_demo=false;game.brain=PassiveAI.new()
 await get_tree().process_frame
 for kind in range(5):
  for face in [-1,1]:
   game.hud.opponent_choice=(kind+1)%5;game.hud._choose(kind);game.set_physics_process(false)
   game.sim.fighters[0].x=-1.3*face;game.sim.fighters[1].x=1.3*face
   game.sim.fighters[0].face=face;game.sim.fighters[1].face=-face
   game.render_state(0);game.layout_camera()
   for frame in range(60):
    game._physics_process(DT)
    await get_tree().process_frame
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png(out+"/%d_%d_%03d.png"%[kind,face,frame])
   records.append({"kind":kind,"face":face,"frames":60,"clip":game.current_clips[0]})
   var f=FileAccess.open(out+"/manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "));f.close()
 print("IDLE_NATIVE_COMPLETE ",phase)
 get_tree().quit()
