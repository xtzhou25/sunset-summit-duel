extends "res://tests/directional_hud_test.gd"
const Roles=preload("res://scripts/characters.gd")
class QuietOpponent extends RefCounted:
 func reset():pass
 func act(_s,_d):return {}
var game
var cases:Array=[]
func _initialize():call_deferred("run_tests")
func tick(n:=1):
 for i in range(n):game._physics_process(1.0/60.0)
func pad(v:Vector2)->Vector2:return hud._direction_pad.get_global_rect().get_center()+v*hud._direction_pad.size.x*.5
func cleared()->bool:
 for v in game.held.values():
  if bool(v):return false
 return game.taps.is_empty() and hud._joystick_touch_id==-1 and hud._joystick_vector==Vector2.ZERO
func run_tests():
 if not ResourceLoader.exists(Roles.get_character(3).model):
  printerr("BLOCKED: final Tao asset missing; no placeholder acceptance");quit(2);return
 game=load("res://main.tscn").instantiate();root.add_child(game);await settle();game.set_physics_process(false);hud=game.hud
 for dims in [Vector2i(375,614),Vector2i(390,791),Vector2i(568,267),Vector2i(844,337),Vector2i(960,600)]:
  root.size=dims;await settle()
  for a in range(4):
   for b in range(4):
    if a==b:continue
    var prefix=str(dims)+str([a,b])
    game.show_menu();hud.opponent_choice=-1;await settle()
    check(fits(hud._menu_card.get_global_rect(),Rect2(Vector2.ZERO,Vector2(dims))) and card_contents_fit(hud._menu_card),prefix+" menu fits")
    for wanted in range(b+1):tap(hud._opponent_button,91);await settle()
    tap(hud._choice_buttons[a],92);await settle();game.brain=QuietOpponent.new();game.set_physics_process(false);game.render_state(0)
    check(game.playing and [game.sim.fighters[0].kind,game.sim.fighters[1].kind]==[a,b],prefix+" touch starts exact pair")
    check(hud._names[0].text==Roles.get_character(a).name and hud._names[1].text==Roles.get_character(b).name+" AI",prefix+" actual names")
    check(hud._meter_style_kinds==[a,b],prefix+" actual role colors")
    check(game.model_cache.size()<=4 and game.audio_pool.players.size()==10,prefix+" bounded model and sound pools")
    for slot in range(2):
     check(game.actors[slot].get_child(0)==game.model_cache[game.sim.fighters[slot].kind],prefix+" model role in slot"+str(slot))
     check(game.anims[slot].has_animation("FightIdle_R") and game.anims[slot].has_animation("FightIdle_L"),prefix+" real paired model animation")
     check(not game.rifle_props[slot].visible,prefix+" rifle hidden on restart")
    if a==3 or b==3:
     var slot:int=0 if a==3 else 1
     check(game.anims[slot].has_animation("PeachCast_R") and game.anims[slot].has_animation("PeachCast_L"),prefix+" real peach paired cast")
    var x:float=game.sim.fighters[0].x
    touch(1,pad(Vector2(.65,-.65)),true);tick(12)
    check(game.sim.fighters[0].y>.1 and game.sim.fighters[0].x>x,prefix+" diagonal actual jump")
    drag(1,pad(Vector2(-.65,-.65)));tick(20)
    check(game.sim.fighters[0].y>0 and game.sim.fighters[0].vx<0,prefix+" air direction reversal")
    tick(100);check(game.sim.fighters[0].y==0,prefix+" held up no automatic repeated jump")
    touch(2,hud._touch_buttons["punch"].get_global_rect().get_center(),true);tick()
    check(game.sim.fighters[0].attack=="punch" and game.held.get("left",false),prefix+" independent finger punch while moving")
    game.toggle_pause();check(game.paused and cleared(),prefix+" pause clears all sources")
    game.toggle_pause();drag(1,pad(Vector2(0,-.8)));check(game.taps.is_empty(),prefix+" stale drag rejected")
    touch(3,pad(Vector2(0,.8)),true);tick(60);check(game.sim.fighters[0].crouching,prefix+" fresh down crouch")
    root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);check(game.paused and cleared(),prefix+" focus loss clears and pauses")
    if game.paused:game.toggle_pause()
    game.sim.fighters[0].hp=0;game.render_state(0)
    check(hud._health[0].value==0 and not game.rifle_props[0].visible,prefix+" KO health and hidden prop")
    hud.show_result("测试结束");await settle();tap(overlay_button(hud._result_card,"再战一场"),93);await settle()
    check([game.sim.fighters[0].kind,game.sim.fighters[1].kind]==[a,b] and game.sim.fighters[0].hp==100 and game.sim.fighters[1].hp==100,prefix+" actual replay retains pair resets HP")
    check(game.sim.fighters[0].special_cooldown==0 and game.sim.projectiles.is_empty(),prefix+" replay clears special state")
    game.show_menu();await settle()
    check(cleared() and game.sim.projectiles.is_empty() and game.projectile_view.views.is_empty() and game.effects.is_empty(),prefix+" menu clears all transient state")
  cases.append({"viewport":str(dims),"pairs":12})
 check(game.model_cache.size()==4,"four real models cached exactly once")
 var f=FileAccess.open("res://qa-tao/main_controls.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"scope":"actual native main and synthetic viewport touch; explicit quiet-AI fixture; not device/browser"},"  "));f.close()
 print("TAO MAIN CONTROLS QA checks=",checks," failures=",failures);game.queue_free();await process_frame;quit(failures)
