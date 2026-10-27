extends "res://tests/directional_hud_test.gd"
var game
func _initialize():call_deferred("run_tests")
func run_tests():
 game=load("res://main.tscn").instantiate();root.add_child(game);await settle();game.set_physics_process(false);hud=game.hud
 for dims in [Vector2i(375,614),Vector2i(390,791),Vector2i(568,267),Vector2i(844,337),Vector2i(960,600)]:
  root.size=dims;await settle()
  for character in range(3):
   game.show_menu();hud.opponent_choice=-1;await settle()
   check(fits(hud._menu_card.get_global_rect(),Rect2(Vector2.ZERO,Vector2(dims))) and card_contents_fit(hud._menu_card),str(dims)+" full trio menu fits")
   check(hud._opponent_button.size.y>=44 and label_fits(hud._opponent_button),str(dims)+" opponent readable target")
   for wanted in range(3):
    tap(hud._opponent_button,91);await settle()
    check(hud.opponent_choice==wanted,"actual touch cycles opponent"+str(wanted))
    check(hud._opponent_button.text.contains(["因","鱼","七"][wanted]),"opponent text correct")
   check(label_fits(hud._choice_buttons[character]),str(dims)+" choice label fits"+str(character))
   tap(hud._choice_buttons[character],92);await settle()
   var expected:int=0 if character==2 else 2
   check(game.playing and game.sim.fighters[0].kind==character and game.sim.fighters[1].kind==expected,"touch chooses role and explicit/different opponent")
   var pair:Array=[character,expected]
   hud.show_result("测试结束");await settle()
   var replay:Button=overlay_button(hud._result_card,"再战一场")
   tap(replay,93);await settle()
   check([game.sim.fighters[0].kind,game.sim.fighters[1].kind]==pair,"actual rematch preserves both role IDs")
   check(game.sim.fighters[0].hp==100 and game.sim.fighters[1].hp==100,"rematch resets HP")
  game.show_menu();hud.opponent_choice=-1;await settle()
  mouse(hud._opponent_button.get_global_rect().get_center(),true);mouse(hud._opponent_button.get_global_rect().get_center(),false);await settle()
  check(hud.opponent_choice==0,"mouse cycles opponent")
  mouse(hud._choice_buttons[2].get_global_rect().get_center(),true);mouse(hud._choice_buttons[2].get_global_rect().get_center(),false);await settle()
  check(game.sim.fighters[0].kind==2 and game.sim.fighters[1].kind==0,"mouse Qi player choice")
 for cycle in range(100):
  var a:int=cycle%3;var b:int=(a+1+cycle%2)%3
  game.start_match(a,b);game.render_state(0.0)
  check(game.model_cache.size()<=3 and game.rifle_props.size()==2,"bounded caches cycle"+str(cycle))
  check(game.audio_pool.players.size()==10,"fixed audio pool")
  check(game.actors[0].get_child_count()==2 and game.actors[1].get_child_count()==2 and game.rifle_props[0]!=game.rifle_props[1],"exactly two actual prop roots and no orphan actor nodes")
  for i in range(2):
   check(game.actors[i].get_child(0)==game.model_cache[game.sim.fighters[i].kind],"child0 is selected model")
  hud.show_result("测试结束");await settle();tap(overlay_button(hud._result_card,"再战一场"),94);await settle()
  check([game.sim.fighters[0].kind,game.sim.fighters[1].kind]==[a,b],"100-cycle actual rematch pair")
  game.show_menu();await settle()
  check(game.sim.projectiles.is_empty() and game.projectile_view.views.is_empty() and game.effects.is_empty(),"menu clears projectiles and effects")
  check(not game.rifle_props[0].visible and not game.rifle_props[1].visible,"menu clears prop")
 print("QI CHOICE INPUT checks=",checks," failures=",failures)
 game.queue_free();await process_frame;quit(failures)
