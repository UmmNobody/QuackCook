extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + message)
func frames(n: int) -> void:
	for i in n: await process_frame
func pointer_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/yaima/Documents/test-codex-connect/.quackcook-main-menu/" + name + ".png")
func run() -> void:
	var game = root.get_node("GameManager")
	game.tutorial_seen = true
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await frames(8)
	var menu = current_scene
	pointer_at(Vector2(root.size.x - 50, 50))
	await create_timer(0.25).timeout
	check(menu.continue_button.disabled, "Continue disabled without a checkpoint")
	check(menu.get_node("Home/Logo").texture.resource_path.ends_with("QuackCookLogoV2.png"), "Uses V2 logo")
	await shot("menu")
	for name in ["Start","Setting","Credit"]:
		var button = menu.get_node("Home/" + name)
		button.grab_focus()
		await create_timer(0.25).timeout
		check(button.visual.scale.is_equal_approx(Vector2(1.2,1.2)) and is_equal_approx(button.visual.position.x,18), name + " highlights at 1.2 scale and right offset")
		if name == "Setting": await shot("hover")
		pointer_at(Vector2(root.size.x - 50, 50))
		button.release_focus()
		await create_timer(0.25).timeout
		check(button.visual.scale.is_equal_approx(Vector2.ONE) and is_zero_approx(button.visual.position.x), name + " restores its position")
	menu.get_node("Home/Setting").pressed.emit()
	menu.get_node("Home/Credit").pressed.emit()
	check(current_scene == menu, "Placeholder buttons do not change scene")
	menu.start_button.pressed.emit()
	await frames(30)
	check(current_scene.name == "IntroCutscene", "NewGame opens the intro")
	current_scene.skip_button.pressed.emit()
	await frames(30)
	check(current_scene.name == "Main" and game.current_day == 1, "NewGame starts day one")
	game.return_to_menu()
	await frames(30)
	menu = current_scene
	check(not menu.continue_button.disabled, "Continue enabled after returning from a run")
	menu.continue_button.grab_focus()
	await create_timer(0.25).timeout
	check(menu.continue_button.visual.scale.is_equal_approx(Vector2(1.2,1.2)), "Continue uses the same hover effect")
	menu.start_button.pressed.emit()
	check(menu.confirmation.visible, "NewGame confirms before replacing checkpoint")
	menu.cancel_button.pressed.emit()
	check(menu.home.visible and not menu.confirmation.visible, "Cancel keeps the run")
	menu.continue_button.pressed.emit()
	await frames(30)
	check(current_scene.name == "Main" and game.current_day == 1, "Continue resumes the saved day")
	game.return_to_menu()
	await frames(30)
	print("Main menu checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
