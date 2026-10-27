extends SceneTree
var game
var failures := 0
var checks := 0
func _initialize():
 call_deferred("run")
func check(ok:bool, label:String):
 checks += 1
 if not ok:
  failures += 1
  printerr("FAIL ",label)
func key(code:int,pressed:bool,alt:bool=false):
 var event:=InputEventKey.new()
 event.physical_keycode=code;event.keycode=code;event.pressed=pressed;event.alt_pressed=alt
 root.push_input(event,true)
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game)
 await process_frame;await process_frame
 game.set_physics_process(false)
 root.size=Vector2i(1280,800)
 await process_frame;await process_frame
 check(game.hud.desktop_controls(),"native desktop detected")
 check(root.min_size==Vector2i(960,600),"desktop minimum window size")
 check(game.hud._keyboard_help.visible,"menu keyboard help visible")
 check(game.hud._keyboard_help.text.contains("F11"),"fullscreen discoverable")
 for kind in range(5):
  game.hud._choose(kind)
  await process_frame
  check(not game.hud._touch_panel.visible,"touch strip hidden")
  check(game.hud._desktop_help.visible,"keyboard strip visible")
  check(is_equal_approx(game.hud.gameplay_height_ratio(),0.935),"52px strip replaces touch region")
  game.hud._set_special_status(kind,2.1)
  check(game.hud._desktop_help.text.contains("2.1s"),"special cooldown visible")
 key(KEY_D,true);check(game.held.get("right",false),"move key down")
 key(KEY_D,false);check(not game.held.get("right",false),"move key release")
 key(KEY_SPACE,true);check(game.taps.get("jump",false),"space jump")
 key(KEY_SPACE,false)
 key(KEY_J,true);check(game.taps.get("punch",false),"punch key")
 key(KEY_J,false)
 key(KEY_ESCAPE,true);key(KEY_ESCAPE,false);check(game.paused,"Esc pauses")
 key(KEY_ESCAPE,true);key(KEY_ESCAPE,false);check(not game.paused,"Esc resumes")
 # Dummy display cannot change actual mode; interception still must not trigger old debug kick/restart.
 var draws:int=game.opponent_selection.draws
 game.screenshot_countdown=0.0
 key(KEY_F11,true);key(KEY_F11,false)
 check(game.screenshot_countdown==0.0 and game.opponent_selection.draws==draws,"F11 no debug combat mutation")
 key(KEY_ENTER,true,true);key(KEY_ENTER,false,true)
 check(game.opponent_selection.draws==draws,"AltEnter no match mutation")
 for dims in [Vector2i(960,600),Vector2i(1280,800),Vector2i(1920,1080)]:
  root.size=dims
  await process_frame;await process_frame;await process_frame
  var label:Label=game.hud._desktop_help
  var measured:Vector2=label.get_theme_font("font").get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_CENTER,label.size.x,label.get_theme_font_size("font_size"))
  check(measured.y<=48.0,"desktop keyboard text fits strip "+str(dims))
 game.show_menu();await process_frame
 check(not game.hud._desktop_help.visible,"menu hides fight strip")
 print("DESKTOP_UI checks=",checks," failures=",failures," display=",DisplayServer.get_name())
 game.audio_pool.suspend(true);await create_timer(0.2).timeout
 game.queue_free();game=null;await process_frame;await process_frame
 quit(failures)
