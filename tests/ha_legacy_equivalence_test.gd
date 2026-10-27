extends SceneTree
const Old=preload("res://tests/ha_legacy_combat.gd")
const New=preload("res://scripts/combat.gd")
const OldBrain=preload("res://tests/ha_legacy_ai.gd")
const NewBrain=preload("res://scripts/ai.gd")
var checks:=0
var failures:=0
func _init():
 for kind in range(4):
  for opponent in range(4):
   if kind==opponent:continue
   for seed_id in range(4):
    var before=Old.new();var after=New.new();before.reset(kind,opponent);after.reset(kind,opponent)
    var b0=OldBrain.new();var b1=NewBrain.new();b0.rng.seed=711+seed_id;b1.rng.seed=711+seed_id;b0.reset();b1.reset()
    var rng:=RandomNumberGenerator.new();rng.seed=3971+seed_id
    for frame in range(2400):
     var commands:Array=[]
     for slot in range(2):
      var c:Dictionary={"move":float(rng.randi_range(-1,1))}
      for action in ["jump","crouch","punch","kick","heavy","roundhouse","special"]:c[action]=rng.randf()<.12
      commands.append(c)
     var old_cmd:Dictionary=b0.act(before,1.0/60.0);var new_cmd:Dictionary=b1.act(after,1.0/60.0)
     if old_cmd!=new_cmd:failures+=1;printerr("AI MISMATCH ",kind,"/",opponent," seed=",seed_id," frame=",frame);break
     if seed_id%2==0:commands[1]=old_cmd
     before.step(1.0/60.0,commands);after.step(1.0/60.0,commands)
     checks+=1
     # New role-only state may add neutral fields; compare every original field exactly.
     var equal:=true
     for slot in range(2):
      for key in before.fighters[slot]:
       if before.fighters[slot][key]!=after.fighters[slot].get(key):equal=false;printerr("FIELD ",slot," ",key)
     if not equal or before.events!=after.events or before.projectiles!=after.projectiles or before.time_left!=after.time_left or before.winner!=after.winner:
      failures+=1;printerr("LEGACY MISMATCH ",kind,"/",opponent," seed=",seed_id," frame=",frame);break
     if before.round_over:
      before.reset(kind,opponent);after.reset(kind,opponent);b0.reset();b1.reset()
 print("HA LEGACY EQUIVALENCE frames=",checks," failures=",failures)
 quit(failures)
