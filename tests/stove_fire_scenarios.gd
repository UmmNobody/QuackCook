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
	for i in count: await physics_frame
func capture(room: Node3D, stove: Node3D, name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().is_empty(): return
	var cam := Camera3D.new()
	room.add_child(cam)
	cam.global_position = stove.to_global(Vector3(2.4, 2.5, 3))
	cam.look_at(stove.to_global(Vector3(0, 1.4, 0)))
	cam.make_current()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(name + ".png"))
	cam.queue_free()
func run() -> void:
	var room = load("res://scenes/main.tscn").instantiate()
	room.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(room)
	current_scene = room
	var stove = room.get_node("Kitchen/Stations/Stove")
	var player = room.get_node("Actors/Player")
	player.set_physics_process(false)
	player.head.set_process(false)
	await frames(4)
	check(not stove.fire.active and not stove.fire.visible, "Empty stove has no fire")
	for name in ["Pan", "Pot"]:
		var item = room.get_node("Items/" + name)
		stove.place_cookware(item)
		await frames(3)
		check(not stove.fire.active, name + " empty cookware has no fire")
		var path := "res://scenes/items/foods/chicken.tscn" if name == "Pan" else "res://scenes/items/foods/rice.tscn"
		var food = load(path).instantiate()
		room.add_child(food)
		if name == "Pan": food.current_state = FoodItem.State.CUT
		food.cook_duration = 100
		check(item.add_food(food), name + " accepts food")
		await frames(35)
		check(stove.fire.active and stove.fire.emitting and stove.fire.visible and food.cook_progress > 0, name + " fire runs while cooking")
		await capture(room, stove, name.to_lower() + "_fire")
		var progress: float = food.cook_progress
		paused = true
		for i in 8: await process_frame
		check(not stove.fire.can_process() and food.cook_progress == progress, "Pause freezes fire and food")
		paused = false
		player.head.pick_up(item)
		check(not stove.fire.active and not stove.fire.visible, name + " pickup stops fire immediately")
		stove.interact_with(item, player.head)
		await frames(3)
		check(stove.fire.active, name + " replacing cookware restarts fire")
		food.cook_duration = food.cook_progress + 0.03
		await frames(5)
		check(food.current_state == FoodItem.State.COOKED and not stove.fire.active, name + " cooked food stops fire")
		item.clear_food()
		await frames(3)
		check(not stove.fire.active, name + " removing food keeps fire off")
		player.head.pick_up(item)
		player.head.drop_object()
		item.global_position = stove.global_position + Vector3(4, 2, 0)
		item.freeze = true
		await frames(3)
	room.queue_free()
	await frames(3)
	print("Stove fire checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
