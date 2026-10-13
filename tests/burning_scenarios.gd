extends SceneTree
var checks := 0
var failures := 0
var room: Node3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func make_food(kind: String) -> FoodItem:
	var food = load("res://scenes/items/foods/" + kind + ".tscn").instantiate()
	food.position = Vector3(2, 4, 0)
	room.add_child(food)
	food.freeze = true
	if kind == "chicken": food.cut()
	return food
func prisoner() -> CharacterBody3D:
	var actor = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	actor.position = Vector3(-10, 1, 0)
	room.add_child(actor)
	actor.set_physics_process(false)
	return actor
func hit(item: RigidBody3D, target: Node3D) -> Node:
	var impact = load("res://scripts/combat/throw_impact.gd").ensure(item)
	impact.arm(room.get_node("Actors/Player"), 1.0, [item] as Array[PhysicsBody3D])
	impact._report_contact(target, impact.launch_generation, 2.0)
	return impact
func run() -> void:
	room = load("res://scenes/main.tscn").instantiate()
	room.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(room)
	current_scene = room
	await frames(4)
	var stove = room.get_node("Kitchen/Stations/Stove")
	stove.set_physics_process(false)
	var pan = room.get_node("Items/Pan")
	stove.place_cookware(pan)
	for kind in ["chicken", "mixed_vegetables", "rice"]:
		var food := make_food(kind)
		food.apply_heat(food.cook_duration)
		check(food.current_state == FoodItem.State.COOKED, kind + " cooks in its configured duration")
		food.apply_heat(2.99)
		check(food.burn_progress == 0 and not food.is_burning(), kind + " has a three second grace period")
		food.apply_heat(0.01 + food.cook_duration / 2)
		check(food.current_state == FoodItem.State.COOKED and is_equal_approx(food.burn_progress, food.cook_duration / 2), kind + " burn meter uses the cooking duration")
		pan.current_food = food
		stove._setup_cooking_ui()
		check(stove._progress_fill.bg_color.r > 0.9 and is_equal_approx(stove.progress_bar.ratio, 0.5), kind + " shows half red meter")
		food.apply_heat(food.cook_duration / 2 + 0.001)
		check(food.is_burning() and food.cooked_mesh.visible and food.cooked_mesh.material_override.albedo_color.r < 0.02, kind + " retains cooked geometry with black override")
		check(food.burning_fire.visible and food.burning_fire.emitting, kind + " has fire particles")
		stove._setup_cooking_ui()
		check(stove._progress_fill.bg_color == Color.BLACK and is_equal_approx(stove.progress_bar.ratio, 1), kind + " shows full black meter")
		pan.current_food = null
		food.queue_free()
		await frames(2)
	var food := make_food("chicken")
	pan.add_food(food)
	stove._physics_process(food.cook_duration / 2)
	check(stove._progress_fill.bg_color.g > 0.7 and is_equal_approx(stove.progress_bar.ratio, 0.5), "Raw to cooked meter is green")
	stove._physics_process(food.cook_duration / 2)
	check(stove._progress_fill.bg_color.g > 0.7 and is_equal_approx(stove.progress_bar.ratio, 1), "Grace period keeps full green meter")
	stove._physics_process(4)
	var before: float = food.burn_progress
	pan.remove_from_stove()
	stove._physics_process(20)
	check(food.burn_progress == before and not stove.cooking_ui_3d.visible, "Removing pan stops burning progress and hides meter")
	stove.place_cookware(pan)
	stove._physics_process(20)
	check(food.is_burning(), "Returning pan resumes overheating")
	pan.remove_from_stove()
	var tray = room.get_node("Items/Tray")
	check(pan.handle_tray_transfer(tray) and tray.current_food == food, "Burnt food transfers to a tray")
	check(food.is_burning() and food.burning_fire.visible, "Fire follows transferred food")
	var actor := prisoner()
	var impact := hit(tray, actor)
	check(is_equal_approx(actor.health, 98) and actor.has_node("BurnStatus"), "Thrown burning tray applies impact and ignites prisoner")
	var status = actor.get_node("BurnStatus")
	status.set_physics_process(false)
	check(status.fire.get_parent() == actor and status.fire.visible, "Prisoner flames follow the character")
	status._physics_process(0.99)
	check(is_equal_approx(actor.health, 98), "No fire damage before one second")
	status._physics_process(0.01)
	check(is_equal_approx(actor.health, 88), "Fire deals ten damage at one second")
	impact._report_contact(actor, impact.launch_generation, 2)
	check(is_equal_approx(actor.health, 88), "Repeated collision from one throw does not duplicate damage")
	status._physics_process(2)
	check(is_equal_approx(actor.health, 68) and status.remaining == 0 and not status.fire.visible, "Fire deals exactly thirty over three seconds and expires")
	status._physics_process(2)
	check(is_equal_approx(actor.health, 68), "Expired fire does no further damage")
	actor.ignite()
	status.set_physics_process(false)
	status._physics_process(0.8)
	actor.ignite()
	status.set_physics_process(false)
	status._physics_process(0.2)
	check(is_equal_approx(actor.health, 58), "Re-ignition refreshes duration without delaying or stacking ticks")
	status.extinguish()
	var plain := make_food("rice")
	var other := prisoner()
	hit(plain, other)
	check(not other.has_node("BurnStatus"), "Nonburning food never ignites prisoners")
	plain.apply_heat(plain.cook_duration * 2 + 3.1)
	hit(plain, other)
	check(other.has_node("BurnStatus"), "A thrown loose burning food ignites")
	var other_status = other.get_node("BurnStatus")
	other_status.set_physics_process(false)
	other.health = 10
	other_status._physics_process(1)
	check(other.is_incapacitated() and not other_status.fire.visible, "Lethal burn enters ragdoll once and extinguishes")
	actor.ignite()
	status.set_physics_process(true)
	var hp: float = actor.health
	paused = true
	for i in 90: await process_frame
	check(is_equal_approx(actor.health, hp) and is_equal_approx(status.remaining, 3), "Pause freezes fire duration and damage")
	paused = false
	await frames(185)
	check(is_equal_approx(actor.health, hp - 30) and status.remaining == 0, "Real physics ticks apply all three damage ticks")
	room.queue_free()
	await frames(4)
	print("Burning checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
