extends "res://tests/spacing_capture.gd"
func capture_commands(config:Dictionary,frame:int,_contacted:bool)->void:
 if frame==12 or frame==72:game.on_command("crouch",true)
 if frame==58 or frame==108:game.on_command("crouch",false)
 if frame==90:game.on_command("jump",true)
 if frame==91:game.on_command("jump",false)
func run_spacing_capture()->void:
 capture_viewport=SubViewport.new();capture_viewport.size=Vector2i(960,600)
 capture_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;capture_viewport.own_world_3d=true;root.add_child(capture_viewport)
 game=load("res://main.tscn").instantiate();capture_viewport.add_child(game);game.set_physics_process(false)
 await process_frame
 build_capture_overlay()
 for kind in [0,1]:
  for face in [-1,1]:
   await record_scenario({"id":"crouch-%d-%d"%[kind,face],"kind":kind,"face":face,"gap":1.2,"frames":150,"title":"CROUCH / RELEASE / JUMP CANCEL - %d / %d"%[kind,face]})
 write_capture_json(capture_output+"/telemetry.json",{"kind":"Controlled initial position, real held/released crouch and jump input, not AI match","scenarios":scenario_summaries,"samples":all_samples})
 capture_viewport.queue_free();await process_frame;quit()
