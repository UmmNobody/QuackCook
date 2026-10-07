extends SceneTree

var room: Node3D
var manager: Node
var spawner: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func advance(frames: int) -> void:
	for frame in frames: await physics_frame

func until(predicate: Callable, frames: int = 1500) -> bool:
	for frame in frames:
		if predicate.call(): return true
		await advance(1)
	return false

func run_checks() -> void:
	manager = root.get_node("QueueManager")
	room = load("res://scenes/Queuetest.tscn").instantiate()
	room.start_test_wave_on_ready = false
	spawner = room.get_node("Spawner")
	spawner.spawning_paused = true
	spawner.patience_seconds = 300
	root.add_child(room)
	current_scene = room
	spawner.start_wave(2)
	var order: Array[int] = [FoodItem.Type.CHICKEN, FoodItem.Type.WATER]
	var a = spawner.spawn_one(order)
	check(a.has_node("Visuals/Model/ROOT/Armature/Skeleton3D") and not a.has_node("MeshInstance3D"), "Prisoner scene instances the GLB instead of a capsule mesh")
	var player: AnimationPlayer = a.visuals.animation_player
	check(player.get_animation_list().size() == 13, "All thirteen imported animation clips are available")
	check(player.get_animation("P1_Tray_Walk").loop_mode == Animation.LOOP_LINEAR and player.get_animation("P1_Tray_Throw").loop_mode == Animation.LOOP_NONE, "Walk loops while throw is a one-shot")
	var appearance_matches: bool = a.visuals.head_style in a.visuals.HEAD_STYLES
	for part in a.visuals.HEAD_STYLES:
		if not part.is_empty():
			appearance_matches = appearance_matches and (a.visuals.skeleton.get_node(NodePath(part)).visible == (part == a.visuals.head_style))
	check(appearance_matches, "Only the randomly selected head style is visible, or none for the bare-head option")
	check(await until(func(): return a.is_moving()), "Queue movement begins")
	check(player.assigned_animation == "P1_Walk_Waddle_Blockout", "Walking without a tray uses the normal walk")
	await advance(30)
	check(a.visuals.global_basis.z.dot(Vector3.RIGHT) > 0.9, "Visual faces the direction of queue travel")
	check(await until(func(): return a.state == a.State.PICKING_UP_TRAY), "Pickup enters its own animation state")
	check(player.assigned_animation == "P1_Tray_Pickup" and not a.has_serving_tray(), "Pickup animation begins empty-handed")
	check(await until(func(): return a.has_serving_tray()), "Tray attaches during the grab portion of the animation")
	check(a.state == a.State.PICKING_UP_TRAY and a.slot_index == manager.tray_pickup_index, "Queue waits for the whole pickup animation after the grab")
	var tray = a.serving_tray
	check(await until(func(): return a.is_moving()), "Queue resumes after pickup finishes")
	check(player.assigned_animation == "P1_Tray_Walk", "Walking with a tray uses the carry walk")
	var initial_grip: Vector3 = a.tray_hold_point.position
	await advance(15)
	check(a.tray_hold_point.position.distance_to(initial_grip) > 0.001, "Held tray follows animated hand positions")
	check(await until(func(): return manager.occupant_at_station(0) == a), "Prisoner arrives at chicken")
	await advance(25)
	check(player.assigned_animation == "P1_Tray_Idle" and a.visuals.global_basis.z.dot(Vector3.FORWARD * -1) > 0.9, "Standing customer faces the table with a tray idle")
	var b = spawner.spawn_one(order)
	check(await until(func(): return b.has_serving_tray()), "Second prisoner receives a separate tray")
	manager.request_serve(0)
	manager.request_serve(0) # Duplicate serving starts anger.
	check(a.state == a.State.THROWING_TRAY and a.is_departing() and a.has_serving_tray(), "Anger starts the throw animation while the tray is still held")
	check(player.assigned_animation == "P1_Tray_Throw", "Anger uses the imported throw clip")
	var original_position: Vector3 = a.global_position
	await advance(20)
	check(a.has_serving_tray() and a.global_position.distance_to(original_position) < 0.03, "Prisoner stays in place during throw wind-up")
	check(manager.occupants[manager.service_start_index] == a, "Throwing prisoner still blocks their old queue slot")
	check(await until(func(): return not a.has_serving_tray(), 120), "Tray releases at the animation's throw moment")
	var debris: RigidBody3D = a.thrown_tray
	check(is_instance_valid(debris) and tray.get_parent() == debris and a.tray_hold_point.get_child_count() == 0, "The same tray is reparented into a physics body")
	check(tray.has_food(FoodItem.Type.CHICKEN), "Food already served remains visible on the thrown tray")
	check(debris.collision_layer == 0 and room.get_node("Player") in debris.get_collision_exceptions(), "Thrown tray cannot block prisoners or collide with the player")
	var thrown_position: Vector3 = debris.global_position
	await advance(10)
	check(debris.global_position.distance_to(thrown_position) > 0.1, "Released tray actually flies under physics")
	check(b.has_serving_tray() and not b.serving_tray.has_food(FoodItem.Type.CHICKEN), "Another prisoner's tray is unaffected")
	check(a.visuals.skeleton.get_node("Hand_Fist_L").visible and not a.visuals.skeleton.get_node("Hand_Hold_L").visible, "Hands switch to fists after releasing the tray")
	check(await until(func(): return a.state == a.State.ENTERING_COMBAT), "Throw completes before entering combat")
	check(player.assigned_animation == "P1_Combat_Enter", "Combat entry clip plays before leaving the queue")
	check(await until(func(): return a.state == a.State.ANGRY_EXIT), "Combat preparation finishes")
	await advance(3)
	check(player.assigned_animation == "P1_Combat_Walk", "Angry departure uses the combat walk")
	check(await until(func(): return a.state == a.State.ATTACKING), "Prisoner reaches attack range")
	check(a.attacks_made == 0 and player.assigned_animation == "P1_Punch_Combo", "Attack wind-up has no immediate contact event")
	check(await until(func(): return a.attacks_made > 0, 90), "Attack contact occurs during the strike animation")
	check(await until(func(): return player.assigned_animation == "P1_Kick_Front_R", 240), "Combat progresses to the kick animation")
	check(await until(func(): return player.assigned_animation == "P1_Boxing_Flurry", 240), "Combat progresses to the boxing animation")
	check(not is_instance_valid(debris), "Discarded tray expires instead of accumulating in endless play")
	# Reset while a new tray is airborne, before its lifetime expires.
	manager.make_angry(b, "Test reset")
	check(await until(func(): return is_instance_valid(b.thrown_tray), 180), "Second prisoner independently throws its tray")
	var second_debris = b.thrown_tray
	room.reset_lab()
	await advance(3)
	check(not is_instance_valid(second_debris), "Reset removes discarded trays as well as prisoners")
	room.queue_free()
	await advance(3)
	check(get_nodes_in_group("DiscardedPrisonerTrays").is_empty(), "Scene cleanup leaves no discarded trays behind")
	print("Model scenario checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
