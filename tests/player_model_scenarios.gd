extends SceneTree

var checks := 0
var failures := 0
var player
var stage: Node3D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await physics_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().is_empty(): return
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = player.position + Vector3(2.4, 1.3, -3.7)
	camera.look_at(player.position)
	camera.make_current()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(name + ".png"))
	camera.queue_free()
	player.camera.make_current()

func capture_feet(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().is_empty(): return
	var old_pitch: float = player._look_pitch
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(0, 1000)
	player._unhandled_input(mouse)
	player._update_view()
	player.camera.make_current()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(name + ".png"))
	player._look_pitch = old_pitch
	player._update_view()

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40, 1, 40)
	collision.shape = shape
	floor_body.add_child(collision)
	stage.add_child(floor_body)
	floor_body.position.y = -0.5
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	floor_mesh.mesh = box
	floor_body.add_child(floor_mesh)
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-40, -30, 0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.18, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	stage.add_child(environment)
	player = load("res://scenes/characters/player/player.tscn").instantiate()
	stage.add_child(player)
	player.position.y = 1.04
	await frames(12)
	check(player.body_mesh.get_node("PlayerDuck") != null and not player.has_node("MeshInstance3D"), "Duck replaces capsule visual")
	var meshes = player.body_mesh.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == 5, "All five duck meshes present")
	var hidden_from_fps := true
	var visible_feet := 0
	for mesh in meshes:
		if mesh.name == &"Player | Foot_L" or mesh.name == &"Player | Foot_R":
			if mesh.visible and (mesh.layers & player.camera.cull_mask) != 0: visible_feet += 1
		else:
			hidden_from_fps = hidden_from_fps and mesh.visible and (mesh.layers & player.camera.cull_mask) == 0
	check(hidden_from_fps and visible_feet == 2, "Both feet visible in FPS while head and body stay excluded")
	check(player.body_animation.current_animation == "Idle", "Stationary player uses Idle")
	check(player.body_animation.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR and player.body_animation.get_animation("Walk").loop_mode == Animation.LOOP_LINEAR, "Idle and Walk loop")
	await capture("duck_idle")
	await capture_feet("feet_idle")
	var skeleton: Skeleton3D = player.body_mesh.find_child("Skeleton3D", true, false)
	var foot := skeleton.find_bone("foot.L")
	var idle_foot := skeleton.get_bone_pose(foot)
	Input.action_press("up")
	await frames(15)
	check(player.body_animation.current_animation == "Walk", "Walking selects Walk")
	check(not skeleton.get_bone_pose(foot).is_equal_approx(idle_foot), "Walk actually animates the foot bone")
	await capture("duck_walk")
	await capture_feet("feet_walk")
	await frames(65)
	check(player.body_animation.is_playing() and player.body_animation.current_animation == "Walk", "Walking continues beyond one animation cycle")
	Input.action_release("up")
	await frames(4)
	check(player.body_animation.current_animation == "Idle", "Stopping returns to Idle")
	player.head.rotation.y = 0.7
	await frames(3)
	check(is_equal_approx(player.body_mesh.rotation.y, 0.7), "Body follows viewing yaw")
	player.try_dash(Vector3.FORWARD)
	await frames(4)
	check(player.body_animation.current_animation == "Walk" and player.body_animation.speed_scale > 1.0, "Dash increases walk playback speed")
	await capture_feet("feet_dash")
	var phase: float = player.body_animation.current_animation_position
	paused = true
	for i in 8: await process_frame
	check(player.body_animation.current_animation_position == phase, "Pause freezes animation")
	paused = false
	player.take_damage(1000)
	check(not player.body_mesh.visible and not player.body_animation.is_playing(), "Knockout hides standing model and pauses animation")
	await frames(ceili(player.stun_duration * 60.0) + 12)
	check(not player.unconscious and player.body_mesh.visible and player.body_animation.current_animation == "Idle" and player.body_animation.is_playing(), "Recovery restores visible animated duck")
	var original = load("res://assets/models/characters/Player_Duck.glb").instantiate()
	check(original.get_node("AnimationPlayer").get_animation("Walk").loop_mode == Animation.LOOP_NONE, "Imported animation resource is not modified globally")
	original.free()
	stage.queue_free()
	await frames(3)
	print("Player model checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
