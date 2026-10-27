extends SceneTree
const Combat=preload("res://scripts/combat.gd")
func _init():
 var s=Combat.new();var table=[]
 for kind in range(2):
  for move in ["punch","straight","heavy","roundhouse","kick"]:
   var f:Dictionary=s.fresh(kind,0,1);var row:Dictionary=s.attack_config(f,move).duplicate()
   row.kind=kind;row.move=move;row.total=row.startup+row.active+row.recovery;row.blockstun=0.0;row.block_hitstop=.025
   row.cooldown=0.0;row.cancel="fresh second punch only during final 120ms" if move=="punch" else "none"
   row.effective_reach_note="measured skinned limb curve capped by reach, then hurtbox 0.26m; not full cap at every active frame"
   table.append(row)
  table.append({"kind":kind,"move":"special","total":Combat.MEOW_DURATION if kind==0 else Combat.HEART_START+Combat.HEART_AIR+Combat.HEART_LAND,"emit":Combat.MEOW_EMIT if kind==0 else Combat.HEART_EMIT,"cooldown":Combat.SPECIAL_COOLDOWN,"damage":12,"stun":.26,"guard":28,"push":.24,"projectile_lifetime":Combat.PROJECTILE_LIFETIME,"projectile_speed":Combat.PROJECTILE_SPEED,"blockstun":0,"block_hitstop":.025,"cancel":"none; interruption does not refund cooldown"})
 var f=FileAccess.open("res://docs/P3-MOVE-CONTRACT.json",FileAccess.WRITE);f.store_string(JSON.stringify(table,"  "));f.close();quit()
