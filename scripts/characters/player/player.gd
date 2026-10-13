extends CharacterBody3D

signal health_changed(current: float, maximum: float)
signal unconscious_started
signal recovered

const RagdollScene = preload("res://scenes/characters/player/player_ragdoll.tscn")
## Layer 20 is excluded only by this player's first-person camera.
const PLAYER_MODEL_LAYER: int = 1 << 19
@export_group("Model Animation")
@export_range(0.0, 0.5) var animation_blend_time: float = 0.15
@export_range(0.1, 3.0) var walk_animation_speed: float = 1.0
@export_group("Dash")
@export_range(5.0, 30.0) var dash_speed: float = 12.0
@export_range(0.05, 1.0) var dash_duration: float = 0.18
## Delay between dash starts. Holding Shift does not repeat the dash.
@export_range(0.0, 5.0) var dash_cooldown: float = 0.8
@export var dash_ground_only: bool = true
@export_group("Health")
@export_range(1.0, 1000.0) var max_health: float = 100.0
@export_range(0.0, 10.0) var invulnerability_duration: float = 0.5
@export_range(0.1, 30.0) var stun_duration: float = 2.0
@export_group("Hit Feedback")
## Horizontal speed away from the attacker, in metres per second.
@export_range(0.0, 10.0) var hit_push_speed: float = 2.8
@export_range(1.0, 40.0) var hit_push_deceleration: float = 10.0
@export_range(0.0, 30.0) var hit_turn_min_degrees: float = 5.0
@export_range(0.0, 45.0) var hit_turn_max_degrees: float = 12.0
@export_range(0.01, 0.3) var hit_turn_attack_time: float = 0.045
@export_range(0.05, 1.0) var hit_turn_return_time: float = 0.3
@export_group("Knockout Ragdoll")
@export_range(0.0, 10.0) var knockout_push_speed: float = 3.2
@export_range(0.0, 5.0) var knockout_up_speed: float = 0.7
@export_range(0.0, 8.0) var knockout_tumble_speed: float = 2.0

var health: float = 100.0
var invulnerability_remaining: float = 0.0
var stun_remaining: float = 0.0
var controls_enabled: bool = true
var unconscious: bool = false
var knockback_velocity := Vector3.ZERO
var dash_remaining: float = 0.0
var dash_cooldown_remaining: float = 0.0
var _dash_direction := Vector3.ZERO
var ragdoll: Node3D
var _hit_rng := RandomNumberGenerator.new()
var _hit_turn := Vector3.ZERO
var _hit_elapsed: float = 100.0
var _look_pitch: float = 0.0
var _standing_camera: Transform3D
var _standing_layer: int
var _standing_mask: int
var _standing_mesh_visible: bool
var _fall_origin := Vector3.ZERO
var _last_grounded_position := Vector3.ZERO

@onready var health_bar: ProgressBar = $HealthHUD/HealthBar
@onready var health_label: Label = $HealthHUD/HealthLabel
@onready var blur: ColorRect = $HealthHUD/UnconsciousBlur
@onready var stun_label: Label = $HealthHUD/StunLabel
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var body_mesh: Node3D = $Visuals
@onready var body_animation: AnimationPlayer = $Visuals/PlayerDuck/AnimationPlayer
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.005
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
var t_bob: float = 0.0

func _ready() -> void:
	_hit_rng.randomize()
	_standing_camera = camera.transform
	_look_pitch = camera.rotation.x
	_standing_layer = collision_layer
	_standing_mask = collision_mask
	_standing_mesh_visible = body_mesh.visible
	_last_grounded_position = global_position
	_setup_model()
	reset_health()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func can_control() -> bool:
	return not SceneTransition.busy and controls_enabled and not unconscious and not get_tree().paused

func is_incapacitated() -> bool:
	return unconscious

func take_damage(amount: float, source: Node3D = null) -> bool:
	if not is_finite(amount) or amount <= 0.0 or unconscious or invulnerability_remaining > 0.0 or get_tree().paused: return false
	var direction := _away_from(source)
	health = maxf(0.0, health - amount)
	AudioManager.hurt(self, false)
	invulnerability_remaining = invulnerability_duration
	knockback_velocity = direction * hit_push_speed
	_start_hit_turn()
	if health <= 0.0: _begin_unconscious(direction)
	health_changed.emit(health, max_health)
	_update_health_ui()
	return true

func _away_from(source: Node3D) -> Vector3:
	var direction := global_position - source.global_position if is_instance_valid(source) else head.global_basis.z
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = head.global_basis.z
		direction.y = 0.0
	return direction.normalized()

func _start_hit_turn() -> void:
	var strength := deg_to_rad(_hit_rng.randf_range(minf(hit_turn_min_degrees, hit_turn_max_degrees), maxf(hit_turn_min_degrees, hit_turn_max_degrees)))
	var side := -1.0 if _hit_rng.randf() < 0.5 else 1.0
	_hit_turn = Vector3(_hit_rng.randf_range(-0.55, 0.55), side, -side * _hit_rng.randf_range(0.2, 0.5)) * strength
	_hit_elapsed = 0.0

