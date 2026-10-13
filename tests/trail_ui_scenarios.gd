extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await process_frame
func run() -> void:
	var comic = load("res://scenes/cutscenes/intro_cutscene.tscn").instantiate()
	root.add_child(comic)
	check(not comic.has_node("Hint"), "Page number and reading hint removed from scene")
	check(is_equal_approx(comic.auto_button.modulate.a, 0.35), "Auto off is faint")
	comic.auto_button.set_pressed(true)
	check(is_equal_approx(comic.auto_button.modulate.a, 1), "Auto on is full strength")
	comic.auto_button.set_pressed(false)
	check(is_equal_approx(comic.auto_button.modulate.a, 0.35), "Turning auto off restores faint style")
	comic.queue_free()
	await frames(2)
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var body := RigidBody3D.new()
	body.freeze = true
	world.add_child(body)
	var ball := MeshInstance3D.new()
	ball.mesh = SphereMesh.new()
	ball.scale = Vector3.ONE * 0.2
	body.add_child(ball)
	var impact = load("res://scripts/combat/throw_impact.gd").ensure(body)
	impact.arm(null, 1, [body] as Array[PhysicsBody3D])
	impact.set_physics_process(false)
	var trail = impact.trail
	trail.set_physics_process(false)
	check(trail != null and trail.top_level, "Throw creates a world-space trail")
	for i in 10:
		body.position = Vector3(-2 + i * 0.2, sin(i * 0.15), 0)
		trail._physics_process(1.0/60)
	check(trail.visible and trail.mesh.get_surface_count() == 1, "Moving item produces ribbon geometry")
	check(trail.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "White trail remains visible without scene lighting")
	var sample: Vector3 = trail.points[2]
	body.rotation.y = 1.0
	check(trail.points[2] == sample and trail.global_basis.is_equal_approx(Basis.IDENTITY), "Item spin does not rotate trail history")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/yaima/Documents/test-codex-connect/.quackcook-trail-ui/trail.png")
	trail._physics_process(0.3)
	check(not trail.visible and trail.points.is_empty(), "Stationary item tail fades out")
	body.position += Vector3.RIGHT
	trail._physics_process(0.016)
	body.position += Vector3.RIGHT
	trail._physics_process(0.016)
	impact.disarm()
	check(not trail.visible and trail.points.is_empty() and not trail.is_physics_processing(), "Pickup or recovery disarms and clears trail")
	impact.arm(null, 1, [body] as Array[PhysicsBody3D])
	impact.set_physics_process(false)
	trail.set_physics_process(false)
	check(impact.trail == trail and trail.points.size() == 1, "Next throw reuses effect without old history")
	body.position += Vector3(100, 0, 0)
	trail._physics_process(0.016)
	check(trail.points.is_empty() and not trail.visible, "Teleport cannot draw a long streak")
	world.queue_free()
	await frames(3)
	print("Trail and UI checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
