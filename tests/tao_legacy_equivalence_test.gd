extends SceneTree
const Old=preload("res://tests/tao_legacy_combat.gd")
const New=preload("res://scripts/combat.gd")
var checks:=0
var failures:=0
func _init():
 for pair in [[0,1],[0,2],[1,0],[1,2],[2,0],[2,1]]:
  var kind:int=pair[0]
  var opponent:int=pair[1]
  for seed_id in range(4):
   var before=Old.new();var after=New.new();before.reset(kind,opponent);after.reset(kind,opponent)
   var rng:=RandomNumberGenerator.new();rng.seed=3971+seed_id
   for frame in range(2400):
    var commands:Array=[]
    for slot in range(2):
     var c:Dictionary={"move":float(rng.randi_range(-1,1))}
     for action in ["jump","crouch","punch","kick","heavy","roundhouse","special"]:c[action]=rng.randf()<.12
     commands.append(c)
    before.step(1.0/60.0,commands);after.step(1.0/60.0,commands)
    checks+=1
    if before.fighters!=after.fighters or before.events!=after.events or before.projectiles!=after.projectiles or before.time_left!=after.time_left or before.winner!=after.winner:
     failures+=1;printerr("LEGACY MISMATCH kind=",kind," seed=",seed_id," frame=",frame)
     for slot in range(2):
      for key in before.fighters[slot]:
       if before.fighters[slot][key]!=after.fighters[slot][key]:printerr("field ",slot," ",key,": ",before.fighters[slot][key]," vs ",after.fighters[slot][key])
     printerr("events ",before.events," vs ",after.events)
     printerr("projectiles ",before.projectiles," vs ",after.projectiles)
     break
    if before.round_over:
     before.reset(kind,opponent);after.reset(kind,opponent)
 print("TAO LEGACY EQUIVALENCE frames=",checks," failures=",failures)
 quit(failures)
