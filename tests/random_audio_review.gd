extends Node
const OUT="res://exports/qa-random-audio"
var game
var failures:Array=[]
var records:Array=[]
var checks:=0
class QuietBrain extends RefCounted:
 var command:Dictionary={}
 func reset():command.clear()
 func act(_s,_d):return command
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _ready():call_deferred("run")
func setup(kind:int):
 game.hud.set_opponent_choice((kind+1)%5);game.hud._choose(kind);game.set_physics_process(false)
 game.brain=QuietBrain.new();game.muted=false;game.audio_pool.configure(1,1,.5,false)
 game.sim.fighters[0].x=-1;game.sim.fighters[1].x=1
 game.render_state(0)
func tick():game._physics_process(1.0/60.0)
func run():
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 get_tree().root.size=Vector2i(960,600)
 game=load("res://main.tscn").instantiate();add_child(game);game.set_physics_process(false)
 await get_tree().process_frame
 game.show_menu()
 await snap("menu-random")
 for kind in range(5):
  for outcome in ["hit","block","miss"]:
   setup(kind)
   if outcome=="block":
    game.sim.fighters[1].x=4.2;game.sim.fighters[0].x=2.2;game.brain.command={"move":1.0}
   game.on_command("special",true);tick();game.on_command("special",false)
   # Move after target lock, before emission; no hit or audio events are injected.
   if outcome=="miss":game.sim.fighters[1].x=-3.6
   var captured:=false
   for n in range(160):
    tick()
    if not captured and game.sim.projectiles.size()>0:
     captured=true
     if outcome=="hit":await snap("role-%d-emission"%kind)
   var counts:Dictionary={}
   for e in game.feedback_history:
    if not e.cue.is_empty():counts[e.cue]=counts.get(e.cue,0)+1
   var emit:String=["meow","heart_emit","rifle_emit","peach_emit","cake_drop"][kind]
   check(counts.get(emit,0)==1,"role %d %s exactly one emission"%[kind,outcome])
   if kind==4:
    check(counts.get("cake_warn",0)==1,"cake startup warning")
    check(counts.get("cake_land",0)==(0 if outcome=="block" else 1),"cake %s only appropriate landing"%outcome)
    check(counts.get("block",0)==(1 if outcome=="block" else 0),"cake contact guard priority")
   if kind in [1,3] and outcome=="hit":check(counts.get("heart_hit" if kind==1 else "peach_hit",0)==1,"dedicated fruit/heart contact")
   check(game.projectile_audio_kinds.is_empty(),"projectile audio ownership cleaned")
   check(game.audio_pool.players.size()==10,"fixed voice pool")
   var before:int=game.audio_pool.counts.requested
   for e in game.sim.events:game.dispatch_feedback(e)
   check(game.audio_pool.counts.requested==before,"stale event batch cannot play twice")
   records.append({"role":kind,"outcome":outcome,"cues":counts})
   game.show_menu();check(game.projectile_audio_kinds.is_empty(),"menu clears ownership")
 # Interrupted startup has warning, but no synthetic drop/landing on cleanup.
 setup(4);game.sim.fighters[0].x=-.35;game.sim.fighters[1].x=.35
 game.brain.command={"punch":true};game.on_command("special",true);tick();game.on_command("special",false)
 for n in range(100):tick()
 var interrupted:Array=[]
 for e in game.feedback_history:
  if e.cue.begins_with("cake_"):interrupted.append(e.cue)
 check(interrupted==["cake_warn"],"interrupted cake cast warns only")
 game.show_menu();await snap("menu-restored")
 var report={"status":"pass" if failures.is_empty() else "fail","checks":checks,"failures":failures,"cases":records,"display":DisplayServer.get_name(),"audio_driver":AudioServer.get_driver_name(),"limits":"No subjective audio acceptance; native screenshots only when real display is available."}
 var f=FileAccess.open(OUT+"/audio-events-"+DisplayServer.get_name()+".json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
 print("RANDOM_AUDIO_REVIEW ",JSON.stringify(report))
 game.queue_free();await get_tree().process_frame
 get_tree().quit(0 if failures.is_empty() else 1)
func snap(label:String):
 if DisplayServer.get_name()=="headless":return
 await get_tree().process_frame
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png(OUT+"/"+label+".png")
