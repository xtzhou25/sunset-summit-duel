extends "res://tests/symmetric_matchup_audit.gd"
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame;game.set_physics_process(false)
 for role in range(3):
  game.start_match(role);game.set_physics_process(false)
  for face in [-1,1]:
   var f:Dictionary=game.sim.fighters[0];f.x=0;f.y=0;f.face=face;f.special_face=face
   offsets[str(role)+":"+str(face)]=game.signature_emitter(0,Roles.get_character(role).special_emit)
 var results:Array=[]
 for mode in range(2):
  for seed_id in range(24):
   for swap in range(2):
    var left:int=1 if swap==0 else 2;var right:int=2 if swap==0 else 1
    var one:Dictionary=play(left,right,1,2,seed_id,mode==0,mode==1)
    check(one==play(left,right,1,2,seed_id,mode==0,mode==1),"diagnostic exact repeat")
    results.append(one)
  print("DONE DIAGNOSTIC mode",mode)
 var data={"method":"QA-only: reverse fixed RNG stream assignments; separately suppress both special commands (changes policy opportunities, not a perfect causal isolation). No runtime edits.","rounds":results,"checks":checks,"failures":failures}
 var file=FileAccess.open("res://exports/qa-matchup/symmetric-diagnostics.json",FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
 print("DIAGNOSTIC rounds=",results.size()," repeats=",results.size()," checks=",checks," failures=",failures)
 game.queue_free();await process_frame;quit(failures)
