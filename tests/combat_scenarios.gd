extends SceneTree

var room: Node3D
var manager: Node
var spawner: Node
var head: Node3D
var checks: int = 0
var failures: int = 0
var completed: Array[int] = []
var projectiles: Array[Node] = []

func _initialize() -> void: call_deferred("run_checks")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func advance(frames: int) -> void:
	for frame in frames: await physics_frame
func until(predicate: Callable, frames: int = 600) -> bool:
	for frame in frames:
		if predicate.call(): return true
		await physics_frame
	return false
func spawn() -> Node3D:
	await until(func(): return manager.can_spawn())
	var order: Array[int] = [FoodItem.Type.WATER]
	return spawner.spawn_one(order)
func reset(count: int) -> void:
	head.drop_object()
	spawner.cancel_wave()
	manager.reset_queue()
	for item in projectiles:
		if is_instance_valid(item): item.queue_free()
	projectiles.clear()
	manager.set_physics_process(true)
	await advance(3)
	spawner.start_wave(count)
func make_item(path: String) -> RigidBody3D:
	var item = load(path).instantiate()
	room.add_child(item)
	projectiles.append(item)
	item.gravity_scale = 0.0
	return item
func shoot(item: Node3D, target: Node3D, force: float) -> void:
	item.global_position = target.global_position + Vector3(0, 0.72, 2.0)
	item.global_basis = Basis.IDENTITY
	head.carry_position.global_transform = Transform3D(Basis.IDENTITY, item.global_position)
	head.pick_up(item)
	head.throw_object(force)

