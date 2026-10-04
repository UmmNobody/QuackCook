class_name QuackServingTray
extends RigidBody3D
## ถาดเสิร์ฟของ NPC แยกจาก class Tray (ที่พักอาหาร) ของทีมอย่างสมบูรณ์
## วัตถุอาหารใช้ Node3D ได้เลย จึงยังไม่ผูกกับสูตรอาหารหรือชนิดอาหารของทีม

signal contents_changed(occupied_slots: int)
var slots: Array[Marker3D] = []
var items: Array[Node3D] = [null, null, null, null]
var holder: PhysicsBody3D
var thrown: bool = false

func _ready() -> void:
	mass = 0.35
	continuous_cd = true
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.7
	physics_material_override.bounce = 0.08
	# จุดวางอยู่ใน .tscn เพื่อขยับตำแหน่งช่องใน Editor ได้โดยตรง
	for point in $FoodSlots.get_children(): slots.append(point as Marker3D)

## หยุดฟิสิกส์ระหว่างถือ แต่ถาดยังเป็น object ของฉาก ไม่เป็นส่วนหนึ่งของ mesh ตัวละคร
func equip(npc: PhysicsBody3D) -> void:
	holder = npc
	thrown = false
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	add_collision_exception_with(npc)

## ใช้ถาด instance เดิมตอนโยน ทำให้อาหารทั้ง 4 ช่องไม่หาย
func throw_from(release_pose: Transform3D, velocity: Vector3) -> void:
	global_transform = release_pose
	freeze = false
	sleeping = false
	linear_velocity = velocity
	angular_velocity = Vector3(2.0, 0.5, -3.0)
	thrown = true
	# คง exception กับผู้โยนไว้ ป้องกันชนมือ/ตัวทันทีที่ปล่อย
	holder = null

## index = -1 หมายถึงหาอาหารช่องแรกที่ว่าง; คืน false เมื่อเต็มหรือใส่ซ้ำ
func insert_item(item: Node3D, index: int = -1) -> bool:
	if not is_instance_valid(item) or item in items or item == self: return false
	if index == -1:
		for i in 4:
			if not is_instance_valid(items[i]):
				index = i
				break
	if index < 0 or index >= 4 or is_instance_valid(items[index]): return false
	if item is RigidBody3D:
		# จำค่าฟิสิกส์ไว้คืนเมื่อนำอาหารออกจากถาด
		item.set_meta("npc_tray_physics", [item.collision_layer, item.collision_mask, item.freeze])
		item.freeze = true
		item.collision_layer = 0
		item.collision_mask = 0
	if item.get_parent(): item.reparent(slots[index], false)
	else: slots[index].add_child(item)
	item.transform = Transform3D.IDENTITY
	items[index] = item
	contents_changed.emit(occupied_count())
	return true

func remove_item(index: int) -> Node3D:
	if index < 0 or index >= 4 or not is_instance_valid(items[index]): return null
	var item = items[index]
	items[index] = null
	item.reparent(get_parent(), true)
	if item is RigidBody3D and item.has_meta("npc_tray_physics"):
		var old: Array = item.get_meta("npc_tray_physics")
		item.collision_layer = old[0]
		item.collision_mask = old[1]
		item.freeze = old[2]
		item.remove_meta("npc_tray_physics")
	contents_changed.emit(occupied_count())
	return item

func occupied_count() -> int:
	var count = 0
	for item in items:
		if is_instance_valid(item): count += 1
	return count
