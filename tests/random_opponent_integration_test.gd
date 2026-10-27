extends "res://tests/directional_hud_test.gd"
const Selection=preload("res://scripts/opponent_selection.gd")
var game
var evidence:Array=[]
func _initialize():call_deferred("run_tests")
func mouse_activate(button:Button):
 var point:=button.get_global_rect().get_center();mouse(point,true);mouse(point,false)
func run_tests():
 game=load("res://main.tscn").instantiate();root.add_child(game);game.set_physics_process(false);await settle();hud=game.hud
 check(hud.opponent_choice==-1 and hud._opponent_button.text.begins_with("对手：随机"),"initial random label")
 var expected=Selection.new();expected.rng.seed=51926;game.opponent_selection.rng.seed=51926
 for dims in [Vector2i(375,614),Vector2i(568,267),Vector2i(960,600)]:
  root.size=dims;await settle()
  for player in range(5):
   game.show_menu();hud.set_opponent_choice(-1);await settle()
   var draw_before:int=game.opponent_selection.draws
   for frame in range(12):game.render_state(0)
   check(game.opponent_selection.draws==draw_before,"menu renders do not draw")
   if player%2==0:tap(hud._choice_buttons[player],80)
   else:mouse_activate(hud._choice_buttons[player])
   await settle()
   var opponent:int=expected.begin_match(player)
   check(game.playing and game.selected==player and game.opponent_selected==opponent,"real touch/mouse selected expected random pair")
   check(game.opponent_selection.draws==draw_before+1,"one draw per match")
   game.render_state(0)
   check(hud._names[1].text==str(game.Characters.get_character(opponent).name)+" AI","resolved identity shown")
   var ai_state=game.brain.rng.state
   var key:=InputEventKey.new();key.physical_keycode=KEY_D;key.keycode=KEY_D;key.pressed=true;root.push_input(key,true)
   check(game.held.get("right",false),"combat keyboard direction still accepted")
   key=InputEventKey.new();key.physical_keycode=KEY_D;key.keycode=KEY_D;key.pressed=false;root.push_input(key,true)
   check(not game.held.get("right",false),"combat keyboard direction release")
   for frame in range(12):game.render_state(0)
   check(game.opponent_selection.draws==draw_before+1 and game.brain.rng.state==ai_state,"render no opponent or AI randomness")
   for round_index in range(3):
    game.round_delay=.001;game.hitstop=0;game.status_text="平局 · 本回合重赛" if round_index==2 else "你拿下一局！"
    game.wins=[0,0];game._physics_process(1.0/60.0)
    check(game.round_delay<=0 and game.opponent_selected==opponent and game.sim.fighters[1].kind==opponent,"round and tied round retain resolved opponent")
    check(game.opponent_selection.draws==draw_before+1,"no round draw")
   hud.show_result("测试");await settle();tap(overlay_button(hud._result_card,"再战一场"),81);await settle()
   opponent=expected.begin_match(player)
   check(game.opponent_selected==opponent and game.opponent_selection.draws==draw_before+2,"real replay random draws exactly once")
   game.show_menu();await settle()
   check(hud._opponent_button.text.begins_with("对手：随机") and game.opponent_selection.draws==draw_before+2,"menu restores random label without draw")
   var manual:int=(player+2)%5
   for cycle in range(manual+1):tap(hud._opponent_button,82);await settle()
   check(hud._opponent_button.text.begins_with("对手："+str(game.Characters.get_character(manual).name)),"manual label through touch cycling")
   tap(hud._choice_buttons[player],83);await settle()
   check(game.opponent_selected==manual and game.opponent_selection.draws==draw_before+2,"manual pair without draw")
   hud.show_result("测试");await settle();mouse_activate(overlay_button(hud._result_card,"再战一场"));await settle()
   check(game.opponent_selected==manual and game.opponent_selection.draws==draw_before+2,"mouse manual replay stable")
   game.show_menu();await settle();tap(hud._choice_buttons[manual],84);await settle()
   opponent=expected.begin_match(manual)
   check(game.selected==manual and game.opponent_selected==opponent and hud.opponent_choice==-1,"changing player to manual opponent invalidates self to random")
   check(hud._opponent_button.text.begins_with("对手：随机") and game.opponent_selection.draws==draw_before+3,"invalid self updates mode and single draw")
   evidence.append({"viewport":str(dims),"player":player,"manual":manual,"final_random":opponent})
 var f=FileAccess.open("res://exports/qa-random-audio/random-integration.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":evidence,"scope":"real main/HUD with synthetic native viewport touch/mouse and combat keyboard; not graphical/device acceptance"},"  "))
 print("RANDOM INTEGRATION checks=",checks," failures=",failures)
 f.close();expected=null;game.audio_pool.suspend(true);await create_timer(.15).timeout;game.queue_free();game=null;hud=null;await settle();quit(failures)
