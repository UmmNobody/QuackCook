extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	var room = load("res://scenes/main.tscn").instantiate()
	room.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(room)
	current_scene = room
	var recovery = room.get_node("ItemRespawner")
	await frames(4)
	var hit = room.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(recovery.respawn_point.global_position, recovery.respawn_point.global_position + Vector3.DOWN * 2, 1))
	check(not hit.is_empty() and absf(hit.position.y - 1.83076) < 0.02, "Marker sits above the central kitchen table")
	for path in ["foods/chicken", "foods/carrot", "foods/cabbage", "foods/rice", "foods/bottle", "cookware/pan", "cookware/pot", "cookware/tray", "tools/knife"]:
		var item = load("res://scenes/items/" + path + ".tscn").instantiate()
		item.position = Vector3(30,-12,30)
		room.add_child(item)
		item.linear_velocity = Vector3(10,-20,5)
		item.angular_velocity = Vector3(5,6,7)
		var id: int = item.get_instance_id()
		await frames(18)
		check(item.position.y > 1.8 and item.position.distance_to(recovery.respawn_point.global_position) < 1.5, path + " returns to the table automatically")
		check(item.get_instance_id() == id, path + " preserves the original item")
		item.queue_free()
		await frames(3)
	var pan = load("res://scenes/items/cookware/pan.tscn").instantiate()
	room.add_child(pan)
	var food = load("res://scenes/items/foods/chicken.tscn").instantiate()
	room.add_child(food)
	food.current_state = FoodItem.State.CUT
	pan.add_food(food)
	food.cook_progress = 1.5
	food.current_state = FoodItem.State.COOKED
	var impact = load("res://scripts/combat/throw_impact.gd").ensure(pan)
	impact.arm(room.get_node("Actors/Player"), 2.0, [pan] as Array[PhysicsBody3D])
	pan.global_position = Vector3(30,-12,30)
	pan.linear_velocity = Vector3(10,-20,5)
	pan.angular_velocity = Vector3(5,6,7)
	check(recovery.recover_item(pan) and pan.linear_velocity == Vector3.ZERO and pan.angular_velocity == Vector3.ZERO, "Recovery immediately clears linear and angular throw momentum")
	await frames(18)
	check(pan.position.y > 1.8 and pan.current_food == food and food.get_parent() == pan.food_snap_point, "Contained food returns together with cookware")
	check(food.current_state == FoodItem.State.COOKED and food.cook_progress == 1.5, "Food state and cooking progress survive recovery")
	check(not impact.armed, "Respawn disarms old thrown-object damage")
	pan.queue_free()
	await frames(3)
	var knife = load("res://scenes/items/tools/knife.tscn").instantiate()
	room.add_child(knife)
	knife.global_position = Vector3(30,-12,30)
	knife.is_stuck = true
	knife.freeze = true
	await frames(18)
	check(knife.position.y > 1.8 and not knife.is_stuck, "Stuck knife below the world is released and recovered")
	knife.queue_free()
	await frames(3)
	var player = room.get_node("Actors/Player")
	var held = room.get_node("Items/Pot")
	player.head.pick_up(held)
	check(not recovery.recover_item(held) and player.head.carried_object == held, "Held items are not teleported out of the hand")
	player.head.drop_object()
	var stove = room.get_node("Kitchen/Stations/Stove")
	stove.place_cookware(held)
	check(not recovery.recover_item(held) and stove.current_cookware == held, "Cookware attached to a stove is left alone")
	var first = load("res://scenes/items/cookware/pan.tscn").instantiate()
	var second = load("res://scenes/items/cookware/pot.tscn").instantiate()
	room.add_child(first)
	room.add_child(second)
	first.global_position = Vector3(30,-12,30)
	second.global_position = Vector3(30,-12,32)
	await frames(32)
	check(first.position.y > 1.8 and second.position.y > 1.8, "Multiple fallen items are recovered in sequence")
	var paused_item = load("res://scenes/items/cookware/tray.tscn").instantiate()
	paused_item.position = Vector3(30,-12,30)
	room.add_child(paused_item)
	paused = true
	for i in 20: await process_frame
	check(paused_item.position.y == -12, "Pause freezes recovery with the rest of gameplay")
	paused = false
	await frames(18)
	check(paused_item.position.y > 1.8, "Recovery continues after unpausing")
	room.queue_free()
	await frames(3)
	print("Item respawn checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
