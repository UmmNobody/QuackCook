extends Node3D

signal interact_object(target: Node)
signal object_focused(target: Node)
signal charge_updated(progress_ratio: float)

@export var follow_speed: float = 20.0

# Throwing
@export var min_throw_force: float = 5.0
@export var max_throw_force: float = 25.0
@export var charge_rate: float = 20.0
@export var hold_threshold: float = 0.3

@onready var ray_cast: RayCast3D = $Camera3D/RayCast3D
@onready var carry_position: Marker3D = $Camera3D/CarryObjectMarker

var carried_object: RigidBody3D = null
var last_hovered_object: Node = null

var current_throw_force: float = min_throw_force
var hold_timer: float = 0.0

var is_holding_button: bool = false
var is_charging: bool = false

var player:Node3D = null

func _ready() -> void:
	player = get_tree().get_first_node_in_group("Player")

func _process(delta: float) -> void:
	_check_hovered_object()
	_update_throw_charge(delta)


func _physics_process(delta: float) -> void:
	if carried_object == null:
		return

	var weight: float = clamp(follow_speed * delta, 0.0, 1.0)

	# Follow position
	var target_pos := carry_position.global_position
	carried_object.global_position = carried_object.global_position.lerp(
		target_pos,
		weight
	)

	# Follow rotation
	var target_basis := carry_position.global_transform.basis
	var current_basis := carried_object.global_transform.basis

	carried_object.global_transform.basis = current_basis.slerp(
		target_basis,
		weight
	)

	carried_object.linear_velocity = Vector3.ZERO
	carried_object.angular_velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drop"):
		drop_object()
	
	elif event.is_action_pressed("Interact"):
		_handle_interact_pressed()

	elif event.is_action_released("Interact"):
		_handle_interact_released()


func _handle_interact_pressed() -> void:
	# Carry something and hover object have interact_with()
	if last_hovered_object and last_hovered_object.has_method("interact_with"):
		var is_handled: bool = last_hovered_object.interact_with(carried_object, self)
		if is_handled:
			return
	
	# Dont Carry anything
	if carried_object == null:
		if last_hovered_object:
			# Pick something
			if last_hovered_object.is_in_group("Pickable") and last_hovered_object is RigidBody3D:
				pick_up(last_hovered_object as RigidBody3D)
			# Interact with something
			elif last_hovered_object.is_in_group("Interactable") and last_hovered_object.has_method("_interact"):
				last_hovered_object._interact()
		return
	
	# Carry Somthing and charge to throw
	is_holding_button = true
	hold_timer = 0.0
	current_throw_force = min_throw_force


func _handle_interact_released() -> void:
	if carried_object == null or not is_holding_button:
		return

	if is_charging:
		throw_object(current_throw_force)

	_reset_throw_state()


func _update_throw_charge(delta: float) -> void:
	if not is_holding_button or carried_object == null:
		return

	hold_timer += delta

	if hold_timer < hold_threshold:
		return

	is_charging = true

	current_throw_force = min(current_throw_force + charge_rate * delta,max_throw_force)
	var progress := (current_throw_force - min_throw_force) / (max_throw_force - min_throw_force)

	charge_updated.emit(progress)


func _check_hovered_object() -> void:
	var current_target: Node = null

	if ray_cast.is_colliding():
		var collider := ray_cast.get_collider()

		if collider and collider.is_in_group("Focusable"):
			current_target = collider

	if current_target == last_hovered_object:
		return

	last_hovered_object = current_target
	object_focused.emit(last_hovered_object)


func pick_up(object: RigidBody3D) -> void:
	if object is Pan:
		var pan := object as Pan
		if pan.is_on_stove:
			pan.remove_from_stove()
	
	carried_object = object
	carried_object.freeze = true
	
	if player:
		carried_object.add_collision_exception_with(player)


func drop_object() -> void:
	if carried_object == null:
		return

	if player:
		carried_object.remove_collision_exception_with(player)

	carried_object.freeze = false
	carried_object = null


func throw_object(force: float) -> void:
	if carried_object == null:
		return

	var object := carried_object
	var throw_direction := -carry_position.global_transform.basis.z.normalized()
	var throw_vector := throw_direction * force

	drop_object()
	
	if object.has_method("throw"):
		object.throw(throw_vector)
	else:
		object.apply_central_impulse(throw_vector)

func _reset_throw_state() -> void:
	is_holding_button = false
	is_charging = false
	hold_timer = 0.0
	current_throw_force = min_throw_force
	charge_updated.emit(0.0)
