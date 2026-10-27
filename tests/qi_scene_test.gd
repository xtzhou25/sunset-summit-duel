extends SceneTree
const Roles=preload("res://scripts/characters.gd")
var errors:=0
var checks:=0
var game
func check(ok:bool,label:String):
 checks+=1
 if not ok: errors+=1;printerr("FAIL ",label)
func _initialize():call_deferred("run")
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false)
 check(game.audio_pool.assets_ready,"new cue assets ready")
 check(game.audio_pool.players.size()==10,"fixed10pool")
 check(game.audio_pool.cue_streams.has("rifle_emit"),"rifle sound loaded")
 for a in range(3):
  for b in range(3):
   if a==b:continue
   game.start_match(a,b);game.render_state(0);await process_frame
   check(game.sim.fighters[0].kind==a and game.sim.fighters[1].kind==b,"explicit pair")
   check(game.hud._names[0].text==Roles.get_character(a).name,"player name")
   check(game.hud._names[1].text==Roles.get_character(b).name+" AI","opponent name")
   check(game.hud._meter_style_kinds==[a,b],"role color identity")
   for i in range(2):
    check(game.anims[i].has_animation("FightIdle_R"),"paired animation loaded")
    check(not game.rifle_props[i].visible,"gun hidden at restart")
   if a!=2 and b!=2:continue
   var idx:int=0 if a==2 else 1
   for face in [-1,1]:
    game.start_match(a,b)
    var f:Dictionary=game.sim.fighters[idx];f.face=face
    game.sim.begin_special(f)
    for time in [0.0,0.08,0.20,0.40,0.60,0.94,1.0]:
     f.clock=time;f.special_phase_clock=time;game.render_state(0)
     check(game.rifle_props[idx].visible==(time>=0.08 and time<=0.94),"state driven draw interval")
    f.clock=.40;f.special_phase_clock=.40
    var origin:Vector2=game.signature_emitter(idx,.40);game.render_state(0)
    var muzzle:Array=game.rifle_contract.prop_local_muzzle_gltf_xyz
    var actual:Vector3=game.rifle_props[idx].to_global(Vector3(muzzle[0],muzzle[1],muzzle[2]))
    check(origin.distance_to(Vector2(actual.x,actual.y))<.00001,"emitter exactly actual prop muzzle")
    check(absf(origin.y-1.548)<.0001,"muzzle height")
    check(absf(origin.x-(f.x+face*.798))<.0001,"muzzle facing coordinate")
    f.stun=.2;game.render_state(0);check(not game.rifle_props[idx].visible,"hurt hides prop")
    f.stun=0;f.down=true;game.render_state(0);check(not game.rifle_props[idx].visible,"down hides prop")
    f.down=false;f.hp=0;game.render_state(0);check(not game.rifle_props[idx].visible,"KO hides prop")
    game.show_menu();check(not game.rifle_props[idx].visible,"menu clears prop immediately")
 game.hud.opponent_choice=2;game.hud._choose(0);check(game.opponent_selected==2,"opponent UI option used")
 game.hud._choose(2);check(game.opponent_selected==0,"self opponent safely defaults distinct")
 for c in "七步枪单发射击自动对手浅蓝":check(game.hud._ui_font.has_char(c.unicode_at(0)),"glyph "+c)
 print("QI SCENE checks=",checks," failures=",errors)
 game.queue_free();await process_frame;quit(errors)
