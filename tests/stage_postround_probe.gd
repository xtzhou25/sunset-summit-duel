extends SceneTree
const C=preload("res://scripts/combat.gd")
var rows:Array=[]
func _init():
 for kind in range(4):
  for side in [-1.0,1.0]:
   var sim=C.new();sim.reset(4,kind)
   sim.fighters[0].x=-2.9*side;sim.fighters[1].x=2.9*side;sim.fighters[1].hp=1
   sim.fighters[0].face=int(side);sim.fighters[1].face=int(-side)
   sim.step(1.0/60.0,[{"special":true},{}])
   for n in range(180):
    sim.step(1.0/60.0,[{},{}])
    if sim.round_over:break
   var row:={"kind":kind,"side":side,"round_over":sim.round_over,"at_ko_gap":absf(sim.fighters[0].x-sim.fighters[1].x),"at_ko":sim.fighters.duplicate(true),"snapshots":[]}
   var maxgap:=0.0
   for n in range(120):
    sim.step_post_round(1.0/60.0)
    maxgap=maxf(maxgap,absf(sim.fighters[0].x-sim.fighters[1].x))
    if n in [0,9,29,59,119]:row.snapshots.append({"frame":n,"fighters":sim.fighters.duplicate(true)})
   row.maximum_postround_gap=maxgap
   row.final=sim.fighters.duplicate(true);rows.append(row)
 FileAccess.open("res://exports/qa-stage/postround-probe.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
 for row in rows:print("POSTROUND role=",row.kind," side=",row.side," ko=",row.round_over," gap=",row.at_ko_gap," maximum=",row.maximum_postround_gap)
 quit()
