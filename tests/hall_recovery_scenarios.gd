extends SceneTree
var failures := 0
var checks := 0
var room: Node3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func item_at(position: Vector3) -> RigidBody3D:
	var item = load("res://scenes/items/foods/chicken.tscn").instantiate()
	item.position = position
	# Keep timing probes stationary and separate from furniture and one another.
	item.gravity_scale = 0
	item.collision_layer = 2
	item.collision_mask = 0
	room.add_child(item)
	return item
func run() -> void:
	room = load("res://scenes/main.tscn").instantiate()
	room.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(room)
	current_scene = room
	var recovery = room.get_node("ItemRespawner")
	check(is_equal_approx(recovery.respawn_delay, 5.0), "Default delay is five seconds")
	await frames(6)
	var front := item_at(Vector3(-8, 3, 1))
	var far_left := item_at(Vector3(-15, 3, -12))
	var far_right := item_at(Vector3(-15, 3, 12))
	await frames(280)
	check(front.position.x < -6.5 and far_left.position.x < -6.5 and far_right.position.x < -6.5, "Nothing returns before five seconds")
	check(recovery.recovery_area.overlaps_body(far_left) and recovery.recovery_area.overlaps_body(far_right), "Area covers both far corners of the hall")
	await frames(100)
	check(front.position.x > 0 and far_left.position.x > 0 and far_right.position.x > 0, "All hall items return after delay, staggered safely")
	front.queue_free()
	far_left.queue_free()
	far_right.queue_free()
	await frames(6)
	var returned := item_at(Vector3(-10, 3, 0))
	await frames(180)
	returned.global_position = Vector3(3, 3, 0)
	await frames(160)
	check(returned.global_position.is_equal_approx(Vector3(3, 3, 0)), "Returning to kitchen cancels recovery")
	returned.global_position = Vector3(-10, 3, 0)
	await frames(200)
	check(returned.position.x < -6.5, "Re-entering hall starts a fresh timer")
	returned.queue_free()
	await frames(18)
	check(recovery._pending.is_empty(), "Deleted items are removed from pending timers")
	var held := item_at(Vector3(-10, 3, 0))
	var head = room.get_node("Actors/Player/Head")
	await frames(180)
	head.set_physics_process(false)
	head.set_process(false)
	head.carried_object = held
	await frames(160)
	check(held.position.x < -6.5 and not recovery._pending.has(held.get_instance_id()), "Held items cancel their timer")
	head.carried_object = null
	head.set_physics_process(true)
	head.set_process(true)
	held.queue_free()
	var fallen := item_at(Vector3(30, -12, 30))
	await frames(280)
	check(fallen.position.y < -10, "Fallen objects also wait five seconds")
	await frames(50)
	check(fallen.position.y > 1.8, "Fall protection still returns objects to table")
	fallen.queue_free()
	var paused_item := item_at(Vector3(-10, 3, 0))
	await frames(150)
	paused = true
	for i in 330: await process_frame
	check(paused_item.position.x < -6.5, "Pause freezes the recovery timer")
	paused = false
	await frames(100)
	check(paused_item.position.x < -6.5, "Timer resumes without counting paused time")
	await frames(90)
	check(paused_item.position.x > 0, "Recovery finishes after enough unpaused time")
	paused_item.queue_free()
	var player = room.get_node("Actors/Player")
	player.set_physics_process(false)
	room.get_node("Environment/KitchenShutter").animation_player.seek(2.5, true)
	await frames(3)
	var pose: Transform3D = player.global_transform
	pose.origin = Vector3(-5.4, 3.1, 1.81)
	var collision := KinematicCollision3D.new()
	check(player.test_move(pose, Vector3(-2, 0, 0), collision) and collision.get_collider() == room.get_node("Environment/ServiceWindowPlayerBarrier"), "Player cannot cross the open service window")
	var barrier = room.get_node("Environment/ServiceWindowPlayerBarrier")
	var probe := item_at(Vector3(-5.4, 3, 1.81))
	probe.collision_layer = 1
	probe.collision_mask = 1
	probe.linear_velocity = Vector3(-6, 0, 0)
	await frames(25)
	check(probe.position.x < -6.6, "Thrown items can still pass the player barrier")
	check((barrier.collision_layer & 5) == 0 and barrier.collision_mask == 0, "Barrier does not block the prisoner collision mask")
	var ragdoll = load("res://scenes/characters/player/player_ragdoll.tscn").instantiate()
	for body in ragdoll.find_children("*", "RigidBody3D", true, false):
		check((body.collision_mask & barrier.collision_layer) != 0, "Player ragdoll also collides with barrier")
	ragdoll.free()
	room.queue_free()
	await frames(4)
	print("Hall recovery checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