func run_checks() -> void:
	manager = root.get_node("QueueManager")
	room = load("res://scenes/Queuetest.tscn").instantiate()
	room.start_test_wave_on_ready = false
	spawner = room.get_node("Spawner")
	spawner.spawning_paused = true
	spawner.patience_seconds = 300
	root.add_child(room)
	current_scene = room
	head = room.get_node("Player/Head")
	spawner.wave_completed.connect(func(total: int): completed.append(total))
	await reset(1)
	var a = await spawn()
	check(a.health == a.max_health and a.max_health == 100, "Prisoner begins with full configurable health")
	a.take_damage(-5)
	check(a.health == 100, "Negative damage cannot heal")
	head.pick_up(a)
	check(head.carried_object == null, "Conscious prisoners cannot be picked up")
	manager.set_physics_process(false)
	a.set_physics_process(false)
	a.global_position = Vector3(0, 0.02, -5)
	a.max_health = 1000
	a.health = 1000
	var paths: Array[String] = ["maps/pan", "maps/Pot", "maps/knife", "foods/Tray", "foods/Bottle", "foods/Chicken", "foods/Carrot", "foods/Cabbage", "foods/Rice", "foods/MixedVegetables"]
	for i in paths.size():
		var item = make_item("res://scenes/prefebs/" + paths[i] + ".tscn")
		var before: float = a.health
		shoot(item, a, 5.0 if i % 2 == 0 else 25.0)
		check(await until(func(): return a.health < before, 240), paths[i] + " causes damage through a real thrown collision")
		var impact = item.get_node("ThrowImpact")
		var expected: float = impact.hit_speeds.get(a.get_instance_id(), 0.0) * head.throw_damage_per_speed
		check(expected > 0 and is_equal_approx(a.health, before - expected), "Damage uses incoming linear velocity: " + paths[i])
		impact._report_contact(a, impact.launch_generation, 20.0)
		impact._report_contact(a, impact.launch_generation, 20.0)
		check(is_equal_approx(a.health, before - expected), "Repeated contacts in the same throw do not stack damage: " + paths[i])
		item.queue_free()
		await advance(2)
	check(a.anger_reason == "Hit by a thrown object", "Hitting a calm prisoner makes it angry")

	var bottle = make_item("res://scenes/prefebs/foods/Bottle.tscn")
	var before: float = a.health
	bottle.global_position = a.global_position + Vector3(0, 0.7, 1)
	head.pick_up(bottle)
	head.drop_object()
	bottle.linear_velocity = Vector3(0, 0, -5)
	await advance(40)
	check(a.health == before, "Ordinary drop/contact does not arm damage")
	shoot(bottle, a, 25)
	check(await until(func(): return a.health < before), "Previously dropped item can be picked up and thrown")
	var impact = bottle.get_node("ThrowImpact")
	var old_generation: int = impact.launch_generation
	head.pick_up(bottle)
	check(not impact.armed, "Picking a projectile up immediately disarms it")
	head.drop_object()
	check(not impact.armed and not head.is_charging, "Dropping remains harmless and clears charging state")
	before = a.health
	shoot(bottle, a, 25)
	impact._report_contact(a, old_generation, 20.0)
	check(a.health == before, "Delayed contacts from an old launch cannot damage a new launch")
	check(await until(func(): return a.health < before), "A new throw can damage the same prisoner again")
	bottle.freeze = true
	bottle.linear_velocity = Vector3.ZERO
	bottle.angular_velocity = Vector3.ZERO
	await advance(60)
	check(not impact.armed, "A stopped projectile loses its damage state")
	bottle.queue_free()
	await advance(2)

	var slow = make_item("res://scenes/prefebs/foods/Bottle.tscn")
	before = a.health
	shoot(slow, a, 5)
	check(await until(func(): return a.health < before), "Weak throw hits")
	var weak_damage: float = before - a.health
	slow.queue_free()
	await advance(2)
	var fast = make_item("res://scenes/prefebs/foods/Bottle.tscn")
	before = a.health
	shoot(fast, a, 25)
	check(await until(func(): return a.health < before), "Strong throw hits")
	check(before - a.health > weak_damage * 3.0, "Higher impact speed produces more damage for the same item")
	check(fast.linear_velocity.length() < fast.get_node("ThrowImpact").hit_speeds.get(a.get_instance_id(), 0.0), "Damage retains incoming speed even when the collision solver slows the item")
	fast.queue_free()
	await advance(2)
	var slowed = make_item("res://scenes/prefebs/foods/Bottle.tscn")
	before = a.health
	shoot(slowed, a, 25)
	# Brake after launch, well before impact: damage must not use charge/launch speed.
	await advance(1)
	slowed.linear_velocity = Vector3(0, 0, -2)
	check(await until(func(): return a.health < before), "A projectile slowed in flight still hits")
	check(before - a.health < weak_damage, "Damage follows speed near impact rather than the original launch strength")
	slowed.queue_free()
	await advance(25)

	var scale_before: Vector3 = a.scale
	var collider_before: Transform3D = a.get_node("CollisionShape3D").transform
	a.take_damage(1)
	check(a.visuals.hit_flash > 0.0, "Damage immediately starts a soft red flash")
	await advance(3)
	check(not a.visuals.model.scale.is_equal_approx(a.visuals.base_model_scale), "Nonlethal damage squashes the rendered model")
	check(a.scale == scale_before and a.get_node("CollisionShape3D").transform == collider_before, "Hit tween does not scale the actor or its movement collider")
	a.take_damage(1)
	await advance(30)
	check(a.visuals.model.scale.is_equal_approx(a.visuals.base_model_scale) and is_zero_approx(a.visuals.hit_flash), "Repeated hits restart feedback then restore scale and color")
	var colors_restored: bool = true
	for i in a.visuals.hit_materials.size():
		colors_restored = colors_restored and a.visuals.hit_materials[i].albedo_color.is_equal_approx(a.visuals.base_colors[i])
	check(colors_restored, "Every material restores its original color")

	# One wave owns both corpses until the player disposes of them.
	await reset(2)
	a = await spawn()
	var b = await spawn()
	manager.set_physics_process(false)
	a.set_physics_process(false)
	b.set_physics_process(false)
	a.global_position = Vector3(-2, 0.02, -5)
	b.global_position = Vector3(2, 0.02, -5)
	var ricochet = make_item("res://scenes/prefebs/foods/Bottle.tscn")
	shoot(ricochet, a, 25)
	check(await until(func(): return a.health < 100), "A launch can hit its first victim")
	var ricochet_impact = ricochet.get_node("ThrowImpact")
	var a_after_hit: float = a.health
	check(is_zero_approx(b.visuals.hit_flash) and a.visuals.hit_materials[0] != b.visuals.hit_materials[0], "A prisoner's hit flash does not tint another prisoner")
	ricochet_impact._report_contact(b, ricochet_impact.launch_generation, 3.0)
	ricochet_impact._report_contact(a, ricochet_impact.launch_generation, 3.0)
	check(a.health == a_after_hit and b.health == 100 - 3.0 * head.throw_damage_per_speed, "The same launch may hit another victim at a different speed but cannot re-hit the first")
	ricochet.queue_free()
	var slot: int = a.slot_index
	a.give_serving_tray()
	var original_tray = a.serving_tray
	a.take_damage(100, room.get_node("Player"))
	await advance(3)
	check(a.is_incapacitated() and a.health == 0 and not a.attack_in_progress, "Lethal damage enters permanent incapacity and cancels attacks")
	check(a.visuals.model.scale.is_equal_approx(a.visuals.base_model_scale), "Lethal damage cancels squash before physical bones start")
	check(manager.active_count() == 1 and manager.incapacitated_count() == 1 and spawner.wave_alive_count() == 1, "Corpses do not consume the living prisoner cap")
	check(spawner.wave_pending_count() == 2 and spawner.wave_active and completed.is_empty(), "Incapacity does not prematurely complete the wave")
	check(manager.occupants[slot] != a and not a in manager.reservations, "Incapacitation clears occupancy and all reservations")
	check(is_instance_valid(original_tray) and original_tray.get_parent() == a.thrown_tray and not a.has_serving_tray(), "Lethal hit releases a held tray without waiting for an animation")
	check(a.thrown_tray.get_node_or_null("ThrowImpact") == null, "Prisoner-discarded trays are not armed as player weapons")
	check(a.ragdoll.bones.size() == 6 and a.ragdoll.bones.all(func(bone): return bone.get_bone_id() >= 0), "Ragdoll uses six valid physical bones")
	await advance(180)
	check(a.ragdoll.center().y < 0.65 and a.ragdoll.center().y > 0, "Ragdoll falls and settles on the floor")
	check(a.ragdoll.bones.all(func(bone): return bone.global_position.distance_to(a.ragdoll.center()) < 2), "Ragdoll joints hold the body together")
	a.take_damage(100)
	check(a.get_node("Ragdoll") == a.ragdoll and a.health == 0, "Further damage does not create another ragdoll")
	a.give_serving_tray()
	a.move_to_slot(0, Vector3.ZERO)
	a.set_waiting(true, true)
	check(a.is_incapacitated() and not a.has_serving_tray(), "A corpse cannot resume queue actions or receive another tray")

	head.carry_position.global_transform = Transform3D(Basis.IDENTITY, Vector3(2, 0.85, -2.8))
	var body_pose: Transform3D = a.visuals.skeleton.get_bone_pose(a.visuals.skeleton.find_bone("body"))
	var neck_pose: Transform3D = a.visuals.skeleton.get_bone_pose(a.visuals.skeleton.find_bone("neck"))
	head.last_hovered_object = a
	head._handle_interact_pressed()
	await advance(45)
	check(head.carried_object == a and a.ragdoll.held, "Existing interaction input picks up an unconscious prisoner")
	check(a.visuals.skeleton.get_bone_pose(a.visuals.skeleton.find_bone("body")).is_equal_approx(body_pose) and a.visuals.skeleton.get_bone_pose(a.visuals.skeleton.find_bone("neck")).is_equal_approx(neck_pose), "Holding preserves non-physical bone local poses instead of stretching the body/neck")
	check(a.ragdoll.center().distance_to(head.carry_position.global_position) < 0.03, "Entire frozen ragdoll follows the same carry marker")
	var held_center: Vector3 = a.ragdoll.center()
	head.drop_object()
	await advance(1)
	check(a.ragdoll.center().distance_to(held_center) < 0.15, "Dropping resumes physics at the carried pose without teleporting")
	check(not a.ragdoll.held and a.get_node_or_null("ThrowImpact") == null, "Dropping a corpse is harmless")
	head.pick_up(a)
	await advance(30)
	before = b.health
	head.throw_object(25)
	check(await until(func(): return b.health < before, 180), "A thrown ragdoll damages another prisoner through actual bone collisions")
	var corpse_impact = a.get_node("ThrowImpact")
	var corpse_damage: float = corpse_impact.hit_speeds.get(b.get_instance_id(), 0.0) * head.throw_damage_per_speed
	check(corpse_damage > 0 and is_equal_approx(b.health, before - corpse_damage), "Ragdoll damage uses the incoming linear velocity of the hitting bone")
	corpse_impact._report_contact(b, corpse_impact.launch_generation, 20.0)
	check(is_equal_approx(b.health, before - corpse_damage), "Additional limbs cannot multiply corpse damage")
	corpse_impact._report_contact(a.ragdoll.bones[0], corpse_impact.launch_generation, 20.0)
	check(a.health == 0, "A thrown corpse cannot attack itself or regain consciousness")
	b.take_damage(100)
	await advance(3)
	check(manager.active_count() == 0 and manager.incapacitated_count() == 2 and spawner.wave_active, "All prisoners down still requires disposing of both bodies")
	var trash = room.get_node("PrisonerTrash")
	head.pick_up(a)
	head.last_hovered_object = trash
	head.is_charging = true
	head.is_holding_button = true
	head._handle_interact_pressed()
	await advance(3)
	check(not is_instance_valid(a) and head.carried_object == null and not head.is_charging and head.last_hovered_object == null, "Trash interaction deletes the corpse and clears every held/charge/focus reference")
	check(spawner.wave_active and spawner.wave_pending_count() == 1, "One remaining body still blocks wave completion")
	head.pick_up(b)
	trash.interact_with(b, head)
	await advance(3)
	check(not spawner.wave_active and completed == [2], "Disposing of the last body completes the wave exactly once")
	check(manager.actors.is_empty(), "Disposal leaves no stale queue actors")

	var kitchen_pan = make_item("res://scenes/prefebs/maps/pan.tscn")
	var chicken = make_item("res://scenes/prefebs/foods/Chicken.tscn")
	chicken.current_state = FoodItem.State.CUT
	head.pick_up(chicken)
	check(kitchen_pan.interact_with(chicken, head) and kitchen_pan.current_food == chicken and head.carried_object == null, "Original held ingredient still transfers into cookware")
	head.pick_up(kitchen_pan)
	trash.interact_with(kitchen_pan, head)
	await advance(2)
	check(is_instance_valid(kitchen_pan) and kitchen_pan.current_food == null and head.carried_object == kitchen_pan, "Trash removes food inside cookware while preserving the held cookware")
	head.drop_object()
	var loose_food = make_item("res://scenes/prefebs/foods/Carrot.tscn")
	head.pick_up(loose_food)
	trash.interact_with(loose_food, head)
	await advance(2)
	check(not is_instance_valid(loose_food) and head.carried_object == null, "Trash still accepts a loose FoodItem through the original controls")

	await reset(1)
	a = await spawn()
	a.take_damage(100)
	await advance(3)
	head.pick_up(a)
	room.reset_lab()
	await advance(3)
	check(not is_instance_valid(a) and head.carried_object == null, "Reset safely removes a corpse while it is being held")
	room.queue_free()
	await advance(3)
	check(manager.actors.is_empty() and manager.layout_owner == null, "Scene exit clears live prisoners and corpses")
	print("Combat scenario checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
