extends SceneTree
var checks := 0
var failures := 0
var game: Node
var room: Node3D
var shutter: Node
var panel: Node3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func load_room() -> void:
	room = load("res://scenes/main.tscn").instantiate()
	room.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(room)
	current_scene = room
	shutter = room.get_node("Environment/KitchenShutter")
	panel = room.get_node("Environment/QuackCook_Kitchen/Manual_Roller_Shutter_ROOT/Shutter_Rectangular_Panel")
func resolve_wave(spawner: Node) -> void:
	spawner.spawning_paused = true
	while spawner.remaining_to_spawn() > 0:
		var order: Array[int] = [FoodItem.Type.WATER]
		var actor = spawner.spawn_one(order)
		if actor == null: break
		actor.take_damage(10000)
		await frames(2)
	await frames(3)
func run() -> void:
	game = root.get_node("GameManager")
	game.tutorial_seen = true
	load_room()
	await frames(3)
	var closed_pose: Vector3 = panel.position
	check(not shutter.target_open and not shutter.moving and is_zero_approx(shutter.animation_time), "Fresh kitchen starts with shutter closed")
	var config = load("res://scripts/resources/service_wave_config.gd").new()
	config.prisoner_count = 1
	config.required_successes = 0
	config.preparation_seconds = 30.0
	var progression = load("res://scripts/resources/day_progression.gd").new()
	progression.extra_prisoners_per_day = 0
	progression.extra_successes_per_day = 0
	check(game.start_run(config, progression), "Start real day loop")
	var spawner = room.get_node("Queue/QueueLayout/Spawner")
	spawner.spawning_paused = true
	var button = room.get_node("Kitchen/Interactables/CloseKitchenButton")
	var player = room.get_node("Actors/Player")
	await frames(30)
	check(panel.position.is_equal_approx(closed_pose), "Shutter stays closed throughout preparation")
	button.interact_with(null, player.head)
	check(game.state == game.State.SERVING and shutter.target_open, "Manual open button starts shutter opening")
	await frames(65)
	check(panel.position.y > closed_pose.y + 0.1 and shutter.moving, "Imported panel visibly rises during opening")
	var mid_pose: Vector3 = panel.position
	var mid_time: float = shutter.animation_time
	game.toggle_pause_menu()
	await frames(40)
	check(panel.position.is_equal_approx(mid_pose) and shutter.animation_time == mid_time, "Esc pause freezes shutter during service")
	game.toggle_pause_menu()
	await frames(170)
	var opened_pose: Vector3 = panel.position
	check(not shutter.moving and is_equal_approx(shutter.animation_time, shutter.opened_time), "Opening stops at middle of combined clip")
	check(opened_pose.y > closed_pose.y + 1.8, "Panel reaches imported fully open pose")
	await frames(190)
	check(panel.position.is_equal_approx(opened_pose), "Shutter stays open instead of automatically playing closing half")
	button.interact_with(null, player.head)
	check(game.state == game.State.SERVING and shutter.target_open, "Rejected kitchen close leaves shutter open")
	await resolve_wave(spawner)
	check(game.can_close_kitchen(), "Resolved wave allows closing")
	button.interact_with(null, player.head)
	check(game.state == game.State.SUMMARY and paused and not shutter.target_open and shutter.moving, "Closing button starts closing while report pauses gameplay")
	var player_pose: Transform3D = player.global_transform
	await frames(60)
	check(panel.position.y < opened_pose.y - 0.1, "Shutter continues descending behind paused summary")
	check(player.global_transform.is_equal_approx(player_pose), "Player remains frozen while shutter closes")
	await frames(120)
	check(not shutter.moving and panel.position.is_equal_approx(closed_pose), "Shutter finishes fully closed behind report")
	check(game.next_day(), "Advance to next day in same scene")
	spawner.spawning_paused = true
	await frames(10)
	check(game.state == game.State.PREPARING and panel.position.is_equal_approx(closed_pose), "Next day's preparation keeps shutter closed")
	game.preparation_remaining = 0.05
	await frames(180)
	check(game.state == game.State.SERVING and shutter.target_open and panel.position.is_equal_approx(opened_pose), "Countdown expiry opens shutter automatically")
	await resolve_wave(spawner)
	button.interact_with(null, player.head)
	await frames(48)
	var closing_pose: Vector3 = panel.position
	game._first_day.preparation_seconds = 0.0
	check(game.next_day(), "Zero-preparation next day can start while shutter is closing")
	check(panel.position.distance_to(closing_pose) < 0.04 and shutter.target_open, "Early reopen reverses smoothly without snapping")
	await frames(180)
	check(panel.position.is_equal_approx(opened_pose) and not shutter.moving, "Reversal completes at open pose")
	room.queue_free()
	await frames(4)
	load_room()
	await frames(3)
	check(panel.position.is_equal_approx(closed_pose) and not shutter.target_open, "Reloaded kitchen resets shutter closed")
	room.queue_free()
	await frames(3)
	print("Kitchen shutter checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
