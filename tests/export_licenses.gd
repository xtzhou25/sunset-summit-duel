extends SceneTree
func _init():
 var f=FileAccess.open('res://docs/GODOT-LICENSE.txt',FileAccess.WRITE);f.store_string(Engine.get_license_text());f.close()
 f=FileAccess.open('res://docs/ENGINE-THIRD-PARTY.json',FileAccess.WRITE);f.store_string(JSON.stringify({'components':Engine.get_copyright_info(),'licenses':Engine.get_license_info()},'  '));f.close();quit()
