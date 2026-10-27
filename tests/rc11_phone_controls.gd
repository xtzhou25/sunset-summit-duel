extends "res://tests/directional_hud_test.gd"
# Reuse actual native touch/mouse cancellation suite with main attached, all six pairs.
var game
func _initialize():call_deferred("run_tests")
func run_tests():
 game=load("res://main.tscn").instantiate();root.add_child(game);await settle();game.set_physics_process(false);hud=game.hud
 hud.command.connect(func(action:String,pressed:bool):commands.append([action,pressed]))
 for dims in [Vector2i(568,267),Vector2i(375,614)]:
  root.size=dims;await settle()
  for a in range(3):
   for b in range(3):
    if a==b:continue
    game.show_menu();hud.opponent_choice=b;hud._choose(a);await settle()
    input_tests(str(dims)+" pair "+str([a,b]))
    check(no_holds(),"native controls released")
    game.show_menu()
    check(game.held.is_empty() and game.taps.is_empty(),"menu clears actual main continuous input")
 print("RC11_PHONE_CONTROLS pair_viewports=12 failures=",failures," assertions=",checks)
 game.queue_free();await process_frame;quit(failures)
