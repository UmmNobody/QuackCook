extends SceneTree
var checks := 0
var failures := 0
var reports := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func run() -> void:
	var game = root.get_node("GameManager")
	game.tutorial_seen = true
	game.summary_opened.connect(func(_summary): reports += 1)
	check(game.summary_delay_seconds == 3.0, "Default summary delay is three seconds")
	var room = load("res://scenes/main.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	var summary = room.get_node("UI/DaySummary")
	game.open_kitchen()
	game.spawner.cancel_wave()
	game.spawned_count = game.config.prisoner_count
	game.served_count = game.config.prisoner_count
	check(not game.finish_service().is_empty(), "Valid kitchen close accepted")
	check(game.summary_pending and paused and not summary.screen.visible and reports == 0, "Close pauses gameplay without displaying report immediately")
	check(game.finish_service().is_empty() and not game.next_day(), "Repeated close and early next day are blocked")
	game.confirm_summary()
	game.toggle_pause_menu()
	check(game.summary_pending and not game.pause_menu_open, "Report confirmation and pause menu cannot interrupt closing")
	await create_timer(2.8, true).timeout
	check(not summary.screen.visible and reports == 0, "Report remains hidden before three seconds")
	await create_timer(0.3, true).timeout
	check(summary.screen.visible and reports == 1 and not game.summary_pending, "Report appears once after three seconds")
	check(game.next_day(), "Next day works after delayed report opens")
	game.open_kitchen()
	game.spawner.cancel_wave()
	game.spawned_count = game.config.prisoner_count
	game.finish_service()
	check(game.summary_pending and not summary.screen.visible, "Failed quota also waits before report")
	room.queue_free()
	await process_frame
	await create_timer(3.2, true).timeout
	check(reports == 1 and not game.summary_pending and not paused, "Scene unload cancels pending report and releases pause")
	print("Summary delay checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
