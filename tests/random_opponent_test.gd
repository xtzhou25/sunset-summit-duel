extends SceneTree
const Selection=preload("res://scripts/opponent_selection.gd")
const AI=preload("res://scripts/ai.gd")
var checks:=0
var failures:=0
var distributions:Array=[]
func check(ok:bool,what:String):
 checks+=1
 if not ok: failures+=1;printerr("FAIL ",what)
func _initialize():
 var a=Selection.new();var b=Selection.new();var brain=AI.new()
 var brain_state=brain.rng.state
 seed(12345);var global_expected=randi();seed(12345)
 for player in range(5):
  a.rng.seed=1000+player;b.rng.seed=1000+player
  var counts=[0,0,0,0,0]
  for i in range(20000):
   var got:int=a.begin_match(player)
   check(got>=0 and got<5 and got!=player,"eligible")
   check(got==b.begin_match(player),"seed reproducibility")
   counts[got]+=1
  check(counts[player]==0,"never self")
  for role in range(5):
   if role!=player:check(counts[role]>=4700 and counts[role]<=5300,"frequency within 6% of equal share")
  distributions.append({"player":player,"draws":20000,"counts":counts})
  for opponent in range(5):
   if player==opponent:continue
   var before:int=a.draws;var state=a.rng.state
   for repeat in range(100):check(a.begin_match(player,opponent)==opponent,"manual stable")
   check(a.draws==before and a.rng.state==state,"manual consumes no randomness")
  for invalid in [-10,-1,5,99,player]:
   var before:int=a.draws
   check(a.begin_match(player,invalid)!=player and a.requested==-1 and a.draws==before+1,"invalid/self becomes random")
 check(brain.rng.state==brain_state,"selection cannot consume AI RNG")
 check(randi()==global_expected,"selection cannot consume global RNG")
 var f=FileAccess.open("res://exports/qa-random-audio/random-unit.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"failures":failures,"distributions":distributions,"scope":"100000 seeded draws, mapping/frequency, manual/invalid cases and RNG isolation"},"  "))
 f.close();print("RANDOM UNIT checks=",checks," failures=",failures);quit(failures)
