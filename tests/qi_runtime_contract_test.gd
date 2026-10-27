extends SceneTree
## Independent actual-main test. Fixtures set positions/defense only; real input,
## simulation clocks, emitted events and clean imported reference poses drive QA.
const DT:=1.0/60.0
const EXPECTED_NAMES:=["因","鱼","七"]
const EXPECTED_COLORS:=[Color("c77dff"),Color("ffe273"),Color("8ccff3")]
class FixtureAI extends RefCounted:
 var command:Dictionary={}
 func reset():command.clear()
 func act(_sim,_delta):return command.duplicate()
var game
var robot:=FixtureAI.new()
var ref_root:Node3D
var ref_anim:AnimationPlayer
var contract:Dictionary
var checks:=0
var failures:=0
var emissions:Array=[]
var seen_events:Dictionary={}
var cases:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",label)
func find_skeleton(n:Node)->Skeleton3D:
 if n is Skeleton3D:return n
 for child in n.get_children():
  var found:=find_skeleton(child)
  if found:return found
 return null
func find_animation(n:Node)->AnimationPlayer:
 if n is AnimationPlayer:return n
 for child in n.get_children():
  var found:=find_animation(child)
  if found:return found
 return null
func setup(a:int,b:int,face:int,mode:String="hit"):
 game.brain=robot;game.start_match(a,b);game.set_physics_process(false)
 game.auto_demo=false;robot.command={};game.set_feedback_preferences(.85,1,true)
 if game.muted:game.toggle_mute()
 var idx:int=0 if a==2 else 1
 var f:Dictionary=game.sim.fighters[idx];var o:Dictionary=game.sim.fighters[1-idx]
 f.x=-.9*face;o.x=1.1*face;f.face=face;o.face=-face
 if mode=="miss":o.y=8.0;o.vy=0.0 # Explicit high-air spatial miss fixture.
 if mode=="block":set_move(1-idx,float(face))
 game.sim.emitter_provider=observe_emitter;emissions.clear();seen_events.clear();game.render_state(0)
func set_move(index:int,value:float):
 if index==0:
  game.on_command("left",value<0);game.on_command("right",value>0)
 else:robot.command.move=value
func input_special(index:int,pressed:bool):
 if index==0:game.on_command("special",pressed)
 else:robot.command.special=pressed
func tick()->Array:
 var before:float=game.sim.elapsed;game._physics_process(DT)
 var out:Array=[]
 if game.sim.elapsed!=before:
  for e in game.sim.events:
   if not seen_events.has(e.event_id):seen_events[e.event_id]=true;out.append(e.duplicate(true))
 return out
func reference_muzzle(f:Dictionary)->Vector3:
 ref_root.position=Vector3(f.x,0,0);ref_root.rotation.y=f.special_face*PI/2.0
 var side:String="R" if f.special_face>0 else "L"
 ref_anim.stop();ref_anim.play("RifleCast_"+side,0);ref_anim.seek(float(contract.emit_at_s),true);ref_anim.advance(0)
 var sk:=find_skeleton(ref_root);sk.force_update_all_bone_transforms()
 var marker:Dictionary=contract.facing[side].muzzle_marker;var v:Array=marker.offset
 return sk.global_transform*sk.get_bone_global_pose(sk.find_bone(marker.bone))*Vector3(v[0],v[1],v[2])
func observe_emitter(index:int,age:float)->Vector2:
 var origin:Vector2=game.signature_emitter(index,age)
 if game.sim.fighters[index].kind!=2:return origin
 var independent:=reference_muzzle(game.sim.fighters[index])
 emissions.append({"index":index,"age":age,"origin":[origin.x,origin.y],"reference":[independent.x,independent.y,independent.z]})
 check(absf(age-.4)<.000001,"one exact deterministic .40 emission age")
 check(origin.distance_to(Vector2(independent.x,independent.y))<.00001,"origin equals clean separately imported exported-bone reference")
 return origin
