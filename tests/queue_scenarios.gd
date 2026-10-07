extends SceneTree

var room: Node3D
var manager: Node
var checks: int = 0
var failures: int = 0
var order_failed: bool = false

func _initialize() -> void:
	call_deferred("run_checks")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func advance(frames: int) -> void:
	for frame in frames:
		await physics_frame
		if manager and is_instance_valid(manager.layout_owner):
			var queued: Array = []
			for actor in manager.actors.values():
				if is_instance_valid(actor) and not actor.is_departing(): queued.append(actor)
			queued.sort_custom(func(a, b): return a.ticket < b.ticket)
			for i in range(1, queued.size()):
				if queued[i].position.x > queued[i - 1].position.x + 0.05: order_failed = true

func until(predicate: Callable, frames: int = 900) -> bool:
	for frame in frames:
		if predicate.call(): return true
		await advance(1)
	return false

func setup_room() -> void:
	room = load("res://scenes/Queuetest.tscn").instantiate()
	room.get_node("Spawner").spawning_paused = true
	room.get_node("Spawner").patience_seconds = 300.0
	root.add_child(room)
	current_scene = room
	await advance(2)

func fresh(order: Array[int]) -> Node3D:
	room.get_node("Spawner").cancel_wave()
	manager.reset_queue()
	room.refill_wells()
	room.get_node("Spawner").start_wave(12)
	var actor = room.get_node("Spawner").spawn_one(order)
	return actor

