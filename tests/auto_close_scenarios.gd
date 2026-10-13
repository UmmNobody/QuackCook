extends SceneTree
var checks := 0
var failures := 0
var finished := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await process_frame
func run() -> void:
	var game = root.get_node("GameManager")
	game.tutorial_seen = true
	game.set_process(false)
	game.service_finished.connect(func(_report): finished += 1)
	var room = load("res://scenes/main.tscn").instantiate()
	room.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(room)
	current_scene = room
	await frames(4)
	var config = load("res://scripts/resources/service_wave_config.gd").new()
	config.prisoner_count = 1
	config.required_successes = 0
	config.preparation_seconds = 30
	check(game.start_run(config), "Run starts")
	game._process(1)
	check(game.auto_close_remaining < 0, "No close countdown during preparation")
	game.open_kitchen()
	game.spawner.spawning_paused = true
	game._process(20)
	check(game.state == game.State.SERVING and game.auto_close_remaining < 0, "Empty queue does not close before all arrivals")
	var actor = game.spawner.spawn_one([FoodItem.Type.WATER] as Array[int])
	game._process(20)
	check(game.auto_close_remaining < 0, "Queue occupancy prevents countdown")
	actor.anger_reason = "test"
	game._process(20)
	check(game.auto_close_remaining < 0, "Angry prisoner prevents countdown")
	actor.take_damage(10000, room.get_node("Actors/Player"))
	await frames(4)
	check(game.can_close_kitchen(), "Cleared wave can close")
	game._process(0.016)
	check(is_equal_approx(game.auto_close_remaining, 10), "Countdown begins at ten seconds")
	room.get_node("UI/ServiceHUD")._process(0)
	check(room.get_node("UI/ServiceHUD/Status").text.contains("closes in 10 s"), "HUD displays countdown")
	game._process(4)
	game.toggle_pause_menu()
	game._process(50)
	check(is_equal_approx(game.auto_close_remaining, 6), "Pause does not consume countdown")
	game.toggle_pause_menu()
	game._process(5.9)
	check(game.state == game.State.SERVING, "Kitchen remains open before deadline")
	game._process(0.11)
	check(game.state == game.State.SUMMARY and game.summary_pending and finished == 1, "Expiry closes once through existing summary flow")
	check(not room.get_node("UI/DaySummary").screen.visible, "Existing three-second summary delay is preserved")
	game._process(20)
	check(finished == 1, "Repeated ticks cannot close twice")
	await frames(200)
	check(room.get_node("UI/DaySummary").screen.visible, "Summary appears after the closing delay")
	check(game.next_day() and game.auto_close_remaining < 0, "Next day resets countdown")
	game.open_kitchen()
	game.spawner.spawning_paused = true
	# Resolve every arrival in the progressed wave, keeping the normal close gates.
	for i in game.config.prisoner_count:
		var next_actor = game.spawner.spawn_one([FoodItem.Type.WATER] as Array[int])
		next_actor.take_damage(10000, room.get_node("Actors/Player"))
		await frames(3)
	game._process(0.016)
	game._process(2)
	check(game.auto_close_remaining > 0, "Second wave starts a fresh countdown")
	room.get_node("Kitchen/Interactables/CloseKitchenButton").interact_with(null, room.get_node("Actors/Player/Head"))
	check(game.state == game.State.SUMMARY and game.auto_close_remaining < 0 and finished == 2, "Manual wall button closes early and clears timer")
	room.queue_free()
	await frames(4)
	check(game.auto_close_remaining < 0, "Unregister clears countdown")
	print("Auto close checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