func run():
 root.size=Vector2i(960,600)
 contract=JSON.parse_string(FileAccess.get_file_as_string("res://assets/qi_rifle_contract.json"))
 ref_root=Node3D.new();root.add_child(ref_root);var model=load("res://assets/qi.glb").instantiate();model.scale=Vector3.ONE*1.2;ref_root.add_child(model);ref_root.hide();ref_anim=find_animation(model)
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false)
 for a in range(3):
  for b in range(3):
   if a==b:continue
   game.brain=robot;game.start_match(a,b);game.render_state(0)
   check(game.sim.fighters[0].kind==a and game.sim.fighters[1].kind==b,"six explicit ordered pairs")
   for i in range(2):
    var k:int=a if i==0 else b
    check(game.hud._names[i].text==EXPECTED_NAMES[k]+(" AI" if i==1 else ""),"exact role names independent of registry")
    var color:Color=game.hud._health[i].get_theme_stylebox("fill").bg_color
    check(color.is_equal_approx(EXPECTED_COLORS[k]),"actual health fill follows role")
    check(game.model_cache[k].get_parent()==game.actors[i],"right model root attached to role slot")
    check(not game.rifle_props[i].visible,"rifle hidden outside skill")
   if a!=2 and b!=2:continue
   var idx:int=0 if a==2 else 1
   for face in [-1,1]:
    for outcome in ["hit","block","miss"]:
     setup(a,b,face,outcome);input_special(idx,true)
     var spawns:=0;var contacts:=0;var hits:=0;var blocks:=0
     for frame in range(150):
      for e in tick():
       if e.type=="projectile_spawn" and e.kind=="rifle":spawns+=1
       if e.type in ["hit","break","block"] and e.kind=="rifle":
        contacts+=1;hits+=int(e.type=="hit");blocks+=int(e.type=="block")
      if frame==1:input_special(idx,false)
     check(spawns==1 and emissions.size()==1,"single shot per cast "+outcome)
     check(contacts==(0 if outcome=="miss" else 1),"once contact or spatial miss "+outcome)
     check(hits==(1 if outcome=="hit" else 0) and blocks==(1 if outcome=="block" else 0),"correct hit/block/miss result")
     check(game.sim.fighters[1-idx].hp==(88 if outcome=="hit" else 100),"exact12 HP only on unblocked hit")
     check(game.sim.fighters[idx].special_cooldown>0,"cooldown survives completed cast")
     check(not game.rifle_props[idx].visible,"prop hidden at cast completion")
     input_special(idx,true);for frame in range(5):tick()
     check(emissions.size()==1,"no second shot duringCD")
     cases.append({"pair":[a,b],"face":face,"outcome":outcome,"spawn":spawns,"contacts":contacts,"emissions":emissions.duplicate(true)})
 # Active lifecycle checks without injecting animation clocks.
 for face in [-1,1]:
  setup(2,0,face);input_special(0,true)
  for frame in range(15):tick()
  input_special(0,false);check(game.rifle_props[0].visible,"prop drawn before actual fire")
  var before:float=game.sim.fighters[0].clock;var cd:float=game.sim.fighters[0].special_cooldown
  game.toggle_pause();for frame in range(20):tick()
  check(game.sim.fighters[0].clock==before and game.sim.fighters[0].special_cooldown==cd and emissions.is_empty(),"pause freezes cast and no late fire")
  game.toggle_pause();for frame in range(15):tick()
  check(emissions.size()==1,"resume emits exactly once")
  game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);check(game.paused and game.held.is_empty() and game.audio_pool.is_suspended,"background clears/suspends")
  game.show_menu();check(not game.rifle_props[0].visible and not game.rifle_props[1].visible,"menu interruption immediate hidden")
  game.start_match(0,2);check(game.sim.fighters[1].special_cooldown==0 and not game.rifle_props[1].visible,"reselection resets correct role")
 # Real heavy hit before firing interrupts Qi; no private attack clock edits.
 for face in [-1,1]:
  setup(2,0,face);game.sim.fighters[0].x=-.35*face;game.sim.fighters[1].x=.35*face
  robot.command={"heavy":true};for frame in range(9):tick()
  input_special(0,true);for frame in range(80):tick()
  check(emissions.is_empty(),"real incoming heavy cancels before .40 firing")
  check(game.sim.fighters[0].special_cooldown>0,"interrupted skillCD not refunded")
  check(not game.rifle_props[0].visible,"actual interrupted prop hidden")
 # Close-range origin remains at muzzle; projectile overlaps the defender hurtbox.
 for face in [-1,1]:
  setup(2,0,face);game.sim.fighters[0].x=-.35*face;game.sim.fighters[1].x=.35*face
  input_special(0,true)
  for frame in range(100):tick()
  check(emissions.size()==1 and game.sim.fighters[1].hp==88,"close-range actual muzzle shot hits overlapping defender hurtbox")
 # Low HP is a KO fixture; timing and heavy hit still enter through actual native loop.
 setup(2,0,1);game.sim.fighters[0].x=-.35;game.sim.fighters[1].x=.35;game.sim.fighters[0].hp=1
 robot.command={"heavy":true};for frame in range(9):tick()
 input_special(0,true)
 for frame in range(65):tick()
 check(game.sim.round_over and game.sim.fighters[0].hp==0,"real incoming heavy produces KO")
 check(emissions.is_empty() and not game.rifle_props[0].visible,"KO cancels un-emitted rifle and prop")
 robot.command={}
 for frame in range(220):tick()
 check(not game.sim.round_over and game.sim.fighters[0].hp==100,"automatic next round resets HP")
 check([game.sim.fighters[0].kind,game.sim.fighters[1].kind]==[2,0],"next round preserves Qi pairing")
 check(game.sim.projectiles.is_empty() and game.effects.is_empty() and not game.rifle_props[0].visible,"next round clean rifle/effects")
 for c in "七单发射击自动对手":check(game.hud._ui_font.has_char(c.unicode_at(0)),"font glyph "+c)
 var file=FileAccess.open("res://exports/qa-v10/qi-runtime-contract.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"asset_sha256":FileAccess.get_sha256("res://assets/qi.glb"),"scope":"native interface QA, not visual garment/device acceptance","cases":cases},"  "));file.close()
 print("QI_RUNTIME_CONTRACT checks=",checks," failures=",failures," native_cases=",cases.size())
 game.queue_free();ref_root.queue_free();await process_frame;quit(failures)
