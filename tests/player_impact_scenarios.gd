extends SceneTree

var checks := 0
var failures := 0
var player: Node3D
var stage: Node3D
var source: Node3D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func solid(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	stage.add_child(body)
	body.position = position
	return body
func standing_clear() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player.collider.shape
	query.transform = player.collider.global_transform
	query.exclude = [player.get_rid()]
	query.collision_mask = 5
	return player.get_world_3d().direct_space_state.intersect_shape(query).is_empty()
func capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(name + ".png"))

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	solid(Vector3(30, 1, 30), Vector3(0, -0.5, 0))
	player = load("res://scenes/Player.tscn").instantiate()
	stage.add_child(player)
	player.position = Vector3(0, 1.04, 0)
	source = Node3D.new()
	stage.add_child(source)
	source.position = Vector3(0, 1, -2)
	await frames(12)
	check(player.is_on_floor() and player.can_control(), "Player starts grounded and controllable")
	var before := player.global_position
	check(player.take_damage(10, source) and player.health == 90, "Normal hit deals damage")
	var turn: Vector3 = player._hit_turn
	check(player.knockback_velocity.z > 0 and absf(player.knockback_velocity.x) < 0.001, "Push points away from attacker")
	check(not player.take_damage(10, source) and player._hit_turn == turn, "Immunity prevents repeated HP, push and view feedback")
	await frames(4)
	check(absf(player.camera.rotation.y) > 0.01 and player.camera.h_offset == 0 and player.camera.v_offset == 0, "Accepted hit turns the view without projection shake")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(8, 4)
	player._unhandled_input(mouse)
	await frames(35)
	check(player.global_position.z > before.z + 0.1 and player.global_position.z < before.z + 0.9, "Hit produces a small actual backward displacement")
	check(player.knockback_velocity.is_zero_approx(), "Push decays to zero")
	check(absf(player.camera.rotation.y) < 0.001 and absf(player.camera.rotation.z) < 0.001 and absf(player.camera.rotation.x + 0.02) < 0.001, "View settles while preserving mouse input during impact")
	var left := false
	var right := false
	var magnitudes: Array[float] = []
	player._hit_rng.seed = 42
	for i in 16:
		player.invulnerability_remaining = 0
		player.take_damage(1, source)
		left = left or player._hit_turn.y < 0
		right = right or player._hit_turn.y > 0
		magnitudes.append(absf(player._hit_turn.y))
	check(left and right and not is_equal_approx(magnitudes.min(), magnitudes.max()), "Hit direction and strength vary per accepted hit")
	await frames(40)
	player.invulnerability_remaining = 0
	var pan = load("res://scenes/prefebs/maps/pan.tscn").instantiate()
	stage.add_child(pan)
	player.head.pick_up(pan)
	player.head.last_hovered_object = null
	player.head._handle_interact_pressed()
	player.head._update_throw_charge(0.4)
	var eye_before: float = player.camera.global_position.y
	var origin: Vector3 = player.global_position
	check(player.take_damage(1000, source), "Lethal hit accepted")
	check(player.unconscious and not player.can_control() and not player.head.interaction_allowed(), "Stun locks movement and interaction")
	check(player.blur.visible and not player.head.is_charging and player.head.carried_object == pan, "Stun blurs and cancels throw charge while retaining held item")
	check(player.ragdoll.bodies.size() == 6 and player.collision_layer == 0 and player.collision_mask == 0, "Six jointed bodies replace standing collisions")
	var fall = player.ragdoll
	var look_before: float = player._look_pitch
	player._unhandled_input(mouse)
	check(player._look_pitch == look_before, "Mouse look is disabled during ragdoll")
	check(not player.take_damage(1000, source), "Unconscious player ignores further hits")
	await frames(55)
	check(player.unconscious and player.camera.global_position.y < eye_before - 0.4, "Camera follows real fall toward the ground")
	check(player.ragdoll.torso.global_basis.y.dot(Vector3.UP) < 0.85, "Ragdoll topples rather than remaining upright")
	check(player.global_position.distance_to(origin) > 0.25, "Knockout includes actual physics displacement")
	var ragdoll_pose: Transform3D = fall.torso.global_transform
	var timer: float = player.stun_remaining
	paused = true
	for i in 10: await process_frame
	check(fall.torso.global_transform.is_equal_approx(ragdoll_pose) and player.stun_remaining == timer, "Pause freezes ragdoll and stun timer")
	paused = false
	await frames(85)
	check(not player.unconscious and player.health == player.max_health and player.can_control(), "Stun ends with full HP and restored controls")
	check(player.ragdoll == null and not is_instance_valid(fall), "Temporary ragdoll is removed after recovery")
	check(player.collision_layer == 1 and player.collision_mask == 5 and standing_clear(), "Standing collision restored without overlap")
	check(not player.blur.visible and player.camera.rotation.z == 0 and player.camera.position.y > -0.1, "Recovery restores upright FPS view and clears blur")
	check(player.invulnerability_remaining > 0, "Recovery grants existing invulnerability window")
	player.head._handle_interact_released()
	check(player.head.carried_object == pan, "Old charged input cannot throw on recovery")
	player.head.drop_object()
	pan.queue_free()
	var walk_start: Vector3 = player.global_position
	Input.action_press("right")
	await frames(12)
	Input.action_release("right")
	check(player.global_position.distance_to(walk_start) > 0.3, "Walking works after recovery")
	# Strong push into a wall must stay on this side, then recover without clipping.
	var wall := solid(Vector3(8, 4, 0.3), Vector3(0, 2, 4))
	player.global_position = Vector3(0, 1.04, 3.15)
	player.velocity = Vector3.ZERO
	await frames(12)
	source.global_position = Vector3(0, 1, 1)
	player.invulnerability_remaining = 0
	player.take_damage(10, source)
	await frames(40)
	check(player.global_position.z < 3.36, "Nonlethal knockback respects wall collision")
	player.invulnerability_remaining = 0
	player.take_damage(1000, source)
	await frames(150)
	check(not player.unconscious and standing_clear() and player.global_position.z < 3.36, "Ragdoll recovers on the correct side of the wall")
	wall.queue_free()
	stage.queue_free()
	await frames(3)
	# Exercise actual kitchen geometry, a held item, and scene teardown mid-stun.
	stage = load("res://scenes/main.tscn").instantiate()
	stage.get_node("QueueLayout").auto_start_run = false
	root.add_child(stage)
	current_scene = stage
	player = stage.get_node("Player")
	await frames(20)
	player.take_damage(1000)
	await frames(65)
	await capture("player_unconscious")
	check(player.unconscious and player.camera.global_transform.is_finite(), "Ragdoll works inside the actual kitchen")
	await frames(85)
	check(not player.unconscious and player.can_control() and standing_clear(), "Player safely gets up in the actual kitchen")
	await capture("player_recovered")
	player.invulnerability_remaining = 0
	player.take_damage(1000)
	await frames(4)
	var final_body = player.ragdoll
	stage.queue_free()
	await frames(3)
	check(not is_instance_valid(final_body), "Unloading scene mid-stun frees the ragdoll")
	print("Player impact checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
