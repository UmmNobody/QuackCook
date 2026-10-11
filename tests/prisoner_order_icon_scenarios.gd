extends SceneTree
var checks := 0
var failures := 0
var stage: Node3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(n: int) -> void:
	for i in n: await physics_frame
func spawn(order: Array[int]) -> Node3D:
	var actor = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	actor.configure(order, 45.0)
	stage.add_child(actor)
	actor.set_physics_process(false)
	return actor
func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var actor = spawn([FoodItem.Type.WATER, FoodItem.Type.RICE, FoodItem.Type.CHICKEN, FoodItem.Type.MIXED_VEG, FoodItem.Type.CHICKEN])
	check(not actor.has_node("Info") and actor.has_node("FoodIcon/Patience"), "Overhead display has food icon and patience bar without old text")
	check(actor.find_children("*", "Sprite3D", true, false).size() == 1, "One overhead food sprite per prisoner")
	check(actor.food_icon.billboard == BaseMaterial3D.BILLBOARD_ENABLED and not actor.food_icon.shaded, "Icon faces camera and stays readable without scene lighting")
	check(actor.food_icon.visible and actor.food_icon.texture == actor.chicken_icon, "Unsorted multi-food order starts at first needed queue station")
	actor.give_serving_tray()
	var textures := [actor.chicken_icon, actor.vegetables_icon, actor.rice_icon, actor.water_icon]
	for i in actor.MENU.size():
		var food: int = actor.MENU[i]
		check(actor.current_wanted_food() == food and actor.food_icon.texture == textures[i], "Shows only current food %d" % food)
		actor.receive_food(food)
		check(not actor.needs_food(food), "Serving fulfills food %d" % food)
	check(actor.complete() and not actor.food_icon.visible and actor.food_icon.texture == null, "Completed order hides icon immediately")
	actor.queue_free()
	await frames(2)
	actor = spawn([FoodItem.Type.WATER, FoodItem.Type.RICE])
	actor.set_waiting(true, false)
	check(actor.food_icon.texture == actor.rice_icon, "Blocked at an unwanted station still displays next requested food")
	var patience: float = actor.patience
	actor._physics_process(0.1)
	check(actor.patience < patience, "Patience still counts down with the icon display")
	actor.move_to_slot(1, Vector3.ONE)
	check(actor.food_icon.visible and actor.food_icon.texture == actor.rice_icon, "Icon remains visible while walking between slots")
	var route: Array[Vector3] = []
	actor.begin_anger(route, null, "Wrong food")
	check(not actor.food_icon.visible, "Angry prisoner no longer displays a food request")
	actor.queue_free()
	await frames(2)
	actor = spawn([FoodItem.Type.MIXED_VEG])
	actor.take_damage(10000)
	check(actor.is_incapacitated() and not actor.food_icon.visible, "Lethal damage hides icon")
	await frames(3)
	check(is_instance_valid(actor.ragdoll), "Ragdoll still starts without removed label nodes")
	actor.queue_free()
	await frames(2)
	actor = spawn([])
	check(not actor.food_icon.visible, "Empty order does not display a stale preview texture")
	var water_order: Array[int] = [FoodItem.Type.WATER]
	actor.configure(water_order, 30.0)
	check(actor.food_icon.texture == actor.water_icon and actor.food_icon.visible, "Reconfiguring an existing prisoner updates icon immediately")
	actor.begin_exit(Vector3.ZERO)
	check(not actor.food_icon.visible, "Departing prisoner hides icon")
	actor.queue_free()
	await frames(2)
	# Optional visual fixture: render all four supplied icons over actual prisoners.
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and not args.is_empty():
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_COLOR
		world.environment.background_color = Color(0.22, 0.28, 0.33)
		world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world.environment.ambient_light_color = Color.WHITE
		world.environment.ambient_light_energy = 0.8
		stage.add_child(world)
		var light := DirectionalLight3D.new()
		stage.add_child(light)
		light.rotation_degrees = Vector3(-40,-30,0)
		var menu: Array[int] = [FoodItem.Type.CHICKEN, FoodItem.Type.MIXED_VEG, FoodItem.Type.RICE, FoodItem.Type.WATER]
		for i in menu.size():
			var preview = spawn([menu[i]])
			preview.position.x = (i - 1.5) * 1.65
			preview.patience = preview.patience_duration * [1.0, 0.5, 0.1, 0.75][i]
			preview._update_display()
		var camera := Camera3D.new()
		stage.add_child(camera)
		camera.position = Vector3(0,2.3,7)
		camera.look_at(Vector3(0,1.5,0))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0].path_join("prisoner_order_icons.png"))
	stage.queue_free()
	await frames(3)
	print("Prisoner order icon checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)

