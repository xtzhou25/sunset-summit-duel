extends SceneTree
const DT:=1.0/60.0
class Passive extends RefCounted:
 var command:Dictionary={}
 func reset():command={}
 func act(_s,_d):return command.duplicate()
var game
var robot:=Passive.new()
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok: failures+=1;printerr("FAIL ",label)
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false);game.brain=robot
 for a in range(5):
  for b in range(5):
   if a==b:continue
   game.start_match(a,b);game.set_physics_process(false);game.render_state(0)
   check(game.sim.fighters[0].kind==a and game.sim.fighters[1].kind==b,"explicit twenty pairs")
   for i in range(2):
    var k:int=a if i==0 else b
    check(game.hud._names[i].text==game.Characters.get_character(k).name+(" AI" if i==1 else ""),"HUD role names")
    check(game.model_cache[k].get_parent()==game.actors[i],"model attached proper slot")
    check(not game.rifle_props[i].visible,"no rifle on non-rifle idle")
 for foe in range(4):
  for face in [-1,1]:
   for mode in ["hit","block","miss","interrupt","pause"]:
    game.start_match(4,foe);game.set_physics_process(false);robot.command={}
    var f:Dictionary=game.sim.fighters[0];var o:Dictionary=game.sim.fighters[1]
    f.x=-.9*face;o.x=1.1*face;f.face=face;o.face=-face
    var target:float=o.x
    if mode=="block":robot.command.move=float(face)
    game.on_command("special",true);var emitted:=0;var seen:Dictionary={};var peakwarn:=0;var peakfruit:=0
    for frame in range(110):
     game._physics_process(DT)
     if frame==1:game.on_command("special",false)
     if mode=="miss" and frame==6:o.x=-target
     if mode=="interrupt" and frame==6:
      f.attack="";f.stun=.3;f.stun_duration=.3;f.hit_kind="punch";game.sim._clear_special(f)
     if mode=="pause" and frame==6:
      game.toggle_pause();var age:float=game.sim.elapsed
      for j in range(5):game._physics_process(DT)
      check(game.sim.elapsed==age,"pause freezes warning and drop")
      game.toggle_pause()
     peakwarn=maxi(peakwarn,game.projectile_view.warnings.size());peakfruit=maxi(peakfruit,game.projectile_view.views.size())
     check(game.projectile_view.warnings.size()<=1,"one warning only")
     for e:Dictionary in game.sim.events:
      if seen.has(e.event_id):continue
      seen[e.event_id]=true
      if e.type=="projectile_spawn" and e.kind=="cake":
       emitted+=1;check(absf(e.pos.x-target)<.00001,"locked fixed target")
       check(game.projectile_view.views.has(e.id),"actual cake visual created")
       if game.projectile_view.views.has(e.id):check(game.projectile_view.views[e.id].get_child_count()>0,"cake actual mesh scene not empty")
    check(emitted==(0 if mode=="interrupt" else 1),"one activation one cake or canceled")
    check(peakwarn==1,"warning visible during startup")
    check(game.projectile_view.warnings.is_empty() and game.projectile_view.views.is_empty(),"resolved warning and cake gone")
    if mode in ["block","miss","interrupt"]:check(o.hp==100.0,"expected no damage "+mode)
    else:check(o.hp==88.0,"single 12 damage "+mode)
    game.show_menu();check(game.projectile_view.warnings.is_empty(),"menu clears warning")
 game.queue_free();await process_frame
 print("HA_RUNTIME_RESULT checks=",checks," failures=",failures," cases=40 pairs=20")
 quit(1 if failures else 0)
