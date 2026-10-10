extends SceneTree

const Config = preload("res://scripts/resources/service_wave_config.gd")
const Progression = preload("res://scripts/resources/day_progression.gd")
var game: Node
var queue: Node
var checks: int = 0
var failures: int = 0

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

func capture(filename: String) -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty(): return
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(filename + ".png"))

func run() -> void:
	game = root.get_node("GameManager")
	game.tutorial_seen = true # First-time onboarding is covered by tutorial_scenarios.
	queue = root.get_node("QueueManager")
	var progression = Progression.new()
	var defaults = Config.new()
	var day_one = progression.settings_for_day(defaults, 1)
	var day_three = progression.settings_for_day(defaults, 3)
	var day_five = progression.settings_for_day(defaults, 5)
	var late_day = progression.settings_for_day(defaults, 1000)
	check(day_one.prisoner_count == 6 and day_one.required_successes == 4 and day_one.patience_seconds == 45, "Day one defaults")
	check(day_three.prisoner_count == 10 and day_three.required_successes == 8 and day_three.maximum_foods == 3, "Count, target and food demand grow")
	check(day_five.minimum_foods == 2 and day_five.maximum_foods == 4, "Food demand reaches 2-4")
	check(late_day.minimum_foods == 2 and late_day.maximum_foods == 4 and late_day.patience_seconds == 30, "Endless difficulty respects food caps and patience floor")
	check(defaults.prisoner_count == 6 and defaults.minimum_foods == 1, "Progression does not mutate the original settings")
	progression.extra_successes_per_day = 100
	check(progression.settings_for_day(defaults, 50).is_valid(), "Custom target growth cannot exceed arrivals")
	progression = Progression.new()
	var room = load("res://scenes/main.tscn").instantiate()
	room.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(room)
	current_scene = room
	await advance(3)
	var scene_id: int = room.get_instance_id()
	var player = room.get_node("Actors/Player")
	var head = player.get_node("Head")
	var close_button = room.get_node("Kitchen/Interactables/CloseKitchenButton")
	var summary_ui = room.get_node("UI/DaySummary")
	var spawner = room.get_node("Queue/QueueLayout/Spawner")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(-4.0, 2.2, -4.6), close_button.global_position, 3)
	ray.exclude = [player.get_rid()]
	check(room.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == close_button, "Wall button can be aimed at from inside beside the doorway")
	head.object_focused.emit(close_button)
	check(close_button.outline.visible, "Wall button highlights on focus")
	head.object_focused.emit(null)
	check(not close_button.outline.visible, "Wall highlight clears on focus loss")
	close_button.interact_with(null, head)
	check(game.state == game.State.IDLE and not paused, "Cannot close before opening")
	var settings = Config.new()
	settings.prisoner_count = 3
	settings.required_successes = 2
	settings.minimum_foods = 1
	settings.maximum_foods = 1
	settings.preparation_seconds = 0.25
	check(game.start_run(settings, progression), "Start an endless run")
	check(game.current_day == 1 and game.state == game.State.PREPARING, "Run begins on day one in preparation")
	close_button.interact_with(null, head)
	check(game.state == game.State.SERVING and not paused and game.preparation_remaining == 0, "Wall button opens kitchen before countdown ends")
	check(not game.open_kitchen(), "Repeated opening cannot start a second wave")
	game._process(30.0)
	check(game.state == game.State.SERVING and game.spawned_count == 0, "Old countdown cannot duplicate or end manually opened service")
	await until(func(): return game.state == game.State.SERVING)
	spawner.spawning_paused = true
	check(not game.can_close_kitchen(), "Empty queue cannot close with prisoners still unspawned")
	var order: Array[int] = [FoodItem.Type.WATER]
	var corpse = spawner.spawn_one(order) if queue.actors.is_empty() else queue.actors.values()[0]
	corpse.take_damage(10000, player)
	await advance(4)
	check(game.failed_count == 1, "Unserved unconscious prisoner counted as failed")
	for frame in 2000:
		if queue.can_spawn(): spawner.spawn_one(order)
		for station in 4:
			var actor = queue.occupant_at_station(station)
			if actor != null and actor.needs_food(queue.wells[station].accepted_type):
				queue.wells[station].current_servings = queue.wells[station].capacity
				queue.request_serve(station)
		if game.can_close_kitchen(): break
		await physics_frame
	check(game.served_count == 2 and game.failed_count == 1 and game.can_close_kitchen(), "Completed mixed-outcome day can close with body remaining")
	var pan = room.get_node("Items/Pan")
	head.pick_up(pan)
	head.last_hovered_object = null
	head._handle_interact_pressed()
	head._update_throw_charge(0.4)
	player.take_damage(10)
	var health_before: float = player.health
	var stock: int = queue.wells[3].current_servings
	close_button.interact_with(pan, head)
	check(game.state == game.State.SUMMARY and paused, "Closing opens a paused summary without changing scene")
	check(current_scene.get_instance_id() == scene_id and summary_ui.screen.visible, "Summary overlays the existing kitchen")
	check(summary_ui.served_label.text == "2" and summary_ui.missed_label.text == "1" and summary_ui.target_label.text == "2 / 2", "Report shows served, unserved and quota")
	check(game.last_summary.target_met and summary_ui.continue_button.text.contains("2"), "Successful report offers day two")
	await capture("summary_pass")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not player.can_control() and not head.interaction_allowed(), "Report releases cursor and locks gameplay")
	check(head.carried_object == pan and not head.is_charging, "Opening report preserves held item but cancels charging")
	check(game.finish_service().is_empty(), "Repeated close cannot duplicate a report")
	var frozen_body: Transform3D = corpse.ragdoll.bones[0].global_transform
	var frozen_pan: Transform3D = pan.global_transform
	var frozen_immunity: float = player.invulnerability_remaining
	for i in 15: await process_frame
	check(corpse.ragdoll.bones[0].global_transform.is_equal_approx(frozen_body) and pan.global_transform.is_equal_approx(frozen_pan), "Ragdoll and props stay frozen behind summary")
	check(player.invulnerability_remaining == frozen_immunity, "Gameplay timers freeze behind summary")
	summary_ui.continue_button.pressed.emit()
	check(game.current_day == 2 and game.state == game.State.PREPARING and not paused, "Next-day button resumes into preparation")
	check(not summary_ui.screen.visible and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "Next day hides summary and recaptures mouse on a native display")
	check(current_scene.get_instance_id() == scene_id and is_instance_valid(corpse) and head.carried_object == pan, "Same scene, held object and corpse persist to next day")
	check(queue.wells[3].current_servings == stock and player.health == health_before, "Stock and player HP persist")
	check(game.config.prisoner_count == 5 and game.config.required_successes == 4 and game.config.patience_seconds == 43, "Day two receives tougher settings")
	check(game.spawned_count == 0 and game.served_count == 0 and game.failed_count == 0, "Only daily counters reset")
	check(not game.next_day() and game.current_day == 2, "Repeated next-day activation cannot skip days")
	head.drop_object()
	corpse.queue_free()
	await advance(2)
	check(game.failed_count == 0, "Disposing an old corpse does not count against the new day")
	await until(func(): return game.state == game.State.SERVING)
	spawner.spawning_paused = true
	var angry = spawner.spawn_one(order) if queue.queued_count() == 0 else null
	if angry == null:
		for actor in queue.actors.values():
			if not actor.is_departing(): angry = actor; break
	queue.make_angry(angry, "Daily test")
	for frame in 1000:
		if queue.can_spawn():
			var actor = spawner.spawn_one(order)
			if actor != null: actor.take_damage(10000, player)
		if game.spawned_count == game.config.prisoner_count: break
		await physics_frame
	check(game.spawned_count == 5 and queue.queued_count() == 0, "All day-two arrivals resolved out of queue")
	close_button.interact_with(null, head)
	check(game.state == game.State.SERVING and not game.can_close_kitchen(), "Conscious angry prisoner blocks wall button even with empty queue")
	angry.take_damage(10000, player)
	await advance(4)
	close_button.interact_with(null, head)
	check(game.state == game.State.SUMMARY and not game.last_summary.target_met, "Failed day first shows a report")
	check(summary_ui.missed_label.text == "5" and summary_ui.continue_button.text.contains("Game Over"), "Failure report counts every unserved prisoner")
	check(not game.next_day() and game.current_day == 2, "Failed quota cannot advance to another day")
	await capture("summary_fail")
	summary_ui.continue_button.pressed.emit()
	check(await until(func(): return current_scene != null and current_scene.name == "GameOver", 30), "Failure confirmation changes to Game Over scene")
	check(not paused and game.state == game.State.GAME_OVER and game.last_summary.day == 2, "Game Over retains report and unpauses the menu")
	check(queue.layout_owner == null and game.layout == null, "Game Over clears old scene references")
	await capture("game_over")
	current_scene.find_child("Retry", true, false).pressed.emit()
	check(await until(func(): return current_scene != null and current_scene.name == "Main" and game.state == game.State.PREPARING, 60), "Try again loads a fresh playable kitchen")
	check(game.current_day == 1 and game.config.prisoner_count == 6 and game.served_count == 0 and not paused, "Retry resets the run to day one")
	check(current_scene.get_instance_id() != scene_id, "Only restart creates a fresh kitchen")
	var final_scene := current_scene
	final_scene.queue_free()
	await advance(3)
	check(not paused and game.state == game.State.IDLE, "Scene unload leaves no pause or stale run")
	print("Day loop checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
