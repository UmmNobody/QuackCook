extends SceneTree
## ทดสอบผ่านปุ่มและ Timeline ของห้องจริง ป้องกันการตรวจผ่านเมื่อเรียก event ภายในตรง ๆ เท่านั้น
var errors: Array[String] = []
var checks = 0
var room: Node3D

func _initialize(): call_deferred("run")

func check(condition: bool, message: String):
	checks += 1
	if not condition:
		errors.append(message)
		push_error(message)

func click(text_value: String):
	for button in room.find_children("*", "Button", true, false):
		if button.text == text_value:
			button.pressed.emit()
			return
	check(false, "Button missing: " + text_value)

func run():
	room = load("res://npc/tests/npc_test.tscn").instantiate()
	root.add_child(room)
	var npc: QuackNpc = room.prisoner
	click("Receive tray")
	for tick in 140: await physics_frame
	check(npc.clip == "P1_Tray_Idle", "Pickup did not enter tray idle")
	var tray = npc.held_tray
	check(tray.global_basis.y.dot(Vector3.UP) > 0.9999, "Held tray is tilted")
	check(tray.global_position.distance_to(npc.global_position + Vector3(0, 0.7, 0.73)) < 0.03, "Tray is not between palms")
	click("Pause / Resume")
	click("Throw tray > fight mode")
	check(not room.paused and npc.playing, "Throw button failed to resume")
	for tick in 60: await physics_frame
	check(not is_instance_valid(npc.held_tray) and not tray.freeze, "Button throw kept tray attached")
	for tick in 180: await physics_frame
	check(tray.global_position.y < 0.1 and tray.global_position.y > -0.03, "Button throw did not land")
	check(npc.clip == "P1_Combat_Idle", "Throw did not enter fight mode")
	# Seek ข้าม release ผ่าน Slider signal ต้องไม่ทิ้งถาด freeze อยู่กับมือ
	room._preview("P1_Tray_Throw")
	tray = npc.held_tray
	await process_frame
	room.timeline.value = 32.0 / 24.0
	check(not is_instance_valid(npc.held_tray) and not tray.freeze, "Timeline seek did not release tray")
	for tick in 180: await physics_frame
	check(tray.global_position.y < 0.1 and tray.global_position.y > -0.03, "Timeline release did not fall")
	room.timeline.value = 4.0 / 24.0
	check(npc.held_tray == tray and tray.freeze, "Timeline rewind did not restore same tray")
	room.timeline.value = 32.0 / 24.0
	check(not is_instance_valid(npc.held_tray) and not tray.freeze, "Second timeline crossing kept tray")
	click("Play full sequence")
	for tick in 2600: await physics_frame
	check(not room.sequence and npc.clip == "P1_Combat_Idle", "Full sequence did not complete")
	check(not is_instance_valid(npc.held_tray), "Full sequence ended holding a tray")
	var report = {"passed": errors.is_empty(), "checks": checks, "errors": errors}
	var file = FileAccess.open("res://npc/tests/ui_validation_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("NPC_UI_VALIDATION ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
