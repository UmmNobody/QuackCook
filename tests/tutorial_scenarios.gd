extends SceneTree

var game: Node
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
func until(predicate: Callable) -> bool:
	for i in 120:
		if predicate.call(): return true
		await process_frame
	return false
func close_key() -> void:
	var key = InputMap.action_get_events("quit")[0].duplicate() as InputEventKey
	key.pressed = true
	Input.parse_input_event(key)
	var release = key.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await frames(2)
func capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty(): return
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(name + ".png"))

func run() -> void:
	game = root.get_node("GameManager")
	check(not game.tutorial_seen and not game.tutorial_open, "Fresh process starts with unseen tutorial")
	check(not game.open_tutorial(), "Cannot open guide without a kitchen")
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await until(func(): return current_scene != null and current_scene.name == "MainMenu")
	current_scene.start_button.pressed.emit()
	await until(func(): return current_scene != null and current_scene.name == "IntroCutscene")
	current_scene.skip_button.pressed.emit()
	check(await until(func(): return game.tutorial_open), "First Start opens tutorial automatically")
	var room := current_scene
	var guide = room.get_node("UI/TutorialPopup")
	var sign = room.get_node("Kitchen/Interactables/TutorialSign")
	var player = room.get_node("Actors/Player")
	var head = player.get_node("Head")
	check(paused and guide.screen.visible and game.tutorial_seen, "Tutorial opens as a paused modal and marks this session seen")
	check(game.preparation_remaining == 30 and game.spawned_count == 0, "First tutorial preserves the entire preparation countdown")
	await frames(20)
	check(game.preparation_remaining == 30 and game.spawned_count == 0 and not player.can_control(), "Reading guide freezes game and controls")
	check(guide.pages.size() == 5 and guide.page_counter.text == "1 / 5", "Saved scene has all five illustrated pages")
	check(guide.previous_button.disabled and not guide.next_button.disabled, "First-page navigation bounds")
	check(not game.open_tutorial() and not game.open_kitchen() and game.finish_service().is_empty(), "Modal prevents duplicate opening and kitchen actions")
	for i in 5:
		var image: TextureRect = guide.pages[i].get_node("Image")
		check(image.texture.resource_path == "res://assets/textures/ui/tutorial/tutorial%d.png" % (i + 1), "Page %d uses the correct artwork" % (i + 1))
		guide.change_page(i - guide.page_index)
		await capture("tutorial_page_%d" % (i + 1))
	guide.change_page(-guide.page_index)
	await capture("tutorial_first")
	guide.next_button.pressed.emit()
	check(guide.page_counter.text == "2 / 5" and guide.pages[1].visible and not guide.pages[0].visible, "Next shows exactly the second page")
	guide.change_page(3)
	check(guide.next_button.disabled and guide.page_counter.text == "5 / 5", "Last page disables Next")
	guide.change_page(1)
	check(guide.page_index == 4, "Cannot navigate past last page")
	guide.previous_button.pressed.emit()
	check(guide.page_counter.text == "4 / 5", "Previous returns to earlier pages")
	await close_key()
	check(not game.tutorial_open and not game.pause_menu_open and not paused and not guide.screen.visible, "Close shortcut only dismisses tutorial and resumes game")
	check(player.can_control() and head.interaction_allowed(), "Closing restores normal player control")
	check(DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Closing recaptures the mouse")
	await close_key()
	check(game.pause_menu_open and paused and not game.open_tutorial(), "Settings keeps ownership of pause and blocks guide opening")
	await close_key()
	# The guide is now a book on the counter; aim down at its current placement.
	var ray := PhysicsRayQueryParameters3D.create(sign.global_position + Vector3.UP, sign.global_position, 3)
	ray.exclude = [player.get_rid()]
	await physics_frame
	check(room.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == sign, "Guide book is reachable by aiming at its current placement")
	check(sign is StaticBody3D and not sign.is_in_group("Pickable"), "Guide is immovable and cannot be picked up")
	var sign_pose: Transform3D = sign.global_transform
	head.object_focused.emit(sign)
	check(sign.outline.visible and (sign.hint == null or sign.hint.visible), "Guide highlights when focused")
	var pan = room.get_node("Items/Pan")
	head.pick_up(pan)
	head.last_hovered_object = null
	head._handle_interact_pressed()
	head._update_throw_charge(0.4)
	sign.interact_with(pan, head)
	check(game.tutorial_open and paused and guide.page_counter.text == "1 / 5", "Sign reopens the guide from page one")
	check(not head.is_charging and head.carried_object == pan and not sign.outline.visible, "Opening cancels charged throw and focus but keeps held item")
	var held_pose: Transform3D = pan.global_transform
	await frames(15)
	check(pan.global_transform == held_pose and sign.global_transform == sign_pose, "Guide freezes held-item physics while its sign stays fixed")
	guide.close_button.pressed.emit()
	head._handle_interact_released()
	check(head.carried_object == pan and not paused, "Closing does not accidentally release a charged throw")
	head.drop_object()
	# Emulate editing Pages: duplicate, reorder, assign a texture, remove all pages.
	var added = guide.pages[0].duplicate()
	guide.pages_root.add_child(added)
	guide.pages_root.move_child(added, 0)
	var artwork := GradientTexture2D.new()
	artwork.gradient = Gradient.new()
	artwork.width = 640
	artwork.height = 360
	added.get_node("Image").texture = artwork
	check(game.open_tutorial(), "Guide can reopen repeatedly")
	check(guide.pages.size() == 6 and guide.pages[0] == added and guide.page_counter.text == "1 / 6", "Adding and reordering page nodes updates navigation automatically")
	check(not added.get_node("Placeholder").visible, "Assigned artwork hides placeholder number")
	await capture("tutorial_artwork")
	game.close_tutorial()
	var removed: Array[Node] = []
	for page in guide.pages_root.get_children():
		removed.append(page)
		guide.pages_root.remove_child(page)
	game.open_tutorial()
	check(guide.empty_state.visible and guide.page_counter.text == "0 / 0" and guide.next_button.disabled and guide.previous_button.disabled, "Zero-page guide stays closable without errors")
	game.close_tutorial()
	guide.pages_root.add_child(removed.pop_front())
	game.open_tutorial()
	check(guide.page_counter.text == "1 / 1" and guide.next_button.disabled and guide.previous_button.disabled, "One-page guide handles both navigation bounds")
	game.close_tutorial()
	for page in removed: guide.pages_root.add_child(page)
	game.open_kitchen()
	await until(func(): return game.spawned_count > 0)
	check(game.open_tutorial(), "Guide can reopen during active service")
	var count: int = game.spawned_count
	var actor = root.get_node("QueueManager").actors.values()[0]
	var actor_pose: Transform3D = actor.global_transform
	await frames(20)
	check(game.spawned_count == count and actor.global_transform == actor_pose, "Tutorial pauses spawning and prisoner movement")
	check(game.return_to_menu(), "Scene transition can safely leave an open guide")
	check(await until(func(): return current_scene != null and current_scene.name == "MainMenu" and not paused), "Scene unload clears tutorial pause")
	check(game.tutorial_seen and not game.tutorial_open, "Seen flag persists after returning to menu")
	current_scene.start_button.pressed.emit()
	current_scene.continue_button.pressed.emit()
	check(await until(func(): return current_scene != null and current_scene.name == "Main" and game.state == game.State.PREPARING), "Continue opens a fresh kitchen")
	check(not game.tutorial_open and not paused and game.tutorial_seen, "Continue does not repeat automatic tutorial")
	game.return_to_menu()
	await until(func(): return current_scene != null and current_scene.name == "MainMenu")
	current_scene.start_button.pressed.emit()
	current_scene.new_button.pressed.emit()
	await until(func(): return current_scene != null and current_scene.name == "IntroCutscene")
	current_scene.skip_button.pressed.emit()
	await until(func(): return current_scene != null and current_scene.name == "Main" and game.state == game.State.PREPARING)
	check(not game.tutorial_open and game.current_day == 1, "New game in same application session does not repeat tutorial")
	game.return_to_menu()
	await until(func(): return current_scene != null and current_scene.name == "MainMenu")
	print("Tutorial checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
