extends Node
## Exact offscreen viewport render independent of editor embedded root size. QA only.
const OUT:="res://exports/qa-idle-native/phone"
var records:Array=[]
var label:Label
func _ready():
 if DisplayServer.get_name()=="headless":print("PHONE_REVIEW_PARSE_OK");get_tree().quit();return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 label=Label.new();add_child(label);label.position=Vector2(12,12);label.text="Rendering exact phone SubViewports..."
 for dims in [Vector2i(568,267),Vector2i(375,614)]:
  var viewport:=SubViewport.new();viewport.name="PhoneViewport";viewport.size=dims;viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
  var game=load("res://main.tscn").instantiate();viewport.add_child(game);game.set_physics_process(false);game.auto_demo=false
  await get_tree().process_frame;await get_tree().process_frame;await get_tree().create_timer(.3).timeout
  game.show_menu();await get_tree().create_timer(.2).timeout;await capture(viewport,dims,"menu")
  for kind in range(5):
   game.hud.opponent_choice=(kind+1)%5;game.hud._choose(kind);game.layout_camera();game.render_state(1.5)
   await get_tree().create_timer(.25).timeout;await capture(viewport,dims,"role_"+str(kind))
  viewport.queue_free();await get_tree().process_frame
 label.text="PHONE REVIEW COMPLETE / exact viewport PNGs="+str(records.size())
 var f=FileAccess.open(OUT+"/manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify({"complete":true,"records":records,"scope":"exact-size SubViewport own_world_3d native rendering; not real device/browser"},"  "));f.close();print("PHONE_REVIEW_COMPLETE captures=",records.size())
func capture(viewport:SubViewport,wanted:Vector2i,key:String):
 await RenderingServer.frame_post_draw
 var image:Image=viewport.get_texture().get_image()
 var path:String=OUT+"/%dx%d_%s.png"%[wanted.x,wanted.y,key]
 var error:int=image.save_png(path)
 records.append({"path":path,"key":key,"requested":str(wanted),"actual_viewport_size":str(viewport.size),"visible_rect":str(viewport.get_visible_rect().size),"image_size":str(image.get_size()),"own_world_3d":viewport.own_world_3d,"size_matches":image.get_size()==wanted and viewport.size==wanted,"save_error":error})
