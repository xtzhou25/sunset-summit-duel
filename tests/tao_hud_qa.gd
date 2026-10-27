extends "res://tests/directional_hud_test.gd"
const Roles=preload("res://scripts/characters.gd")
var cases:Array=[]
func run_tests():
 for dims in [Vector2i(375,614),Vector2i(390,791),Vector2i(568,267),Vector2i(844,337),Vector2i(960,600),Vector2i(1280,800)]:
  root.size=dims;hud.show_menu();await settle()
  check(Roles.COUNT==4 and hud._choice_buttons.size()==4,"four actual choices")
  check(fits(hud._menu_card.get_global_rect(),Rect2(Vector2.ZERO,Vector2(dims))) and card_contents_fit(hud._menu_card),str(dims)+" menu and all contents fit")
  check(hud._choices_grid.columns==(2 if dims.y>dims.x else 4),str(dims)+" responsive menu columns")
  for a in range(4):
   for b in range(4):
    if a==b:continue
    commands.clear();hud.show_menu();hud.opponent_choice=-1;await settle()
    for wanted in range(b+1):
     tap(hud._opponent_button,91);await settle()
     check(hud.opponent_choice==wanted and hud._opponent_button.text.contains(Roles.get_character(wanted).name),"actual opponent cycle "+str(wanted))
    check(label_fits(hud._choice_buttons[a]) and hud._choice_buttons[a].size.x>=44 and hud._choice_buttons[a].size.y>=44,str(dims)+" choice label target "+str(a))
    tap(hud._choice_buttons[a],92);await settle()
    check(chosen==a and hud.opponent_for(a)==b,"touch exact pair "+str([a,b]))
    hud.set_match({"special_kind":a,"special_cd":0.0,"kinds":[a,b],"names":[Roles.get_character(a).name,Roles.get_character(b).name+" AI"]});await settle()
    check(hud._names[0].text==Roles.get_character(a).name and hud._names[1].text==Roles.get_character(b).name+" AI","pair names "+str([a,b]))
    check(hud._meter_style_kinds==[a,b],"pair color styles "+str([a,b]))
    var pad:Rect2=hud._direction_pad.get_global_rect()
    var pos:Vector2=pad.get_center()+Vector2(-.65,-.65)*pad.size.x*.5
    touch(1,pos,true);touch(2,hud._touch_buttons["punch"].get_global_rect().get_center(),true)
    check(held("left") and held("jump") and held("punch") and hud._joystick_touch_id==1,"pair simultaneous joystick punch "+str([a,b]))
    hud.show_menu();await settle()
    check(no_holds() and hud._joystick_touch_id==-1 and hud._joystick_vector==Vector2.ZERO,"menu clears pair controls")
  hud.opponent_choice=3;tap(hud._opponent_button,99);await settle()
  check(hud.opponent_choice==-1 and hud._opponent_button.text.contains("自动"),"cycle back to auto")
  cases.append({"viewport":str(dims),"menu_rect":str(hud._menu_card.get_global_rect()),"columns":hud._choices_grid.columns})
 for c in "桃桃子波":check(hud._ui_font.has_char(c.unicode_at(0)),"glyph "+c)
 var f=FileAccess.open("res://qa-tao/hud.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"scope":"native synthetic viewport touch; not physical device or browser"},"  "));f.close()
 print("TAO HUD QA checks=",checks," failures=",failures);hud.queue_free();await process_frame;quit(failures)
