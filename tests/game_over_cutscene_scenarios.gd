extends SceneTree
var checks := 0
var failures := 0
var game: Node
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/yaima/Documents/test-codex-connect/.quackcook-game-over-comic/" + name + ".png")
func lose_day() -> void:
	game.open_kitchen()
	game.spawner.spawning_paused = true
	for i in game.config.prisoner_count:
		var actor = game.spawner.spawn_one()
		actor.take_damage(10000)
		await frames(3)
	game.finish_service()
	await frames(13)
func run() -> void:
	game = root.get_node("GameManager")
	root.get_node("SceneTransition").duration = 0.0
	game.tutorial_seen = true
	game.summary_delay_seconds = 0
	change_scene_to_file("res://scenes/main.tscn")
	await frames(10)
	await lose_day()
	var comic = current_scene
	check(comic.name == "GameOverCutscene" and game.state == game.State.GAME_OVER, "Failed day automatically opens a dedicated Game Over comic scene")
	check(not is_instance_valid(game.layout) and not paused, "Kitchen is unloaded and cutscene is unpaused")
	check(comic._panels.size() == 6 and comic.panel_index == 0, "Six panels load in sequence")
	check(comic._panels[0].position.y > 0, "First panel slides upward")
	check(not comic.has_node("EndMenu") and not comic.has_node("Hint"), "Options wait until end and no page/click hint is shown")
	check(is_equal_approx(comic.auto_button.modulate.a, 0.35), "Auto off uses faint styling")
	check(not comic.has_node("Retry"), "Retry belongs only to final report")
	comic.advance()
	for i in range(1, 4):
		comic.advance()
		await frames(30)
	check(comic._panel_pages[0].visible and comic._panels[3].visible, "First page keeps all four panels")
	await shot("page1")
	comic.advance()
	await frames(30)
	check(comic.panel_index == 4 and not comic._panel_pages[0].visible, "Fifth panel changes to page two")
	comic.advance()
	await frames(30)
	await shot("page2")
	check(current_scene == comic, "Last panel stays readable until advancing")
	comic.advance()
	await frames(8)
	check(current_scene.name == "RunSummary", "Completion opens separate final report")
	await shot("choices")
	current_scene.get_node("%Retry").pressed.emit()
	current_scene.get_node("%MainMenu").pressed.emit()
	await frames(15)
	check(current_scene.name == "Main" and game.current_day == 1 and game.state == game.State.PREPARING, "Retry starts fresh day one directly and ignores second choice")
	await lose_day()
	comic = current_scene
	comic.slide_seconds = 0.1
	comic.panel_hold_seconds = 0.5
	comic.auto_button.set_pressed(true)
	check(is_equal_approx(comic.auto_button.modulate.a, 1), "Auto on uses full-strength styling")
	await frames(270)
	check(current_scene.name == "RunSummary", "Auto plays all six panels then opens final report")
	current_scene.get_node("%MainMenu").pressed.emit()
	await frames(15)
	check(current_scene.name == "MainMenu" and not game.has_checkpoint(), "Main Menu returns without restoring failed checkpoint")
	game._enter_game_over()
	await frames(8)
	comic = current_scene
	comic.skip_button.pressed.emit()
	comic.skip_button.pressed.emit()
	await frames(8)
	check(current_scene.name == "RunSummary", "Repeated Skip safely opens final report once")
	await frames(5)
	check(current_scene.name == "RunSummary", "Final report waits for explicit choice")
	current_scene.get_node("%MainMenu").pressed.emit()
	await frames(12)
	print("Game Over comic checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
