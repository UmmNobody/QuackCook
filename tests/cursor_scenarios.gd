extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func run() -> void:
	root.get_node("GameManager").tutorial_seen = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 8: await process_frame
	var hud = current_scene.get_node("UI/ServiceHUD")
	var head = current_scene.get_node("Actors/Player/Head")
	head.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	head.last_hovered_object = null
	hud._update_cursor()
	check(hud.get_node("%Crosshair").visible and not hud.get_node("%FocusCursor").visible, "Empty aim shows +")
	var chicken = load("res://scenes/items/foods/chicken.tscn").instantiate()
	current_scene.add_child(chicken)
	chicken.freeze = true
	head.last_hovered_object = chicken
	hud._update_cursor()
	check(not hud.get_node("%Crosshair").visible and hud.get_node("%FocusCursor").visible, "Pickable target shows focus image instead of +")
	check(hud.get_node("%FocusCursor").texture.resource_path.ends_with("cursor_focus.png"), "Uses requested focus texture")
	head.last_hovered_object = null
	hud._update_cursor()
	check(hud.get_node("%Crosshair").visible and not hud.get_node("%FocusCursor").visible, "Looking away restores +")
	head.last_hovered_object = chicken
	paused = true
	hud._update_cursor()
	check(not hud.get_node("%Crosshair").visible and not hud.get_node("%FocusCursor").visible, "Paused menu hides aiming cursors")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud._update_cursor()
	check(not hud.get_node("%Crosshair").visible and not hud.get_node("%FocusCursor").visible, "Free mouse hides aiming cursors")
	check(root.get_node("AppSettings").FREE_MOUSE_CURSOR.resource_path.ends_with("cursor_freemouse.png"), "Free cursor uses requested texture")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	head.last_hovered_object = chicken
	chicken.queue_free()
	hud._update_cursor()
	check(hud.get_node("%Crosshair").visible and not hud.get_node("%FocusCursor").visible, "Queued deletion restores + immediately")
	await process_frame
	check(not is_instance_valid(head.last_hovered_object), "Regression setup retains a freed hover reference")
	hud._update_cursor()
	check(hud.get_node("%Crosshair").visible and not hud.get_node("%FocusCursor").visible, "Freed hover target safely restores +")
	var next_target = load("res://scenes/items/foods/chicken.tscn").instantiate()
	current_scene.add_child(next_target)
	next_target.freeze = true
	head.last_hovered_object = next_target
	hud._update_cursor()
	check(hud.get_node("%FocusCursor").visible and not hud.get_node("%Crosshair").visible, "Focus recovers on a new target after deletion")
	print("Cursor checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

