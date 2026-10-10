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
func capture(name: String, position: Vector3, target: Vector3) -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty(): return
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.global_position = position
	cam.look_at(target)
	cam.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(name + ".png"))
	cam.queue_free()
func ray(from: Vector3, to: Vector3, mask: int = 3) -> Dictionary:
	return stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))

func run() -> void:
	stage = load("res://scenes/main.tscn").instantiate()
	stage.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(stage)
	current_scene = stage
	var player = stage.get_node("Actors/Player")
	var head = player.head
	var fridge = stage.get_node("Kitchen/Stations/Fridge")
	var door = stage.get_node("Kitchen/Interactables/PrisonerDoor")
	var contents = fridge.get_node("Contents")
	# Gate tests use a controlled fixture, independent of the level artist's
	# placement/parenting of the production ingredient sources.
	var positions := [Vector3(0,0.25,-0.25), Vector3(0,0.95,-0.3), Vector3(0,1.72,-0.3)]
	var sources := ["chicken", "cabbage", "carrot"]
	for source in stage.get_node("Kitchen/FoodSources").get_children(): source.collision_layer = 0
	for i in sources.size():
		var box = load("res://scenes/props/food_sources/" + sources[i] + "_foodbox.tscn").instantiate()
		box.name = sources[i].capitalize() + "Foodbox"
		box.access_controller = fridge
		contents.add_child(box)
		box.position = positions[i]
		box.scale = Vector3.ONE * 0.8
		if i == 2: box.rotation.z = PI * 0.5
	await frames(12)
	check(not fridge.can_access_contents() and not fridge.motion.target_open, "Fridge starts closed")
	check(contents.get_child_count() == 3, "Fridge fixture has three ingredient sources")
	for box in contents.get_children():
		check(box.access_controller == fridge, box.name + " gate points at fridge")
		box.interact_with(null, head)
		check(head.carried_object == null, box.name + " cannot supply through closed fridge")
	var hit := ray(fridge.to_global(Vector3(0,1.3,3)), fridge.to_global(Vector3(0,1.3,0)))
	check(not hit.is_empty() and hit.collider == fridge.door_body, "Closed fridge leaf blocks interaction ray")
	head.object_focused.emit(fridge.door_body)
	check(fridge.door_mesh.material_overlay != null and fridge.body_mesh.material_overlay != null, "Fridge highlights from its door")
	fridge.interact_with(null, head)
	await frames(30)
	check(not fridge.can_access_contents(), "Contents stay gated during opening")
	var old_rotation: Quaternion = fridge.door_mesh.quaternion
	# Actual rotation is on hinge parent. Reversing should keep its current pose.
	var hinge: Node3D = fridge.door_mesh.get_parent()
	old_rotation = hinge.quaternion
	fridge.interact_with(null, head)
	check(old_rotation.angle_to(hinge.quaternion) < 0.06, "Reversal does not snap fridge hinge")
	await frames(90)
	check(not fridge.motion.target_open and absf(hinge.rotation.y) < 0.01, "Fridge finishes closing")
	fridge.door_body.interact_with(null, head)
	await frames(100)
	check(fridge.can_access_contents(), "Clicking fridge leaf opens fully")
	check(fridge.door_body.global_transform.is_equal_approx(fridge.door_mesh.global_transform), "Fridge collider follows animation")
	head.object_focused.emit(null)
	for box in contents.get_children():
		var target: Vector3 = box.get_node("MeshInstance3D").global_position
		target += Vector3.UP * (0.1 if box.name != "CarrotFoodbox" else 0.0)
		hit = ray(Vector3(6.0, target.y, target.z), target)
		check(not hit.is_empty() and hit.collider == box, box.name + " is reachable by aiming through open fridge")
		head.last_hovered_object = box
		head._handle_interact_pressed()
		check(is_instance_valid(head.carried_object) and not head.is_holding_button, box.name + " supplies one held ingredient without starting throw")
		var food = head.carried_object
		head.drop_object()
		food.queue_free()
		await frames(2)
	await capture("fridge_in_kitchen", Vector3(4.8,2.8,-1.9), Vector3(8.5,2.0,-2.5))
	check(not door.motion.target_open, "Prisoner door starts closed")
	check(not door.has_method("interact_with") and not door.leaf.is_in_group("Interactable"), "Player cannot toggle prisoner door")
	var prisoner = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	stage.add_child(prisoner)
	prisoner.set_physics_process(false)
	prisoner.global_position = door.to_global(Vector3(0,0,-2.4))
	prisoner.velocity = door.global_basis * Vector3(2,0,0)
	await frames(10)
	check(not door.motion.target_open, "Parallel queue traffic does not open door")
	prisoner.velocity = door.global_basis * Vector3(0,0,2.5)
	await frames(40)
	check(door.motion.fully_open(), "Approaching prisoner opens door before crossing")
	check(door.leaf.global_transform.is_equal_approx(door.door_mesh.global_transform), "Door aiming collider follows leaf")
	var start := Transform3D(Basis.IDENTITY, door.to_global(Vector3(0,1.05,1.1)))
	var movement: Vector3 = door.global_basis * Vector3(0,0,-2.2)
	check(player.test_move(start, movement), "Open door still blocks player crossing")
	check(not prisoner.test_move(Transform3D(Basis.IDENTITY, door.to_global(Vector3(0,0,1.1))), movement), "Prisoner physics can cross doorway")
	prisoner.global_position = door.to_global(Vector3(0,0,0))
	prisoner.velocity = Vector3.ZERO
	await frames(40)
	check(door.motion.target_open, "Stationary prisoner in passage keeps door open")
	var second = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	stage.add_child(second)
	second.set_physics_process(false)
	second.global_position = door.to_global(Vector3(0,0,-2.4))
	second.velocity = door.global_basis * Vector3(0,0,2.5)
	prisoner.global_position = Vector3(0,1,0)
	await frames(40)
	check(door.motion.target_open, "Following prisoner keeps door open after first passes")
	await capture("prisoner_door_open", Vector3(-2.7,2.8,-3.5), Vector3(-6.3,2,-5.9))
	second.global_position = Vector3(0,1,2)
	await frames(60)
	check(not door.motion.target_open and not door.motion.player.is_playing(), "Door closes after last prisoner clears")
	second.global_position = door.to_global(Vector3(0,0,2.4))
	second.velocity = door.global_basis * Vector3(0,0,-2.5)
	await frames(40)
	check(door.motion.fully_open(), "Door detects approach from kitchen side too")
	second.queue_free()
	prisoner.queue_free()
	await frames(60)
	check(not door.motion.target_open, "Freed prisoners do not leave door stuck open")
	var rag = load("res://scenes/characters/player/player_ragdoll.tscn").instantiate()
	for body in rag.get_children():
		if body is RigidBody3D: check(body.collision_mask == 9, "Ragdoll body respects player barrier")
	rag.free()
	await capture("prisoner_door_closed", Vector3(-2.7,2.8,-3.5), Vector3(-6.3,2,-5.9))
	# Exercise a real angry prisoner's escape route, not just sensor positions.
	var angry = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	stage.add_child(angry)
	angry.global_position = stage.get_node("Queue/QueueLayout/EscapeRoute/OutsideDoor").global_position
	player.global_position = Vector3(-3, 1.85, -5.9)
	var route: Array[Vector3] = []
	for marker in stage.get_node("Queue/QueueLayout/EscapeRoute").get_children(): route.append(marker.global_position)
	angry.begin_anger(route, player, "Door route test")
	await frames(200)
	check(angry.global_position.x > -5.4, "Real angry prisoner passes from queue into kitchen")
	angry.queue_free()
	await frames(60)
	check(not door.motion.target_open, "Door closes after actual angry prisoner leaves passage")
	# A lethal hit near the door must not throw the player through its fixed barrier.
	player.global_position = Vector3(-5.65, 1.85, -5.9)
	player.velocity = Vector3.ZERO
	await frames(6)
	var attacker := Node3D.new()
	stage.add_child(attacker)
	attacker.global_position = Vector3(-3,1.85,-5.9)
	player.invulnerability_remaining = 0
	player.take_damage(1000, attacker)
	await frames(ceili(player.stun_duration * 60.0) + 8)
	check(not player.unconscious and player.global_position.x > -6.1, "Player ragdoll and recovery remain inside kitchen at prisoner door")
	stage.queue_free()
	await frames(3)
	print("Doors checks: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)

