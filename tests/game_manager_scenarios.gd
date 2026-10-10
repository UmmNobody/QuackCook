extends SceneTree

const Config = preload("res://scripts/managers/service_wave_config.gd")
var checks: int = 0
var failures: int = 0
var game: Node
var queue: Node
var room: Node3D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func advance(frames: int) -> void:
	for i in frames: await physics_frame
func until(predicate: Callable, frames: int = 1800) -> bool:
	for i in frames:
		if predicate.call(): return true
		await physics_frame
	return false
func new_config(count: int = 1) -> Resource:
	var config = Config.new()
	config.prisoner_count = count
	config.required_successes = count
	config.preparation_seconds = 0.0
	config.patience_seconds = 300.0
	return config

func run() -> void:
	game = root.get_node("GameManager")
	game.tutorial_seen = true # First-time onboarding is covered by tutorial_scenarios.
	queue = root.get_node("QueueManager")
	check(not game.start_service(Config.new()), "No wave before kitchen registration")
	room = load("res://scenes/main.tscn").instantiate()
	var layout = room.get_node("QueueLayout")
	check(layout.auto_start_run and layout.first_day.prisoner_count == 6 and layout.first_day.preparation_seconds == 30, "Main defaults to one six-person test wave after thirty seconds")
	layout.auto_start_run = false
	root.add_child(room)
	current_scene = room
	await advance(5)
	var player = room.get_node("Player")
	var spawner = layout.get_node("Spawner")
	check(game.layout == layout and queue.layout_owner == layout, "Main registers gameplay queue with both managers")
	check(queue.capacity() == 9 and queue.service_start_index == 5, "Four waiting, one tray and four service markers")
	check(not spawner.use_example_orders and spawner.use_navigation, "Main uses random orders and kitchen navigation")
	var all_empty: bool = true
	for well in queue.wells: all_empty = all_empty and well.current_servings == 0
	check(all_empty, "Main preserves empty food wells; no lab refills")
	for well in queue.wells:
		var button = well.get_node("ServeButton")
		var eye := Vector3(-3.0, 2.35, well.global_position.z)
		var query := PhysicsRayQueryParameters3D.create(eye, button.global_position, 3)
		query.exclude = [player.get_rid()]
		var hit := room.get_world_3d().direct_space_state.intersect_ray(query)
		check(hit.get("collider") == button, "FPS can aim at " + well.name + " serving button without counter obstruction")
		# Aim into the open top, above the serving button and front table rail.
		query.to = well.global_position + Vector3(0, 0.07, 0)
		hit = room.get_world_3d().direct_space_state.intersect_ray(query)
		check(hit.get("collider") == well, "FPS can aim at " + well.name + " to refill food")
	var invalid = new_config()
	invalid.required_successes = 2
	check(not game.start_service(invalid) and game.state == game.State.IDLE, "Impossible goal rejected without starting")
	invalid = new_config()
	invalid.minimum_foods = 4
	invalid.maximum_foods = 1
	check(not game.start_service(invalid), "Invalid food range rejected")
	var config = new_config(6)
	config.preparation_seconds = 0.5
	config.minimum_foods = 1
	config.maximum_foods = 2
	check(game.start_service(config), "GameManager accepts one six-person wave")
	check(not game.start_service(config), "Cannot double-start during preparation")
	config.prisoner_count = 99
	await advance(10)
	check(game.spawned_count == 0 and queue.actors.is_empty(), "No prisoner spawns during preparation")
	check(await until(func(): return game.spawned_count > 0, 60), "Preparation starts Spawner automatically")
	check(game.config.prisoner_count == 6, "Session snapshots its settings")
	check(not game.start_service(config) and not game.can_close_kitchen(), "Active service cannot restart or close early")
	var counts_valid := true
	var geometry_valid := true
	# Exercise real movement through all main-scene stations; only food supply is automated.
	for frame in 5400:
		for actor in queue.actors.values():
			counts_valid = counts_valid and actor.wanted.size() >= 1 and actor.wanted.size() <= 2
			geometry_valid = geometry_valid and actor.global_position.y > 0.6 and actor.global_position.y < 1.0
		for station in 4:
			var actor = queue.occupant_at_station(station)
			var well = queue.wells[station]
			if actor != null and actor.has_serving_tray() and actor.needs_food(well.accepted_type):
				well.current_servings = well.capacity
				well.get_node("ServeButton").interact_with(null, player.get_node("Head"))
		if game.can_close_kitchen(): break
		await physics_frame
	check(game.spawned_count == 6 and spawner.remaining_to_spawn() == 0, "Exactly the requested six prisoners spawn")
	if game.served_count != 6:
		for actor in queue.actors.values(): print("DIAG ", actor.ticket, " pos=", actor.global_position, " state=", actor.state, " slot=", actor.slot_index, " target=", actor.target_index, " destination=", actor.destination, " order=", actor.order_text())
		print("SUMMARY ", game.get_service_summary())
	check(counts_valid, "All randomized orders respect this session's range")
	check(geometry_valid, "Queue markers stay on the actual kitchen floor")
	check(game.served_count == 6 and game.failed_count == 0, "Six prisoners complete service through real main-scene movement")
	check(game.can_close_kitchen(), "Empty queue permits closing after all arrivals")
	var saved_pan = room.get_node("Pan")
	var saved_stock: int = queue.wells[3].current_servings
	var report: Dictionary = game.finish_service()
	check(report.get("target_met", false) and report.get("served") == 6, "Summary contains goal and successful count")
	await advance(300)
	check(game.state == game.State.IDLE and game.spawned_count == 6, "Finishing does not start a new day automatically")
	check(is_instance_valid(saved_pan) and queue.wells[3].current_servings == saved_stock, "Finishing preserves kitchen props and food stock")
	check(await until(func(): return queue.actors.is_empty()), "Successful prisoners reach the main exit and leave")

	check(game.start_service(new_config()), "A later explicit service can reuse the same scene")
	await until(func(): return game.spawned_count == 1)
	var angry = queue.actors.values()[0]
	queue.make_angry(angry, "Integration test")
	check(game.failed_count == 1 and not game.can_close_kitchen(), "Angry prisoner counts as failure and blocks close")
	# Start on the far side of the central island to test the doorway and navigation detour.
	player.global_position = Vector3(4.7, 1.85, 2.6)
	var health_before: float = player.health
	check(await until(func(): return player.health < health_before, 3600), "Angry prisoner enters kitchen and routes around counters to hit player")
	angry.take_damage(10000, player)
	await advance(5)
	check(game.failed_count == 1 and game.served_count == 0, "Anger and incapacitation do not double-count failure")
	check(game.can_close_kitchen(), "An unconscious body does not block the future close-kitchen rule")
	var corpse_id: int = angry.get_instance_id()
	report = game.finish_service()
	check(not report.get("target_met", true), "Failed target is reported without forcing Game Over")
	check(is_instance_valid(angry), "Finish retains the body in the scene")
	check(game.start_service(new_config()), "Old corpse does not block the next explicit wave")
	await until(func(): return game.spawned_count == 1)
	angry.queue_free()
	await advance(3)
	check(game.failed_count == 0 and game.served_count == 0 and not queue.actors.has(corpse_id), "Disposing an old body cannot affect the new session counters")
	room.queue_free()
	await advance(5)
	check(game.layout == null and game.spawner == null and game.state == game.State.IDLE, "Autoload drops scene references and cancels service on unload")
	check(queue.layout_owner == null, "Queue layout also unregisters on unload")
	# The actual F5 boot path must call GameManager once without any test helper.
	room = load("res://scenes/main.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await advance(3)
	check(game.state == game.State.PREPARING and game.config.prisoner_count == 6, "Reload starts exactly one configured preparation")
	room.queue_free()
	await advance(3)
	print("Game manager integration checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
