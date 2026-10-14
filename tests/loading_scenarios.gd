extends SceneTree
var checks := 0
var failures := 0
var loading_visits := 0
var incremental := false
var saw_partial := false
var heartbeat := 0

func _initialize() -> void:
	incremental = "--incremental" in OS.get_cmdline_user_args()
	scene_changed.connect(_scene_changed)
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _scene_changed() -> void:
	if current_scene != null and current_scene.name == "LoadingScene":
		loading_visits += 1
		current_scene.force_incremental_loading = incremental
		check(not root.get_node("GameManager").run_active, "Preparation has not started on loading screen")
		check(not root.get_node("GameManager").launch_from_menu(), "Duplicate launch is blocked while loading")

func wait_for_scene(scene_name: String) -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		heartbeat += 1
		if current_scene == null: continue
		if current_scene.name == "LoadingScene":
			if current_scene.failed:
				check(false, "Loading failed: " + current_scene.status_label.text)
				return false
			if current_scene.progress_bar.value > 0 and current_scene.progress_bar.value < 100: saw_partial = true
		if current_scene.name == scene_name and not root.get_node("SceneTransition").busy:
			await process_frame
			await process_frame
			return true
	check(false, "Timed out waiting for " + scene_name)
	return false

func run() -> void:
	var game = root.get_node("GameManager")
	root.get_node("SceneTransition").duration = 0.0
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await wait_for_scene("MainMenu")
	check(game.launch_from_menu(false), "New game accepted")
	await wait_for_scene("IntroCutscene")
	check(game.finish_intro_cutscene(current_scene), "Intro completion accepted")
	if not await wait_for_scene("Main"):
		quit(1)
		return
	check(loading_visits == 1, "Intro goes through separate loading scene")
	check(game.current_day == 1 and game.run_active, "New game starts day one")
	check(game.tutorial_open and is_equal_approx(game.preparation_remaining, 30), "Loading does not consume preparation/tutorial time")
	check(heartbeat > 5, "Loading yields frames")
	if incremental: check(saw_partial, "Web path exposes intermediate resource progress")
	game.close_tutorial()
	check(game.return_to_menu(), "Return from kitchen accepted")
	await wait_for_scene("MainMenu")
	game.checkpoint_day = 3
	game.run_totals.served = 7
	check(game.launch_from_menu(true), "Continue accepted")
	await wait_for_scene("Main")
	check(loading_visits == 2 and game.current_day == 3, "Continue loads saved day through loading scene")
	check(game.run_totals.served == 7, "Continue preserves session totals")
	game.return_to_menu()
	await wait_for_scene("MainMenu")
	game.state = game.State.GAME_OVER
	game.restart_run()
	await wait_for_scene("Main")
	check(loading_visits == 3 and game.current_day == 1, "Retry loads day one through loading scene")
	check(game.run_totals.served == 0, "Retry resets run totals")
	game.return_to_menu()
	await wait_for_scene("MainMenu")
	game._transition_pending = true
	change_scene_to_file("res://scenes/ui/loading_scene.tscn")
	await wait_for_scene("LoadingScene")
	game._transition_pending = true
	current_scene.target_scene = "res://missing_kitchen_test.tscn"
	current_scene.start_loading()
	for i in 6: await process_frame
	check(current_scene.failed and current_scene.back_button.visible, "Missing target shows recoverable error")
	game.cancel_kitchen_loading(current_scene)
	await wait_for_scene("MainMenu")
	check(not game._transition_pending and game._pending_start_day == 1, "Error return clears loading guard")
	print("Loading checks (%s): %d passed, %d failed" % ["incremental" if incremental else "threaded", checks - failures, failures])
	quit(1 if failures else 0)
