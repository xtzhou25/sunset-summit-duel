extends Node
const DT:=1.0/60.0
const OUT:="res://exports/qa-idle-native/transitions"
class PassiveAI extends RefCounted:
 func reset():pass
 func act(_s,_d):return {}
var game
var records:Array=[]
func _ready():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 game=load("res://main.tscn").instantiate();add_child(game);game.set_physics_process(false);game.auto_demo=false;game.brain=PassiveAI.new()
 await get_tree().process_frame
 for kind in range(5):
  for face in [-1,1]:
   for action in ["punch","hit","crouch","guard","run","sideflip","jump","recover"]:
    game.show_menu();game.hud.opponent_choice=(kind+1)%5;game.hud._choose(kind);game.set_physics_process(false)
    game.sim.fighters[0].x=-1.3*face;game.sim.fighters[1].x=1.3*face
    for n in range(93):game._physics_process(DT)
    var f=game.sim.fighters[0]
    if action=="punch":game.on_command("punch",true)
    elif action=="hit":f.stun=.25;f.stun_duration=.25;f.hit_age=0.0
    elif action=="jump":game.on_command("jump",true)
    elif action=="recover":f.down=true;f.down_phase="rise";f.down_clock=0.0;f.down_ko=false
    elif action=="crouch":game.on_command("crouch",true)
    elif action=="guard":game.on_command("left" if face>0 else "right",true)
    elif action=="run":game.on_command("right" if face>0 else "left",true)
    else:f.x=1.3*face;game.sim.fighters[1].x=-1.3*face
    for frame in range(91):
     if frame==15:
      for cmd in ["punch","crouch","left","right","jump"]:game.on_command(cmd,false)
     game._physics_process(DT)
     if frame in [0,5,14,24,90]:
      await get_tree().process_frame;await RenderingServer.frame_post_draw
      var path=OUT+"/%d_%d_%s_%02d.png"%[kind,face,action,frame]
      get_viewport().get_texture().get_image().save_png(path)
      records.append({"path":path,"kind":kind,"face":face,"action":action,"frame":frame,"clip":game.current_clips[0],"attack":f.attack,"clock":f.clock})
 var file=FileAccess.open(OUT+"/manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(records,"  "));file.close()
 print("IDLE_TRANSITIONS_COMPLETE ",records.size());get_tree().quit()
