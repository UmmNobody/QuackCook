extends SceneTree
var checks: int = 0
var failures: int = 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func advance(count: int) -> void:
	for i in count: await physics_frame
func run() -> void:
	var room = load("res://scenes/main.tscn").instantiate()
	room.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(room)
	current_scene = room
	var player = room.get_node("Actors/Player")
	var head = player.get_node("Head")
	var stove = room.get_node("Kitchen/Stations/Stove")
	player.set_physics_process(false)
	head.set_process(false)
	await advance(3)
	for name in ["Pan", "Pot"]:
		var item = room.get_node("Items/" + name)
		for target in [stove, item]:
			for settle in [0, 5]:
				head.drop_object()
				item.remove_from_stove()
				stove.place_cookware(item)
				if settle > 0: await advance(settle)
				head.carry_position.global_position = stove.stove_snap_point.global_position + Vector3(0, 0.8, -2)
				head.last_hovered_object = target
				head._handle_interact_pressed()
				check(head.carried_object == item, "%s picked up by one click on %s (settle %d)" % [name, target.name, settle])
				await advance(45)
				check(head.carried_object == item and not item.is_on_stove and stove.current_cookware == null, "%s remains held after snap/deferred callbacks (%s, %d)" % [name, target.name, settle])
				check(item.global_position.distance_to(head.carry_position.global_position) < 0.02, "%s reaches the hand without repeated clicks" % name)
				# Return via the actual held-item interaction, then immediately lift again.
				stove.interact_with(head.carried_object, head)
				check(stove.current_cookware == item and item.is_on_stove and head.carried_object == null, "%s can be put back on stove" % name)
				await advance(3)
		# Direct common pickup must detach both subclasses, including Pot.
		head.pick_up(item)
		await advance(5)
		check(head.carried_object == item and not item.is_on_stove and stove.current_cookware == null, "%s direct pickup releases stove ownership" % name)
		head.drop_object()
		item.global_position = stove.stove_snap_point.global_position + Vector3(0, 2, -3)
		item.freeze = true
		await advance(3)
		# Real Area3D auto-snap, not only explicit stove interaction.
		item.global_position = stove.stove_snap_point.global_position
		await advance(5)
		check(stove.current_cookware == item and item.is_on_stove, "%s still auto-snaps when unheld" % name)
		head.last_hovered_object = item
		head._handle_interact_pressed()
		await advance(45)
		check(head.carried_object == item and stove.current_cookware == null, "%s lifts from automatic placement in one click" % name)
		var food_path := "res://scenes/items/foods/chicken.tscn" if name == "Pan" else "res://scenes/items/foods/rice.tscn"
		var food = load(food_path).instantiate()
		room.add_child(food)
		if name == "Pan": food.current_state = FoodItem.State.CUT
		food.cook_duration = 100.0
		check(item.add_food(food), "%s accepts its ingredient" % name)
		stove.interact_with(item, head)
		await advance(15)
		check(food.cook_progress > 0 and stove.cooking_ui_3d.visible, "%s still cooks and shows progress on stove" % name)
		head.last_hovered_object = stove
		head._handle_interact_pressed()
		var saved_progress: float = food.cook_progress
		await advance(45)
		check(head.carried_object == item and item.current_food == food and food.get_parent() == item.food_snap_point, "%s retains food while lifted in one click" % name)
		check(food.cook_progress == saved_progress and not stove.cooking_ui_3d.visible, "%s stops cooking immediately after pickup" % name)
		head.drop_object()
		item.global_position = stove.stove_snap_point.global_position + Vector3(3, 0, -3)
		item.freeze = true
		await advance(3)
	room.queue_free()
	await advance(3)
	print("Stove pickup checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