func _begin_unconscious(direction: Vector3) -> void:
	unconscious = true
	dash_remaining = 0.0
	stun_remaining = stun_duration
	_fall_origin = global_position
	head.cancel_interaction()
	# Disable standing collisions so the controller cannot fight the ragdoll.
	collision_layer = 0
	collision_mask = 0
	body_mesh.hide()
	body_animation.pause()
	ragdoll = RagdollScene.instantiate()
	add_child(ragdoll)
	ragdoll.global_transform = Transform3D(Basis(Vector3.UP, head.global_rotation.y), global_position)
	var launch := direction * knockout_push_speed + Vector3.UP * knockout_up_speed
	launch += Vector3(velocity.x, 0.0, velocity.z).limit_length(SPEED) * 0.25
	ragdoll.start(self, head.carried_object, launch, Vector3.UP.cross(direction) * knockout_tumble_speed)
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	_hit_turn = Vector3.ZERO
	unconscious_started.emit()

func reset_health() -> void:
	if unconscious and not _recover(): return
	dash_remaining = 0.0
	dash_cooldown_remaining = 0.0
	health = max_health
	unconscious = false
	stun_remaining = 0.0
	invulnerability_remaining = 0.0
	knockback_velocity = Vector3.ZERO
	_hit_turn = Vector3.ZERO
	_hit_elapsed = 100.0
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	health_changed.emit(health, max_health)
	_update_health_ui()

func _update_health(delta: float) -> void:
	invulnerability_remaining = maxf(0.0, invulnerability_remaining - delta)
	_hit_elapsed += delta
	if unconscious:
		stun_remaining = maxf(0.0, stun_remaining - delta)
		if stun_remaining <= 0.0: _recover()
	_update_health_ui()

func _recover() -> bool:
	var standing_point := _find_recovery_position()
	# Retry if all candidates are occupied instead of embedding the standing capsule.
	if not standing_point.is_finite(): return false
	global_position = standing_point
	if is_instance_valid(ragdoll):
		ragdoll.stop()
		ragdoll.queue_free()
	ragdoll = null
	collision_layer = _standing_layer
	collision_mask = _standing_mask
	body_mesh.visible = _standing_mesh_visible
	body_animation.play("Idle", animation_blend_time)
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	unconscious = false
	stun_remaining = 0.0
	health = max_health
	AudioManager.hurt(self, false)
	invulnerability_remaining = invulnerability_duration
	camera.transform = _standing_camera
	camera.rotation.x = _look_pitch
	t_bob = 0.0
	health_changed.emit(health, max_health)
	recovered.emit()
	return true

func _find_recovery_position() -> Vector3:
	var center: Vector3 = ragdoll.center() if is_instance_valid(ragdoll) else global_position
	var candidates: Array[Vector3] = [center]
	for radius in [0.65, 1.3, 1.95]:
		for i in 8:
			var angle := TAU * float(i) / 8.0
			candidates.append(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
	candidates.append(_fall_origin)
	candidates.append(_last_grounded_position)
	var space := get_world_3d().direct_space_state
	var excluded: Array[RID] = [get_rid()]
	if is_instance_valid(ragdoll): excluded.append_array(ragdoll.body_rids())
	if head.carried_object is CollisionObject3D: excluded.append(head.carried_object.get_rid())
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = collider.shape
	shape_query.collision_mask = _standing_mask
	shape_query.exclude = excluded
	shape_query.margin = 0.015
	var half_height: float = collider.shape.height * 0.5
	for candidate in candidates:
		var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 1.5, candidate + Vector3.DOWN * 4.0, 1, excluded)
		var floor_hit := space.intersect_ray(ray)
		if floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP) < cos(floor_max_angle): continue
		var point: Vector3 = floor_hit.position + Vector3.UP * (half_height + 0.04 - collider.position.y)
		# Prevent getting up on a countertop above the original floor.
		if point.y > _fall_origin.y + 0.45: continue
		shape_query.transform = Transform3D(global_basis, point) * collider.transform
		if not space.intersect_shape(shape_query, 1).is_empty(): continue
		# Also reject nearby clear floor on the other side of a wall.
		var sweep := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.15
		sweep.shape = sphere
		sweep.collision_mask = _standing_mask & ~4
		sweep.exclude = excluded
		sweep.transform.origin = center
		sweep.motion = point - center
		if space.cast_motion(sweep)[0] < 0.99: continue
		return point
	return Vector3.INF

func _update_health_ui() -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	health_label.text = "HP %d / %d" % [ceili(health), ceili(max_health)]
	blur.visible = unconscious
	stun_label.visible = unconscious
	stun_label.text = "UNCONSCIOUS  %.1f s" % stun_remaining

func _unhandled_input(event: InputEvent) -> void:
	if not can_control(): return
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY * AppSettings.mouse_sensitivity)
		_look_pitch = clampf(_look_pitch - event.relative.y * SENSITIVITY * AppSettings.mouse_sensitivity, deg_to_rad(-80), deg_to_rad(60))

