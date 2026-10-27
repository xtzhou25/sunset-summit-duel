extends SceneTree
class PassiveAI extends RefCounted:
 func reset():pass
 func act(_s,_d):return {}
var game
var results=[]
var errors=[]
const BONES=["DEF-hand.L","DEF-hand.R","DEF-foot.L","DEF-foot.R","DEF-spine.006","DEF-spine"]
func _initialize():call_deferred("run")
func fresh(kind,face):
 game.start_match(kind,(kind+1)%5);game.set_physics_process(false);game.brain=PassiveAI.new();game.auto_demo=false
 game.sim.fighters[0].x=-1.5*face;game.sim.fighters[1].x=1.5*face
 step(1)
func step(n):
 for i in range(n):game._physics_process(1.0/60.0)
func pose():
 var sk=game.find_skeleton(game.model_cache[game.selected]);sk.force_update_all_bone_transforms()
 var out={}
 for bn in BONES:
  var bi=sk.find_bone(bn)
  if bi>=0:out[bn]=sk.global_transform*sk.get_bone_global_pose(bi).origin
 return out
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false)
 for kind in range(5):
  for face in [1,-1]:
   fresh(kind,face);step(12)
   var bounds={};var last_pose={};var max_step={};var wraps=0;var prev_time=-1.0;var changed=0;var root_start=game.actors[0].position;var root_drift=0.0
   var clip=game.current_clips[0];var length=game.anims[0].get_animation(clip).length
   for frame in range(480):
    step(1);var t=game.anims[0].current_animation_position
    if t<prev_time:wraps+=1
    if abs(t-prev_time)>0.00001:changed+=1
    prev_time=t;var p=pose()
    for bn in p:
     if not bounds.has(bn):bounds[bn]=[p[bn],p[bn]];max_step[bn]=0.0
     bounds[bn][0]=bounds[bn][0].min(p[bn]);bounds[bn][1]=bounds[bn][1].max(p[bn])
     if last_pose.has(bn):max_step[bn]=maxf(max_step[bn],p[bn].distance_to(last_pose[bn]))
    last_pose=p;root_drift=maxf(root_drift,game.actors[0].position.distance_to(root_start))
   var motion={}
   for bn in bounds:
    var span=bounds[bn][1]-bounds[bn][0]
    motion[bn]={"xyz_span_m":[span.x,span.y,span.z],"bbox_diagonal_m":span.length(),"max_frame_step_m":max_step[bn]}
   var before=pose();var paused_time=game.anims[0].current_animation_position;game.toggle_pause();step(60)
   var pause_error=0.0;var after=pose()
   for bn in before:pause_error=maxf(pause_error,before[bn].distance_to(after[bn]))
   var pause_dt=game.anims[0].current_animation_position-paused_time;game.toggle_pause();step(1)
   var row={"kind":kind,"face":face,"clip":clip,"length_s":length,"wraps_8s":wraps,"advanced_frames":changed,"root_drift_m":root_drift,"bones_world_m":motion,"pause_bone_change_m":pause_error,"pause_time_change_s":pause_dt,"transitions":[]}
   for action in ["punch","crouch","run","guard","wall_guard","hit"]:
    fresh(kind,face);step(15)
    if action=="punch":game.on_command("punch",true)
    elif action=="crouch":game.on_command("crouch",true)
    elif action=="run":game.on_command("right" if face==1 else "left",true)
    elif action=="guard":game.on_command("left" if face==1 else "right",true)
    elif action=="wall_guard":
     game.sim.fighters[0].x=-2.1*face;game.on_command("left" if face==1 else "right",true)
    elif action=="hit":
     game.sim.fighters[0].stun=0.25;game.sim.fighters[0].stun_duration=0.25;game.sim.fighters[0].hit_age=0.0
    var clips=[];var max_jump=0.0;var old=pose()
    for frame in range(100):
     if frame==15:
      for cmd in ["punch","crouch","left","right"]:game.on_command(cmd,false)
     step(1);var c=game.current_clips[0]
     if clips.is_empty() or clips[-1]!=c:clips.append(c)
     var pp=pose()
     for bn in pp:max_jump=maxf(max_jump,pp[bn].distance_to(old[bn]))
     old=pp
    row.transitions.append({"action":action,"clips":clips,"max_world_bone_step_m":max_jump})
   if changed<470 or wraps<1 or pause_error>0.00001 or abs(pause_dt)>0.00001:errors.append([kind,face,"idle/pause failure"])
   results.append(row)
 var output={"scope":"Real main scene, passive AI, native _physics_process at 60Hz. Eight seconds idle after blend warmup; world-space bone-origin bounds. Transitions use controls except hit fixture.","results":results,"errors":errors}
 var file=FileAccess.open("res://exports/qa-idle-baseline/runtime.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"  "));file.close()
 print("IDLE_AUDIT cases=",results.size()," errors=",errors)
 game.queue_free();await process_frame;quit(errors.size())
