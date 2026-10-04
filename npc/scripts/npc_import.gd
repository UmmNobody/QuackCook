@tool
extends EditorScenePostImport
## ตั้งค่าเฉพาะโมเดล NPC หลัง import; ไม่แก้ project settings ของทีม

func _post_import(scene: Node) -> Object:
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://npc/assets/animation_manifest.json"))
	var players = scene.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player: AnimationPlayer = players[0]
		for item in manifest:
			if player.has_animation(item.action):
				player.get_animation(item.action).loop_mode = Animation.LOOP_LINEAR if item.loop else Animation.LOOP_NONE
	# ปิดมือและอุปกรณ์ทุกแบบก่อน; แต่ละ NPC เปิดเฉพาะแบบที่ใช้งานตอน spawn
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).begins_with("Hand_") or str(mesh.name).begins_with("Hair_") or mesh.name in ["Blindfold", "Hat_Prisoner"]:
			mesh.visible = false
	return scene

