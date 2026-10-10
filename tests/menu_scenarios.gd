extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var queue: Node

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await process_frame
func until(predicate: Callable, count: int = 100) -> bool:
	for i in count:
		if predicate.call(): return true
		await physics_frame
	return false
func esc() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	release.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(release)
	await frames(2)
func menu_ready() -> bool:
	return current_scene != null and current_scene.name == "MainMenu" and not paused
func kitchen_ready() -> bool:
	return current_scene != null and current_scene.name == "Main" and game.state == game.State.PREPARING
func capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty(): return
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(name + ".png"))

func run() -> void:
	game = root.get_node("GameManager")
	game.tutorial_seen = true # First-time onboarding is covered by tutorial_scenarios.
	queue = root.get_node("QueueManager")
	check(game.checkpoint_day == 0 and not game.has_checkpoint(), "New process starts with no checkpoint")
	if "fresh_process_only" in OS.get_cmdline_user_args():
		print("Fresh process checks: %d passed, %d failed" % [checks - failures, failures])
		quit(failures)
		return
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main_menu.tscn", "F5 opens main menu")
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await frames(2)
	check(menu.home.visible and not menu.confirmation.visible, "Menu starts with only its home panel")
	check(menu.home.find_children("*", "Button", true, false).size() == 1, "Main page has exactly one Start button")
	await capture("main_menu")
	menu.start_button.pressed.emit()
	check(not game.launch_from_menu(false), "Repeated Start cannot load duplicate kitchens")
	check(await until(kitchen_ready), "Start without checkpoint opens kitchen")
	check(game.current_day == 1 and game.checkpoint_day == 1, "New run begins on day one and stores session checkpoint")
	var room = current_scene
	var old_room_id := room.get_instance_id()
	var pause_ui = room.get_node("PauseMenu")
	var player = room.get_node("Player")
	var head = player.get_node("Head")
	var pan = room.get_node("Pan")
	head.pick_up(pan)
	head.last_hovered_object = null
	head._handle_interact_pressed()
	head._update_throw_charge(0.4)
	await esc()
	check(paused and game.pause_menu_open and pause_ui.screen.visible, "Esc opens settings and pauses")
	check(not head.is_charging and head.carried_object == pan, "Pause cancels charged throw without dropping item")
	check(not player.can_control() and not head.interaction_allowed(), "Pause disables movement and interactions")
	check(not game.open_kitchen(), "Paused preparation cannot be opened manually")
	var countdown: float = game.preparation_remaining
	var position_before: Vector3 = pan.global_position
	await frames(15)
	check(game.preparation_remaining == countdown and pan.global_position == position_before, "Preparation and held-item physics freeze")
	check(pause_ui.screen.find_children("*", "Button", true, false).size() == 1, "Settings has only the exit button")
	await capture("pause_menu")
	await esc()
	check(not paused and not game.pause_menu_open and not pause_ui.screen.visible, "Second Esc resumes gameplay")
	check(DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Resume recaptures mouse")
	head.drop_object()
	check(await until(func(): return game.state == game.State.SERVING, 2000), "Countdown continues into service")
	await until(func(): return game.spawned_count > 0)
	await esc()
	var spawned: int = game.spawned_count
	var actor = queue.actors.values()[0]
	var actor_position: Vector3 = actor.global_position
	await frames(15)
	check(game.spawned_count == spawned and actor.global_position == actor_position, "Serving pause freezes spawning and prisoner movement")
	await esc()
	for i in 5000:
		for station in 4:
			var prisoner = queue.occupant_at_station(station)
			if prisoner != null and prisoner.needs_food(queue.wells[station].accepted_type):
				queue.wells[station].current_servings = queue.wells[station].capacity
				queue.request_serve(station)
		if game.can_close_kitchen(): break
		await physics_frame
	check(game.served_count == 6 and game.can_close_kitchen(), "First day completes through the real queue")
	game.finish_service()
	check(game.checkpoint_day == 2 and paused, "Passing day saves next day immediately")
	await esc()
	check(game.pause_menu_open and game.state == game.State.SUMMARY, "Settings can open above daily report")
	check(not game.next_day(), "Settings blocks report actions behind it")
	await esc()
	check(not game.pause_menu_open and paused and room.get_node("DaySummary").screen.visible, "Closing settings returns to report without unpausing world")
	await esc()
	pause_ui.exit_button.pressed.emit()
	check(await until(menu_ready), "Exit from passed report returns to menu")
	check(game.checkpoint_day == 2 and game.layout == null and queue.layout_owner == null, "Checkpoint survives scene unload without scene references")
	menu = current_scene
	menu.start_button.pressed.emit()
	check(menu.confirmation.visible and menu.continue_button.text.contains("2"), "Start asks whether to continue saved day")
	await capture("continue_prompt")
	menu.cancel_button.pressed.emit()
	check(menu.home.visible and not menu.confirmation.visible and game.checkpoint_day == 2, "Cancel leaves checkpoint untouched")
	menu.start_button.pressed.emit()
	menu.continue_button.pressed.emit()
	check(await until(kitchen_ready), "Continue loads a fresh kitchen")
	room = current_scene
	check(room.get_instance_id() != old_room_id and game.current_day == 2, "Resume starts saved day in a new scene")
	check(game.config.prisoner_count == 8 and game.config.required_successes == 6 and game.config.patience_seconds == 43, "Resume uses saved day's difficulty")
	check(game.preparation_remaining > 29 and game.served_count == 0 and game.spawned_count == 0, "Resume resets daily progress and gives full preparation")
	var empty := true
	for well in queue.wells: empty = empty and well.current_servings == 0
	check(empty and room.get_node("Player").health == 100 and room.get_node("Player/Head").carried_object == null, "Resume does not restore stock, HP or held items")
	await esc()
	room.get_node("PauseMenu").exit_button.pressed.emit()
	await until(menu_ready)
	check(game.checkpoint_day == 2, "Leaving during preparation retains current day")
	menu = current_scene
	menu.start_button.pressed.emit()
	menu.continue_button.pressed.emit()
	await until(kitchen_ready)
	game.open_kitchen()
	await until(func(): return game.spawned_count > 0)
	check(game.current_day == 2 and game.state == game.State.SERVING, "Resumed day can enter active service")
	await esc()
	current_scene.get_node("PauseMenu").exit_button.pressed.emit()
	await until(menu_ready)
	check(game.checkpoint_day == 2, "Leaving during active service keeps the same day")
	menu = current_scene
	menu.start_button.pressed.emit()
	menu.new_button.pressed.emit()
	await until(kitchen_ready)
	check(game.current_day == 1 and game.checkpoint_day == 1, "New game replaces old checkpoint with day one")
	room = current_scene
	game.open_kitchen()
	var spawner = room.get_node("QueueLayout/Spawner")
	spawner.spawning_paused = true
	for i in 1000:
		if queue.can_spawn():
			var prisoner = spawner.spawn_one()
			if prisoner != null: prisoner.take_damage(10000)
		if game.can_close_kitchen(): break
		await physics_frame
	game.finish_service()
	check(game.state == game.State.SUMMARY and not game.last_summary.target_met and game.checkpoint_day == 0, "Failed day clears checkpoint before Game Over confirmation")
	await esc()
	room.get_node("PauseMenu").exit_button.pressed.emit()
	await until(menu_ready)
	check(not game.has_checkpoint(), "Exiting a failed report cannot revive the lost run")
	menu = current_scene
	menu.start_button.pressed.emit()
	await until(kitchen_ready)
	check(game.current_day == 1 and not paused, "After failure, Start begins day one directly")
	await esc()
	current_scene.get_node("PauseMenu").exit_button.pressed.emit()
	await until(menu_ready)
	check(game.checkpoint_day == 1, "Checkpoint remains in this process at end of test")
	print("Menu checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
