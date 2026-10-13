extends SceneTree
var checks := 0
var failures := 0
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
	root.get_texture().get_image().save_png("C:/Users/yaima/Documents/test-codex-connect/.quackcook-intro/" + name + ".png")
func run() -> void:
	var game = root.get_node("GameManager")
	root.get_node("SceneTransition").duration = 0.0
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await frames(5)
	current_scene.start_button.pressed.emit()
	check(not game.launch_from_menu(false), "Repeated NewGame cannot launch twice")
	await frames(5)
	var comic = current_scene
	check(comic.name == "IntroCutscene" and not is_instance_valid(game.layout), "NewGame loads separate cutscene before kitchen")
	check(comic._panels.size() == 8 and comic.panel_index == 0, "Eight panels are loaded and first starts automatically")
	check(comic._panels[0].position.y > 0 and comic._panels[0].modulate.a < 1, "Panel enters from below with fade")
	comic.advance()
	check(comic.panel_index == 0 and not comic._animating and comic._panels[0].position.y == 0, "Click during animation settles current panel")
	await frames(30)
	check(not comic._panels[1].visible, "Manual mode waits for reader")
	await shot("first_panel")
	for i in range(1,4):
		comic.advance()
		await frames(30)
	check(comic._panels[0].visible and comic._panels[3].visible and comic._panel_pages[0].visible, "Page one retains all four revealed panels")
	await shot("page1")
	comic.advance()
	await frames(30)
	check(comic.panel_index == 4 and not comic._panel_pages[0].visible and comic._panel_pages[4].visible, "Fifth panel starts second page")
	comic.auto_button.set_pressed(true)
	check(comic.auto_play and comic.panel_index == 4, "Auto button toggles without advancing panel")
	comic._process(3.1)
	check(comic.panel_index == 5, "Auto advances after configured hold")
	comic.auto_button.set_pressed(false)
	await frames(30)
	comic._process(10)
	check(comic.panel_index == 5, "Disabling auto stops timed advances")
	for i in range(2):
		comic.advance()
		await frames(30)
	await shot("page2")
	check(comic.panel_index == 7 and game.preparation_remaining == 0, "Last panel waits; kitchen prep has not started")
	comic.advance()
	comic.finish()
	await frames(15)
	check(current_scene.name == "Main" and game.current_day == 1 and game.tutorial_open, "Normal completion starts day one then tutorial")
	check(is_equal_approx(game.preparation_remaining, 30), "Tutorial preserves full kitchen preparation time")
	game.close_tutorial()
	game.return_to_menu()
	await frames(15)
	game.checkpoint_day = 3
	current_scene.continue_button.pressed.emit()
	await frames(15)
	check(current_scene.name == "Main" and game.current_day == 3, "Continue bypasses intro and resumes saved day")
	game.return_to_menu()
	await frames(15)
	current_scene.start_button.pressed.emit()
	check(current_scene.confirmation.visible, "Existing checkpoint still asks before NewGame")
	current_scene.new_button.pressed.emit()
	await frames(5)
	comic = current_scene
	check(comic.name == "IntroCutscene", "Confirmed NewGame plays intro again")
	comic.skip_button.pressed.emit()
	comic.skip_button.pressed.emit()
	await frames(15)
	check(current_scene.name == "Main" and game.current_day == 1, "Skip during entrance starts day one exactly once")
	game.return_to_menu()
	await frames(15)
	# Fast autoplay on a fresh scene exercises the final auto transition.
	game.launch_from_menu(false)
	await frames(5)
	comic = current_scene
	comic.panel_hold_seconds = 0.5
	comic.slide_seconds = 0.1
	comic.auto_button.set_pressed(true)
	await frames(360)
	check(current_scene.name == "Main" and game.current_day == 1, "Auto play completes all panels and enters game")
	game.return_to_menu()
	await frames(15)
	print("Intro cutscene checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