func run_checks() -> void:
	manager = root.get_node("QueueManager")
	var tray_scene = load("res://scenes/serving_tray.tscn")
	var tray_a = tray_scene.instantiate()
	var tray_b = tray_scene.instantiate()
	root.add_child(tray_a)
	root.add_child(tray_b)
	var menu: Array[int] = [FoodItem.Type.CHICKEN, FoodItem.Type.MIXED_VEG, FoodItem.Type.RICE, FoodItem.Type.WATER]
	for food in menu:
		check(not tray_a.has_food(food), "New serving tray starts empty")
		check(tray_a.show_food(food) and tray_a.has_food(food), "Each of four served foods reveals its model")
		check(not tray_b.has_food(food), "Tray instances have independent food visibility")
	check(not tray_a.show_food(FoodItem.Type.CARROT), "Unsupported raw ingredient has no tray display")
	tray_a.clear_food()
	for food in menu: check(not tray_a.has_food(food), "Clearing tray hides each food")
	tray_a.free()
	tray_b.free()
	await setup_room()
	check(manager.capacity() == 9 and manager.waiting_count == 4 and manager.service_start_index == 5, "Capacity follows 4 waiting + 1 tray pickup + 4 service markers")
	check(manager.slot_types[manager.tray_pickup_index] == manager.SlotType.TRAY_PICKUP, "Tray pickup has a distinct slot type")
	check(manager.active_count() == 1, "Initial prisoner admitted")
	check(not manager.can_spawn(), "Entry slot occupied prevents spawning")
	var a = manager.actors.values()[0]
	check(not a.has_serving_tray(), "Spawned prisoner does not receive a tray early")
	check(await until(func(): return a.slot_index == manager.tray_pickup_index and not a.is_moving()), "Prisoner stops at pickup marker")
	var pickup_patience: float = a.patience
	await advance(10)
	check(not a.has_serving_tray() and is_equal_approx(a.patience, pickup_patience), "Pickup delay holds the queue without reducing patience")
	check(await until(func(): return manager.occupant_at_station(0) == a), "A reaches chicken")
	check(a.has_serving_tray() and a.serving_tray.get_parent() == a.get_node("TrayHoldPoint"), "Tray is attached to the prisoner before entering food stations")
	for food in menu: check(not a.serving_tray.has_food(food), "Attached tray starts empty")
	var original_tray = a.serving_tray
	a.give_serving_tray()
	check(a.serving_tray == original_tray and a.get_node("TrayHoldPoint").get_child_count() == 1, "Repeated pickup does not duplicate the tray")
	var b = room.get_node("Spawner").spawn_one()
	check(b != null, "B admitted when entry free")
	check(await until(func(): return b.slot_index == manager.tray_pickup_index and not b.is_moving() and b.has_serving_tray()), "B receives a tray and waits while A blocks chicken")
	var b_tray = b.serving_tray
	var entry_patience: float = b.patience
	await advance(120)
	check(is_equal_approx(b.patience, entry_patience), "Entry waiting does not reduce patience")
	check(b.serving_tray == b_tray and b.get_node("TrayHoldPoint").get_child_count() == 1, "Blocked pickup position preserves the same empty tray")
	var stock: int = room.wells[1].current_servings
	check(not manager.request_serve(1) and room.wells[1].current_servings == stock, "No customer: no stock loss")
	room.wells[0].current_servings = 0
	check(not manager.request_serve(0) and a.received.is_empty(), "Empty well does not serve or anger")
	room.refill_wells()
	# Exercise the real 3D button callback, not only the manager API.
	room.wells[0].get_node("ServeButton").interact_with(null, null)
	check(FoodItem.Type.CHICKEN in a.received and room.wells[0].current_servings == 3, "Correct 3D button serves A once")
	check(a.serving_tray.has_food(FoodItem.Type.CHICKEN) and not b.serving_tray.has_food(FoodItem.Type.CHICKEN), "Receiving chicken shows it only on the recipient's tray")
	await advance(1)
	stock = room.wells[0].current_servings
	check(not manager.request_serve(0) and room.wells[0].current_servings == stock, "Moving prisoner cannot receive a serving")
	check(await until(func(): return manager.occupant_at_station(1) == a and manager.occupant_at_station(0) == b), "A at vegetables; B blocked at unwanted chicken")
	check(not b.needs_food(FoodItem.Type.CHICKEN), "B does not want chicken")
	var service_patience: float = b.patience
	await advance(60)
	check(b.patience < service_patience, "Blocked service position reduces patience")
	manager.max_active_prisoners = 2
	check(manager.request_serve(0), "Wrong food is physically served")
	check(b.anger_reason == "Wrong food" and room.wells[0].current_servings == 2, "Wrong food consumes one and causes anger")
	check(b.serving_tray.has_food(FoodItem.Type.CHICKEN) and FoodItem.Type.CHICKEN not in b.received, "Wrong serving is visible but does not fulfill the order")
	check(not manager.can_spawn() and manager.active_count() == 2, "Angry prisoner counts toward alive limit")
	check(manager.occupants[manager.service_start_index] == b, "Angry prisoner holds slot until body clears")
	check(await until(func(): return manager.occupants[manager.service_start_index] == null, 360), "Angry departure frees source after throwing tray, combat entry and clearance")
	check(await until(func(): return b.attacks_made > 0, 900), "Angry prisoner routes around table and attacks player")
	check(room.hit_count > 0, "Prototype attack event reaches HUD")
	manager.max_active_prisoners = 12

	var c = fresh([FoodItem.Type.CHICKEN])
	c.patience = 0.05
	await advance(30)
	check(c.anger_reason.is_empty(), "Low patience does not expire in entry/movement")
	check(await until(func(): return c.anger_reason == "Patience exhausted"), "Patience expires only after service arrival")

	var d = fresh([FoodItem.Type.RICE])
	check(await until(func(): return manager.occupant_at_station(2) == d), "Unwanted empty stations are passed automatically")
	check(manager.request_serve(2) and d.complete(), "Rice-only order completes")
	var leaving_tray = d.serving_tray
	check(leaving_tray.has_food(FoodItem.Type.RICE), "Rice remains visible during departure")
	check(await until(func(): return manager.active_count() == 0), "Completed prisoner exits and releases all slots")
	check(not is_instance_valid(leaving_tray), "Prisoner's tray is freed with its owner")
	check(manager.occupants.all(func(item): return item == null) and manager.reservations.all(func(item): return item == null), "No reservations remain after exit")

	var e = fresh([FoodItem.Type.CHICKEN, FoodItem.Type.WATER])
	check(await until(func(): return manager.occupant_at_station(0) == e), "Repeated food scenario reaches station")
	manager.request_serve(0)
	manager.request_serve(0)
	check(e.anger_reason == "Wrong food", "Duplicate serving is unwanted food")

	var f = fresh(menu)
	var meal_tray: Node3D = null
	for station in 4:
		check(await until(func(): return manager.occupant_at_station(station) == f), "All-food order reaches the next station")
		if station == 0:
			meal_tray = f.serving_tray
			f.serving_tray.queue_free()
			await advance(2)
			var before_missing_tray: int = room.wells[0].current_servings
			check(not manager.request_serve(0) and room.wells[0].current_servings == before_missing_tray, "No tray means no food consumed")
			f.give_serving_tray()
			meal_tray = f.serving_tray
		check(manager.request_serve(station), "All-food order accepts serving")
		for served in range(station + 1): check(meal_tray.has_food(menu[served]), "Previous servings stay visible on the same tray")
	check(f.complete(), "All four foods visible when the order completes")

	room.get_node("Spawner").cancel_wave()
	manager.reset_queue()
	room.get_node("Spawner").start_wave(12)
	room.refill_wells()
	# Fill every position: each prisoner wants chicken, so the queue eventually blocks.
	var chicken_order: Array[int] = [FoodItem.Type.CHICKEN]
	for frame in 2100:
		if manager.can_spawn(): room.get_node("Spawner").spawn_one(chicken_order)
		await advance(1)
		if manager.queued_count() == 6 and not manager.can_spawn(): break
	check(manager.queued_count() == 6 and not manager.can_spawn(), "Blocked head limits admission including the pickup slot")
	room.get_node("Spawner").cancel_wave()
	manager.reset_queue()
	room.get_node("Spawner").start_wave(12)
	var water_order: Array[int] = [FoodItem.Type.WATER]
	for frame in 3000:
		if manager.can_spawn(): room.get_node("Spawner").spawn_one(water_order)
		await advance(1)
		if manager.queued_count() == 9 and not manager.can_spawn(): break
	check(manager.queued_count() == 9 and not manager.can_spawn(), "All 9 markers cap the queue when the head waits at water")
	check(room.get_node("Spawner").spawn_one(water_order) == null and manager.active_count() == 9, "Full queue cannot instantiate a tenth prisoner")
	check(not order_failed, "No overtaking across all simulated frames")
	for i in manager.capacity():
		if manager.occupants[i] != null and manager.reservations[i] != null:
			check(false, "Slot cannot be occupied and reserved by different actors")

	room.queue_free()
	await advance(3)
	check(manager.layout_owner == null and manager.capacity() == 0 and manager.active_count() == 0, "Scene exit clears autoload references")
	check(manager.slot_types.is_empty() and manager.tray_pickup_index == -1, "Scene exit also clears pickup slot data")
	await setup_room()
	check(manager.active_count() == 1 and manager.next_ticket == 2, "Scene reentry starts a fresh queue")
	room.reset_lab()
	await advance(3)
	check(manager.active_count() == 1 and manager.next_ticket == 2, "Reset does not let old actor callbacks erase new actors")
	room.queue_free()
	await advance(3)
	var standalone = load("res://scenes/prefebs/maps/serving_table.tscn").instantiate()
	root.add_child(standalone)
	var well = standalone.get_node("ChickenWell")
	well.current_servings = 2
	well.get_node("ServeButton").interact_with(null, null)
	check(well.current_servings == 1, "Standalone serving table retains its original behavior")
	standalone.queue_free()
	await process_frame
	print("Queue scenario checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
