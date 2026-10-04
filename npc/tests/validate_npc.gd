extends SceneTree
## รันด้วย --headless --path <project> --script res://npc/tests/validate_npc.gd
## ตรวจ asset, การสลับชุด, อาหาร 4 ช่อง, event โยน และการเดินโดยไม่ต้องเรนเดอร์ภาพ
var errors: Array[String] = []
var checks: int = 0
var max_pose_error: float = 0
var max_mesh_error: float = 0
var mesh_samples_checked: int = 0
var world: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		errors.append(message)
		push_error(message)

func _spawn(path: String) -> QuackNpc:
	var npc: QuackNpc = load(path).instantiate()
	world.add_child(npc)
	npc.set_physics_process(false)
	return npc

## ตรวจผิว Mesh หลัง skin จริง กระดูกถูกตำแหน่งอย่างเดียวไม่พอจับ export offset ที่ผิด
func _skin_bounds(npc: QuackNpc, mesh: MeshInstance3D) -> AABB:
	var result = AABB()
	var first = true
	for surface in mesh.mesh.get_surface_count():
		var arrays = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride = int(weights.size() / vertices.size())
		for i in vertices.size():
			var point = Vector3.ZERO
			for influence in stride:
				var index = i * stride + influence
				if weights[index] == 0: continue
				var bind_id = joints[index]
				var bone_id = mesh.skin.get_bind_bone(bind_id)
				if bone_id < 0: bone_id = npc.skeleton.find_bone(mesh.skin.get_bind_name(bind_id))
				point += (npc.skeleton.get_bone_global_pose(bone_id) * mesh.skin.get_bind_pose(bind_id) * vertices[i]) * weights[index]
			if first:
				result = AABB(point, Vector3.ZERO)
				first = false
			else: result = result.expand(point)
	return result

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_body = StaticBody3D.new()
	world.add_child(floor_body)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(30, 0.1, 30)
	collision.shape = shape
	collision.position.y = -0.05
	floor_body.add_child(collision)
	var npc = _spawn("res://npc/scenes/prisoner.tscn")
	var other = _spawn("res://npc/scenes/prisoner.tscn")
	other.position = Vector3(4, 0, 0)
	var police = _spawn("res://npc/scenes/police.tscn")
	police.position = Vector3(-4, 0, 0)
	_check(npc.skeleton.get_bone_count() == 8, "Prisoner must have 8 bones")
	_check(npc.skeleton.find_bone("tray_anchor") == -1, "Tray bone must be removed")
	_check(npc.animations.size() == 13, "Expected 13 prisoner clips")
	_check(police.animations.size() == 2, "Expected 2 police dances only")
	var samples: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://npc/assets/blender_samples.json"))
	for name_key in samples:
		npc.play_clip(name_key)
		var info: Dictionary = npc.animations[name_key]
		_check(absf(npc.player.get_animation(name_key).length - (info.export_end - 1.0) / 24.0) < 0.0001, "Wrong length " + name_key)
		for sample in samples[name_key]:
			npc.apply_pose(sample.time)
			for bone_name in sample.bones:
				var expected = Vector3(sample.bones[bone_name][0], sample.bones[bone_name][1], sample.bones[bone_name][2])
				var actual = npc.skeleton.get_bone_global_pose(npc.skeleton.find_bone(bone_name)).origin
				var error = actual.distance_to(expected)
				max_pose_error = maxf(max_pose_error, error)
				_check(error < 0.0001, "Pose differs: %s / %s / %s" % [name_key, bone_name, sample.time])
	# เทียบมือ/เท้า/ใบหน้าจริง และตรวจทั้งตำแหน่งกับการหมุนของถาดเทียบต้นฉบับ Blender
	var mesh_reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://npc/assets/blender_mesh_reference.json"))
	for name_key in mesh_reference:
		npc.play_clip(name_key)
		for sample in mesh_reference[name_key]:
			npc.apply_pose(sample.time)
			for mesh_name in sample.bounds:
				var actual = _skin_bounds(npc, npc.model.find_child(mesh_name, true, false))
				var expected: Array = sample.bounds[mesh_name]
				var error = maxf(actual.position.distance_to(npc._vec(expected[0])), actual.end.distance_to(npc._vec(expected[1])))
				max_mesh_error = maxf(max_mesh_error, error)
				mesh_samples_checked += 1
				_check(error < 0.0001, "Mesh differs: %s / %s / %.3fs / %.6fm" % [name_key, mesh_name, sample.time, error])
			if sample.has("tray_columns"):
				var columns: Array = sample.tray_columns
				var expected_tray = Transform3D(Basis(npc._vec(columns[0]), npc._vec(columns[1]), npc._vec(columns[2])), npc._vec(columns[3]))
				_check(npc.hold_point.global_transform.is_equal_approx(expected_tray), "Tray position/rotation differs from Blender: %s / %.3fs" % [name_key, sample.time])
	# อุปกรณ์ของคนหนึ่งต้องไม่เปลี่ยนคนอื่น แม้ใช้ GLB เดียวกัน
	other.set_appearance(2)
	for style in 6:
		npc.set_appearance(style)
		var visible_count = 0
		for accessory_name in npc.metadata.appearances.slice(1):
			if npc.model.find_child(accessory_name, true, false).visible: visible_count += 1
		_check(visible_count == (0 if style == 0 else 1), "Appearance visibility " + str(style))
		_check(other.model.find_child("Hair_Black", true, false).visible, "Appearance leaked between instances")
	for name_key in ["Police_Dance_01", "Police_Dance_02"]:
		police.play_clip(name_key)
		var animation = police.player.get_animation(name_key)
		_check(animation.loop_mode == Animation.LOOP_LINEAR, "Police dance must loop")
		police.apply_pose(0)
		var first: Array[Transform3D] = []
		for i in 8: first.append(police.skeleton.get_bone_global_pose(i))
		police.apply_pose(animation.length)
		for i in 8:
			_check(first[i].is_equal_approx(police.skeleton.get_bone_global_pose(i)), "Police loop seam")
	# มือขึ้น/ลงตรงจังหวะรับและเปลี่ยนโหมด
	npc.play_clip("P1_Tray_Pickup")
	npc.apply_pose(0)
	_check(npc.hand_mode == 0, "Pickup starts without hands")
	npc.apply_pose(4.0 / 24.0)
	_check(npc.hand_mode == 1, "Open hands must appear at frame 5")
	npc.play_clip("P1_Combat_Enter")
	npc.apply_pose(0)
	_check(npc.hand_mode == 0, "Combat enter starts without hands")
	npc.apply_pose(2.0 / 24.0)
	_check(npc.hand_mode == 2, "Fists must appear at frame 3")
	# ทดสอบอาหารด้วย Node3D ว่าง ไม่สร้างโมเดลอาหารจริง
	npc.pickup_tray()
	var tray = npc.held_tray
	_check(tray.slots.size() == 4, "Expected four food slots")
	var foods: Array[Node3D] = []
	for i in 4:
		var food = Node3D.new()
		food.name = "TestFood%d" % i
		world.add_child(food)
		foods.append(food)
		_check(npc.receive_food(food), "Insert food slot " + str(i))
		_check(food.get_parent() == tray.slots[i], "Food attached to wrong slot")
	var fifth = Node3D.new()
	world.add_child(fifth)
	_check(not npc.receive_food(fifth), "Fifth food must be rejected")
	_check(not npc.receive_food(foods[0]), "Duplicate food must be rejected")
	var tray_id = tray.get_instance_id()
	npc.begin_combat()
	npc.apply_pose(QuackNpc.RELEASE_TIME)
	var release_pose = npc.hold_point.global_transform
	var release_count = [0]
	npc.tray_released.connect(func(_tray): release_count[0] += 1)
	npc._events_between(0, QuackNpc.RELEASE_TIME + 0.01)
	_check(not is_instance_valid(npc.held_tray), "Tray still equipped after release")
	_check(tray.get_instance_id() == tray_id and tray.occupied_count() == 4, "Throw must preserve tray instance and contents")
	_check(tray.global_transform.is_equal_approx(release_pose), "Tray jumps at release")
	npc._events_between(0, 1)
	_check(release_count[0] == 1, "Release event repeated")
	for i in 240: await physics_frame
	_check(tray.position.y > -0.05 and tray.position.y < 0.4, "Thrown tray did not land")
	_check(tray.occupied_count() == 4, "Food disappeared during flight")
	var removed = tray.remove_item(0)
	_check(removed == foods[0] and removed.get_parent() == world, "Remove slot failed")
	_check(tray.occupied_count() == 3, "Slot count after removal")
	# เดินมีระยะเคลื่อนจริง ส่วนต่อยยืนต้องไม่เคลื่อนในแนวราบ
	npc.auto_return_to_idle = true
	npc.end_combat()
	npc.walk_to(Vector3(0, 0, 0.5))
	npc.set_physics_process(true)
	for i in 100: await physics_frame
	_check(npc.position.z > 0.3 and not npc.walking, "Walk-to destination failed")
	npc.request_attack("P1_Kick_Front_R")
	var before = npc.position
	for i in 20: await physics_frame
	_check(Vector2(npc.position.x - before.x, npc.position.z - before.z).length() < 0.001, "Standing attack moved horizontally")
	npc.set_physics_process(false)
	# ตรวจการคืนสถานะและท่าเดินต่อยจาก AI target โดยไม่แก้ HP ของใคร
	npc.begin_combat(other)
	npc.play_clip("P1_Combat_Idle")
	npc._update_combat()
	_check(npc.clip == "P1_Combat_Walk_Punch" and npc.walking, "Chase walk-punch failed")
	other.position = npc.position + Vector3(0, 0, 0.7)
	npc._update_combat()
	_check(npc.clip in QuackNpc.ATTACKS and not npc.walking, "Close-range standing attack failed")
	var report = {"passed": errors.is_empty(), "checks": checks, "max_bone_error_m": max_pose_error, "mesh_samples_checked": mesh_samples_checked, "max_mesh_error_m": max_mesh_error, "errors": errors, "engine": Engine.get_version_info().string}
	var output = FileAccess.open("res://npc/tests/validation_report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("NPC_VALIDATION ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