func try_dash(direction: Vector3) -> bool:
	if not can_control() or dash_remaining > 0.0 or dash_cooldown_remaining > 0.0:
		return false
	if dash_ground_only and not is_on_floor(): return false
	direction.y = 0.0
	if direction.is_zero_approx():
		direction = -head.global_basis.z
		direction.y = 0.0
	_dash_direction = direction.normalized()
	AudioManager.cue("dash", self)
	dash_remaining = dash_duration
	dash_cooldown_remaining = dash_cooldown
	return true

func _physics_process(delta: float) -> void:
	_update_health(delta)
	dash_cooldown_remaining = maxf(0.0, dash_cooldown_remaining - delta)
	if not can_control(): dash_remaining = 0.0
	if unconscious:
		if is_instance_valid(ragdoll):
			global_position = ragdoll.center()
			camera.global_transform = ragdoll.view_transform()
		return
	if is_on_floor(): _last_grounded_position = global_position
	if not is_on_floor(): velocity += get_gravity() * delta
	if can_control() and Input.is_action_just_pressed("jump") and is_on_floor(): velocity.y = JUMP_VELOCITY
	var input_dir := Input.get_vector("left", "right", "up", "down") if can_control() else Vector2.ZERO
	var direction := (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if Input.is_action_just_pressed("dash"): try_dash(direction)
	if is_on_floor() or not can_control():
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = lerpf(velocity.x, direction.x * SPEED, minf(delta * 4.0, 1.0))
		velocity.z = lerpf(velocity.z, direction.z * SPEED, minf(delta * 4.0, 1.0))
	# Separate external momentum so normal WASD deceleration cannot erase a hit.
	var movement_velocity := velocity
	if dash_remaining > 0.0:
		# Keep dash separate from walking/air momentum; sweep using normal collisions.
		var dash_weight := minf(dash_remaining / delta, 1.0)
		velocity.x = lerpf(velocity.x, _dash_direction.x * dash_speed, dash_weight)
		velocity.z = lerpf(velocity.z, _dash_direction.z * dash_speed, dash_weight)
		dash_remaining = maxf(0.0, dash_remaining - delta)
	velocity += knockback_velocity
	move_and_slide()
	_update_model(direction)
	velocity.x = movement_velocity.x
	velocity.z = movement_velocity.z
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, hit_push_deceleration * delta)
	t_bob += delta * direction.length() * SPEED * float(is_on_floor()) * float(can_control())
	_update_view()

func _setup_model() -> void:
	for mesh in body_mesh.find_children("*", "MeshInstance3D", true, false):
		# Feet share the animated skeleton, but remain visible in first person.
		var is_foot := mesh.name == &"Player | Foot_L" or mesh.name == &"Player | Foot_R"
		mesh.layers = 1 if is_foot else PLAYER_MODEL_LAYER
	# Duplicate the imported library so other instances and the GLB stay untouched.
	var library := body_animation.get_animation_library("").duplicate(true) as AnimationLibrary
	body_animation.remove_animation_library("")
	body_animation.add_animation_library("", library)
	for animation_name in ["Idle", "Walk"]:
		body_animation.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	body_animation.play("Idle")
	body_animation.advance(0.0)
	body_mesh.rotation.y = head.rotation.y

func _update_model(input_direction: Vector3) -> void:
	body_mesh.rotation.y = head.rotation.y
	var actual_velocity := get_real_velocity()
	var horizontal_speed := Vector2(actual_velocity.x, actual_velocity.z).length()
	# Walking into a wall, being knocked back, or jumping should not run the walk cycle.
	var moving := can_control() and is_on_floor() and horizontal_speed > 0.1
	moving = moving and (not input_direction.is_zero_approx() or dash_remaining > 0.0)
	var animation_name: StringName = &"Walk" if moving else &"Idle"
	body_animation.speed_scale = walk_animation_speed * clampf(horizontal_speed / SPEED, 0.5, 2.0) if moving else 1.0
	if body_animation.current_animation != animation_name:
		body_animation.play(animation_name, animation_blend_time)

func _update_view() -> void:
	var weight: float = 0.0
	if _hit_elapsed < hit_turn_attack_time:
		weight = sin(_hit_elapsed / maxf(hit_turn_attack_time, 0.001) * PI * 0.5)
	else:
		var t := clampf((_hit_elapsed - hit_turn_attack_time) / maxf(hit_turn_return_time, 0.001), 0.0, 1.0)
		weight = 1.0 - smoothstep(0.0, 1.0, t)
	camera.position = _standing_camera.origin + _headbob(t_bob)
	camera.rotation = Vector3(_look_pitch, 0.0, 0.0) + _hit_turn * weight
	camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-85), deg_to_rad(75))

func _headbob(time: float) -> Vector3:
	return Vector3(cos(time * BOB_FREQ / 2) * BOB_AMP, sin(time * BOB_FREQ) * BOB_AMP, 0.0)
