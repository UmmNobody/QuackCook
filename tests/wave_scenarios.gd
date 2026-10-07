extends SceneTree

var room: Node3D
var spawner: Node
var manager: Node
var checks: int = 0
var failures: int = 0
var started: Array[int] = []
var spawned: Array[int] = []
var completed: Array[int] = []
var menu: Array[int] = [FoodItem.Type.CHICKEN, FoodItem.Type.MIXED_VEG, FoodItem.Type.RICE, FoodItem.Type.WATER]

func _initialize() -> void:
	call_deferred("run_checks")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func advance(frames: int) -> void:
	for frame in frames: await physics_frame

func until(predicate: Callable, frames: int = 1500) -> bool:
	for frame in frames:
		if predicate.call(): return true
		await advance(1)
	return false

func run_checks() -> void:
	manager = root.get_node("QueueManager")
	room = load("res://scenes/Queuetest.tscn").instantiate()
	room.start_test_wave_on_ready = false
	spawner = room.get_node("Spawner")
	spawner.patience_seconds = 300
	spawner.spawn_interval = 0.1
	spawner.max_active_prisoners = 2
	check(not spawner.start_wave(6), "Missing setup rejects a wave")
	root.add_child(room)
	current_scene = room
	spawner.wave_started.connect(func(total: int): started.append(total))
	spawner.wave_spawn_finished.connect(func(total: int): spawned.append(total))
	spawner.wave_completed.connect(func(total: int): completed.append(total))
	await advance(90)
	check(manager.active_count() == 0 and not spawner.wave_active, "Spawner stays idle until start_wave is called")
	check(spawner.spawn_one() == null, "Manual spawn cannot bypass a missing wave")
	check(not spawner.start_wave(0) and not spawner.start_wave(-3), "Nonpositive wave sizes are rejected")
	spawner.spawning_paused = true
	check(spawner.start_wave(6), "A six-prisoner wave may exceed the simultaneous cap of two")
	check(not spawner.start_wave(20) and spawner.wave_total == 6, "Overlapping wave cannot overwrite quota")
	await advance(90)
	check(spawner.wave_spawned == 0 and spawner.remaining_to_spawn() == 6, "Pause preserves the entire quota")
	spawner.spawning_paused = false
	check(await until(func(): return spawner.wave_spawned == 2), "Wave automatically admits up to the active limit")
	await advance(180)
	check(spawner.wave_spawned == 2 and spawner.remaining_to_spawn() == 4, "Full active cap delays spawning without consuming quota")
	var exceeded_cap: bool = false
	for frame in 6000:
		room.refill_wells()
		for station in 4:
			var actor = manager.occupant_at_station(station)
			if actor != null and actor.needs_food(menu[station]): manager.request_serve(station)
		if manager.active_count() > 2: exceeded_cap = true
		await advance(1)
		if not spawner.wave_active: break
	check(not exceeded_cap, "All six are processed without exceeding two simultaneous prisoners")
	check(spawner.wave_spawned == 6 and manager.active_count() == 0 and not spawner.wave_active, "Six-person wave finishes through normal serving and departure")
	check(started == [6] and spawned == [6] and completed == [6], "Each lifecycle signal fires once with the requested total")
	check(spawner.spawn_one() == null, "Manual step cannot create a seventh prisoner")
	await advance(180)
	check(manager.active_count() == 0 and started.size() == 1, "No automatic next wave or replacement after completion")

	# All entry markers can fill independently of the active NPC cap.
	spawner.max_active_prisoners = 12
	manager.max_active_prisoners = 12
	spawner.spawning_paused = true
	check(spawner.start_wave(8), "Next wave accepts a different caller-supplied total")
	var chicken_order: Array[int] = [FoodItem.Type.CHICKEN]
	for frame in 2400:
		spawner.spawn_one(chicken_order)
		await advance(1)
		if manager.queued_count() == 6 and not manager.can_spawn(): break
	await advance(180)
	check(spawner.wave_spawned == 6 and spawner.remaining_to_spawn() == 2, "Blocked queue preserves the remaining wave quota")
	check(spawner.spawn_one(chicken_order) == null and spawner.wave_alive_count() == 6, "Failed admission creates no extra tracked prisoner")
	spawner.cancel_wave()
	check(not spawner.wave_active and spawner.remaining_to_spawn() == 0 and manager.active_count() == 6, "Cancel stops pending spawns without deleting existing prisoners")
	manager.reset_queue()
	check(spawner.start_wave(1), "Reset can start a new wave before old queued deletions finish")
	var angry = spawner.spawn_one(chicken_order)
	await advance(3)
	check(spawner.wave_alive_count() == 1 and spawner.wave_active, "Cancelled wave's exit callbacks cannot corrupt the new wave")
	check(spawned == [6, 1] and completed == [6], "Spawn finished is separate from clear and cancellation is not completion")
	check(not spawner.start_wave(2), "New wave rejected while last spawned prisoner is still present")
	angry.patience = 0.01
	check(await until(func(): return not angry.anger_reason.is_empty()), "Last prisoner becomes angry at service position")
	await advance(180)
	check(spawner.wave_active and spawner.wave_alive_count() == 1 and completed == [6], "Angry prisoner leaving the queue does not prematurely clear the wave")
	angry.queue_free()
	await advance(3)
	check(not spawner.wave_active and completed == [6, 1], "Removing the final angry prisoner completes the wave once")
	check(spawner.start_wave(3), "Future day may supply any positive count")
	spawner.cancel_wave()
	spawner.spawning_paused = false
	await advance(90)
	check(manager.active_count() == 0 and completed == [6, 1], "Cancel before first spawn neither spawns nor emits completion")
	room.queue_free()
	await advance(3)
	check(manager.active_count() == 0 and manager.layout_owner == null, "Scene exit still clears the queue autoload")
	print("Wave scenario checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
