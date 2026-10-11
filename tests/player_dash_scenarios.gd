extends SceneTree

var checks := 0
var failures := 0
var stage: Node3D
var player

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func solid(size: Vector3, point: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	stage.add_child(body)
	body.position = point

func reset_player() -> void:
	Input.action_release("dash")
	Input.action_release("right")
	Input.action_release("up")
	player.reset_health()
	player.global_position = Vector3(0, 1.04, 0)
	player.velocity = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	await frames(10)

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	solid(Vector3(40, 1, 40), Vector3(0, -0.5, 0))
	player = load("res://scenes/characters/player/player.tscn").instantiate()
	stage.add_child(player)
	await reset_player()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SHIFT
	check(InputMap.event_is_action(key, "dash"), "Shift is mapped to dash")
	var start: Vector3 = player.position
	Input.action_press("dash")
	await frames(16)
	check(player.position.z < start.z - 2.0 and player.position.z > start.z - 2.4, "Stationary Shift dashes forward for the configured distance")
	check(player.dash_remaining == 0.0 and player.velocity.length() < 0.01, "Dash ends without lingering velocity")
	check(not player.try_dash(Vector3.RIGHT), "Cooldown prevents another dash")
	var stopped: Vector3 = player.position
	await frames(60)
	check(player.position.distance_to(stopped) < 0.02, "Holding Shift does not automatically repeat after cooldown")
	Input.action_release("dash")
	await frames(2)
	Input.action_press("dash")
	await frames(3)
	check(player.dash_remaining > 0.0, "Releasing and pressing Shift starts another dash")
	await reset_player()
	Input.action_press("right")
	Input.action_press("dash")
	await frames(5)
	check(player.position.x > 0.5 and absf(player.position.z) < 0.02, "WASD chooses dash direction")
	player.head.rotation.y = PI / 2.0
	Input.action_release("right")
	await frames(5)
	check(player.position.x > 1.4 and absf(player.position.z) < 0.02, "Turning the view does not redirect an active dash")
	await reset_player()
	check(player.try_dash(Vector3(1, 0, -1)), "Diagonal dash accepted")
	await frames(16)
	check(Vector2(player.position.x, player.position.z).length() < 2.4 and player.position.x > 1.3, "Diagonal dash has the same total speed")
	await reset_player()
	player.head.rotation.y = PI / 2.0
	player.try_dash(Vector3.ZERO)
	await frames(16)
	check(player.position.x < -2.0 and absf(player.position.z) < 0.02, "Idle dash follows the facing direction")
	await reset_player()
	player.position.y = 5.0
	await frames(2)
	check(not player.try_dash(Vector3.FORWARD), "Ground-only dash rejects an airborne start")
	player.dash_ground_only = false
	check(player.try_dash(Vector3.FORWARD), "Inspector option allows air dash")
	await frames(5)
	check(player.velocity.y < 0.0, "Dash retains gravity")
	player.dash_ground_only = true
	await reset_player()
	player.controls_enabled = false
	check(not player.try_dash(Vector3.FORWARD), "Disabled controls block dash")
	player.controls_enabled = true
	player.try_dash(Vector3.FORWARD)
	await frames(2)
	paused = true
	var remaining: float = player.dash_remaining
	var cooldown: float = player.dash_cooldown_remaining
	stopped = player.position
	for i in 8: await process_frame
	check(player.position == stopped and player.dash_remaining == remaining and player.dash_cooldown_remaining == cooldown, "Pause freezes movement and both dash timers")
	check(not player.try_dash(Vector3.FORWARD), "Dash cannot start while paused")
	paused = false
	player.controls_enabled = false
	await frames(2)
	check(player.dash_remaining == 0.0, "Disabling controls cancels an active dash")
	player.controls_enabled = true
	await reset_player()
	player.try_dash(Vector3.FORWARD)
	check(player.take_damage(10) and player.health == 90.0, "Dash does not grant invulnerability")
	check(player.knockback_velocity.length() > 0.0, "Hit knockback still applies during dash")
	player.invulnerability_remaining = 0.0
	player.take_damage(1000)
	check(player.unconscious and player.dash_remaining == 0.0 and not player.try_dash(Vector3.FORWARD), "Knockout cancels dash and blocks a new dash")
	await frames(ceili(player.stun_duration * 60.0) + 10)
	check(not player.unconscious and player.try_dash(Vector3.FORWARD), "Dash works again after recovery")
	await reset_player()
	solid(Vector3(8, 4, 0.2), Vector3(0, 2, -1.5))
	await frames(2)
	player.try_dash(Vector3.FORWARD)
	await frames(16)
	check(player.position.z > -1.0 and player.position.z < -0.5, "Dash stops at a wall without crossing it")
	stage.queue_free()
	await frames(3)
	print("Player dash checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
