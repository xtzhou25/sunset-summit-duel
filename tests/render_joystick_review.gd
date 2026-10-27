extends Node
# Native, exact-size actual-game SubViewport captures, explicit injected touch events.
const OUT := "res://exports/qa-v12/native-joystick"
var records:Array=[]
func _ready():
 if DisplayServer.get_name()=="headless":print("JOYSTICK_REVIEW_PARSE_OK");get_tree().quit();return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 for dims in [Vector2i(1280,800),Vector2i(568,267),Vector2i(375,614)]:
  var vp:=SubViewport.new();vp.size=dims;vp.own_world_3d=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(vp)
  var game=load("res://main.tscn").instantiate();vp.add_child(game);game.set_physics_process(false);game.auto_demo=false
  await get_tree().process_frame;await get_tree().process_frame
  game.hud.opponent_choice=0;game.hud._choose(2);game.layout_camera();game.render_state(0)
  await get_tree().create_timer(.3).timeout
  var h=game.hud;var center:Vector2=h._direction_pad.get_global_rect().get_center();var radius:float=h._direction_pad.size.x*.5
  await capture(vp,game,dims,"neutral")
  touch(h,10,center,true);drag(h,10,center+Vector2(.8,0)*radius)
  await capture(vp,game,dims,"right")
  drag(h,10,center+Vector2(.7,-.7)*radius)
  await capture(vp,game,dims,"diagonal_up")
  drag(h,10,center+Vector2(0,.8)*radius)
  var attack:Vector2=h._touch_buttons.punch.get_global_rect().get_center();touch(h,11,attack,true)
  await capture(vp,game,dims,"down_plus_punch")
  touch(h,11,attack,false);touch(h,10,center,false)
  await capture(vp,game,dims,"released")
  vp.queue_free();await get_tree().process_frame
 var f=FileAccess.open(OUT+"/manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify({"complete":true,"records":records,"scope":"native actual-game exact SubViewport; injected touch controls; not physical phone/browser"},"  "));f.close()
 print("JOYSTICK_REVIEW_COMPLETE captures=",records.size())
 var label:=Label.new();label.text="JOYSTICK REVIEW COMPLETE / 15 native viewport captures";add_child(label)
func touch(h,index:int,pos:Vector2,pressed:bool):
 var e:=InputEventScreenTouch.new();e.index=index;e.position=pos;e.pressed=pressed;h._input(e)
func drag(h,index:int,pos:Vector2):
 var e:=InputEventScreenDrag.new();e.index=index;e.position=pos;h._input(e)
func capture(vp:SubViewport,game,dims:Vector2i,key:String):
 await get_tree().process_frame;await RenderingServer.frame_post_draw
 var img:Image=vp.get_texture().get_image();var path:String=OUT+"/%dx%d_%s.png"%[dims.x,dims.y,key];var err:int=img.save_png(path)
 records.append({"path":path,"key":key,"requested":str(dims),"actual":str(img.get_size()),"size_matches":img.get_size()==dims,"save_error":err,"vector":str(game.hud._joystick_vector),"actions":game.hud._joystick_actions.duplicate(),"owner":game.hud._joystick_touch_id,"held":game.held.duplicate(),"nub_position":str(game.hud._joystick_nub.position)})
