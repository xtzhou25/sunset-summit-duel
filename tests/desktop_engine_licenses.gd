extends SceneTree
func _initialize():
 var f=FileAccess.open('res://exports/windows/GODOT-THIRD-PARTY-NOTICES.json',FileAccess.WRITE)
 f.store_string(JSON.stringify({'engine_license':Engine.get_license_text(),'third_party_copyrights':Engine.get_copyright_info(),'third_party_licenses':Engine.get_license_info()},'  '))
 f.close()
 quit()
