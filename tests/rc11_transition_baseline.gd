extends SceneTree
# Native main-loop transitions. Position/HP fixtures only, no injected animation clocks.
class PassiveAI extends RefCounted:
 var command:Dictionary={}
 func reset():command.clear()
 func act(_s,_d):return command.duplicate()
var game
var robot=PassiveAI.new()
var cases:Array=[]
var rows:Array=[]
var errors:Array=[]
var last_clip:String=""
var last_bones:Array=[]
var max_bone_step:float=0
func _initialize():call_deferred("run")
func check(ok:bool,msg:String):
 if not ok:errors.append(msg);printerr("FAIL ",msg)
func fresh(a:int,b:int):
 game.start_match(a,b);game.auto_demo=false;game.set_physics_process(false);game.brain=robot;robot.reset();game.sim.fighters[0].x=-1.5;game.sim.fighters[1].x=1.5;rows=[];last_clip="";last_bones=[];max_bone_step=0
func step(n:int):
 for z in range(n):
  game._physics_process(1.0/60)
  var f:Dictionary=game.sim.fighters[0]
  var clip:String=game.current_clips[0]
  var sk:Skeleton3D=game.find_skeleton(game.model_cache[f.kind]);sk.force_update_all_bone_transforms()
  var bones:Array=[]
  for bn in ["DEF-hand.L","DEF-hand.R","DEF-foot.L","DEF-foot.R","DEF-head"]:
   var index:int=sk.find_bone(bn)
   if index>=0:
    var p:Vector3=sk.get_bone_global_pose(index).origin;bones.append(p)
    if not p.is_finite():check(false,"non-finite bone "+bn)
  if last_bones.size()==bones.size():
   for k in range(bones.size()):max_bone_step=maxf(max_bone_step,last_bones[k].distance_to(bones[k]))
  if clip!=last_clip:
   rows.append({"time":game.sim.elapsed,"clip":clip,"attack":f.attack,"y":f.y,"clock":f.clock,"clip_time":game.anims[0].current_animation_position,"face":f.face,"down":f.down})
  last_clip=clip;last_bones=bones
func has_clip(prefix:String)->bool:
 for r in rows:
  if r.clip.begins_with(prefix):return true
 return false
func save_case(pair:Array,name:String):cases.append({"pair":pair,"scenario":name,"transitions":rows.duplicate(true),"maximum_sampled_local_bone_step_m":max_bone_step})
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false);game.brain=robot
 for a in range(3):
  for b in range(3):
   if a==b:continue
   var pair:Array=[a,b]
   fresh(a,b);game.on_command("crouch",true);step(20);game.on_command("punch",true);step(2);game.on_command("punch",false);game.on_command("crouch",false);step(45)
   check(has_clip("Crouch") and has_clip("Jab"),str(pair)+" crouch to punch represented");save_case(pair,"crouch_to_punch")
   fresh(a,b);game.on_command("jump",true);step(8);game.on_command("jump",false);game.on_command("punch",true);step(2);game.on_command("punch",false);step(90);game.on_command("heavy",true);step(45)
   check(has_clip("Jump") and has_clip("Jab") and has_clip("HeavyPunch"),str(pair)+" jump/aerial jab/landing/heavy clips");check(game.sim.fighters[0].y==0,str(pair)+" grounded at end");save_case(pair,"jump_jab_land_heavy")
   fresh(a,b);game.on_command("right",true);step(12);game.on_command("right",false)
   game.sim.fighters[0].x=1.2;game.sim.fighters[1].x=-1.2;step(3)
   check(game.sim.fighters[0].face==-1 and game.rendered_faces[0]==-1,str(pair)+" facing follows crossover fixture");save_case(pair,"facing_flip")
   fresh(a,b);game.on_command("special",true);step(12);game.show_menu();step(2)
   check(not game.playing and game.held.is_empty() and not game.rifle_props[0].visible,str(pair)+" special menu clears controls prop");save_case(pair,"special_menu")
   fresh(a,b);game.sim.fighters[0].x=-.35;game.sim.fighters[1].x=.35;robot.command={"heavy":true};step(9);game.on_command("special",true);step(80)
   check(has_clip("HitReact") or has_clip("Knockdown"),str(pair)+" incoming heavy interrupts special");check(game.sim.fighters[0].attack!="special",str(pair)+" interrupted special ended");save_case(pair,"special_heavy_interrupt")
   fresh(a,b);game.sim.fighters[0].x=-.35;game.sim.fighters[1].x=.35;game.sim.fighters[0].hp=1;robot.command={"heavy":true};step(9);game.on_command("special",true);step(80)
   check(has_clip("Knockdown") and game.sim.fighters[0].hp==0,str(pair)+" real heavy KO reaches down animation");check(not game.rifle_props[0].visible,str(pair)+" KO has no rifle prop");save_case(pair,"special_KO_down")
 var out={"cases":cases,"errors":errors,"scope":"native animation state numerical baseline; bone displacement observations are not visual smoothness proof"}
 var file=FileAccess.open("res://exports/qa-v11/transition-baseline.json",FileAccess.WRITE);file.store_string(JSON.stringify(out,"  "));file.close()
 print("TRANSITION_BASELINE scenarios=",cases.size()," failures=",errors.size())
 game.queue_free();await process_frame;quit(errors.size())
