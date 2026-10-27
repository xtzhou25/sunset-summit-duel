extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const Brain=preload("res://scripts/ai.gd")
const DT=1.0/60.0
class PublicNullWorld extends RefCounted:
 var fighters:Array=[{"x":-1.0,"y":0.0,"attack":""},{"x":1.0,"y":0.0,"face":-1,"attack":"","guard":100.0}]
 var projectiles=null
var failures:=0
var checks:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok: failures+=1;printerr("FAIL ",label)
func _init():
 for seed_id in range(1,33):
  var world=Combat.new();world.fighters[0].x=-.5;world.fighters[1].x=.8
  var brain=Brain.new();brain.rng.seed=seed_id;brain.reset()
  var last_move:=0.0;var last_change:=-100;var moved:=false
  for frame in range(240):
   var cmd:Dictionary=brain.act(world,DT)
   if cmd.move!=last_move:
    check(frame-last_change>=10,"movement intent persists >=170ms quantized")
    last_change=frame;last_move=cmd.move;moved=true
  check(moved,"brain can approach and is not inert")
  world.fighters[0].x=2.0
  var first_cross:=-1;var cross_frames:=0
  for frame in range(60):
   var cmd:Dictionary=brain.act(world,DT)
   if brain.intent=="cross_reassess":
    if first_cross<0:first_cross=frame
    cross_frames+=1;check(cmd.move==0,"cross reassessment neutral")
   if frame<13:check(brain.intent!="cross_reassess","no cross response before observation delay")
  check(first_cross>=13 and first_cross<40,"cross response bounded and delayed")
  check(cross_frames>=7,"120ms crossover reconsideration")
  brain.reset()
  check(brain.observed_face==0 and brain.last_projectile_id==-1 and brain.intent=="observe","reset clears intent and threats")
 var null_world=PublicNullWorld.new();var safe_brain=Brain.new()
 for frame in range(60):safe_brain.act(null_world,DT)
 check(safe_brain.snapshots.size()<=16,"null projectile property accepted and bounded")
 for move in ["heavy","roundhouse","kick","special"]:
  var world=Combat.new();var brain=Brain.new();brain.reset()
  for frame in range(30):brain.act(world,DT)
  if move=="special":world.begin_special(world.fighters[1])
  else:world.begin_attack(world.fighters[1],move)
  var id:int=world.fighters[1].attack_id
  world.fighters[0].x=2.0
  for frame in range(30):
   brain.act(world,DT)
   check(world.fighters[1].attack==move and world.fighters[1].attack_id==id,"AI cross observation never mutates committed attack")
 print("P3 INTENT checks=",checks," failures=",failures)
 quit(failures)
