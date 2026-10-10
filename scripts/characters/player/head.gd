extends Node3D

signal interact_object(target: Node)
signal object_focused(target: Node)
signal charge_updated(progress_ratio: float)

const ThrowImpact = preload("res://scripts/combat/throw_impact.gd")

@export var follow_speed: float = 20.0

# Throwing
@export var min_throw_force: float = 5.0
@export var max_throw_force: float = 25.0
@export var charge_rate: float = 20.0
@export var hold_threshold: float = 0.3
## Damage = incoming linear speed (m/s) multiplied by this value.
@export_range(0.1, 20.0) var throw_damage_per_speed: float = 2.0

@onready var ray_cast: RayCast3D = $Camera3D/RayCast3D
@onready var carry_position: Marker3D = $Camera3D/CarryObjectMarker

var carried_object: Node3D = null
var last_hovered_object: Node = null

var current_throw_force: float = min_throw_force
var hold_timer: float = 0.0

var is_holding_button: bool = false
var is_charging: bool = false

var player:Node3D = null

func _ready() -> void:
	player = get_parent()

func interaction_allowed() -> bool:
	if get_tree().paused: return false
	return not is_instance_valid(player) or not player.has_method("is_incapacitated") or not player.is_incapacitated()

func cancel_interaction() -> void:
	_reset_throw_state()
	last_hovered_object = null
	object_focused.emit(null)

func _process(delta: float) -> void:
	if not interaction_allowed(): return
	_check_hovered_object()
	_update_throw_charge(delta)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(carried_object):
		return

	var weight: float = clamp(follow_speed * delta, 0.0, 1.0)
	if carried_object.has_method("update_carry"):
		carried_object.update_carry(carry_position.global_transform, weight)
		return

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
	if not interaction_allowed(): return
	if event.is_action_pressed("drop"):
		drop_object()
	
	elif event.is_action_pressed("Interact"):
		_handle_interact_pressed()

	elif event.is_action_released("Interact"):
		_handle_interact_released()


func _handle_interact_pressed() -> void:
	if not interaction_allowed(): return
	# Carry something and hover object have interact_with()
	if is_instance_valid(last_hovered_object) and last_hovered_object.has_method("interact_with"):
		var is_handled: bool = last_hovered_object.interact_with(carried_object, self)
		if is_handled:
			return
	
	# Dont Carry anything
	if carried_object == null:
		if is_instance_valid(last_hovered_object):
			# Pick something
			if last_hovered_object.is_in_group("Pickable"):
				pick_up(last_hovered_object)
			# Interact with something
			elif last_hovered_object.is_in_group("Interactable") and last_hovered_object.has_method("_interact"):
				last_hovered_object._interact()
		return
	
	# Carry Somthing and charge to throw
	is_holding_button = true
	hold_timer = 0.0
	current_throw_force = min_throw_force


func _handle_interact_released() -> void:
	if not interaction_allowed(): return
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
		if is_instance_valid(collider) and collider.has_meta("prisoner_owner"):
			collider = collider.get_meta("prisoner_owner")

		if collider and collider.is_in_group("Focusable"):
			current_target = collider

	if current_target == last_hovered_object:
		return

	last_hovered_object = current_target
	object_focused.emit(last_hovered_object)


func pick_up(object: Node3D) -> void:
	if not interaction_allowed(): return
	if not is_instance_valid(object) or object.is_queued_for_deletion() or is_instance_valid(carried_object): return
	if object.has_method("can_pick_up"):
		if not object.can_pick_up(): return
	elif not object is RigidBody3D: return
	var impact = object.get_node_or_null("ThrowImpact")
	if impact: impact.disarm()
	_reset_throw_state()
	if object is Cookware and object.is_on_stove:
		object.remove_from_stove()
	
	carried_object = object
	carried_object.tree_exiting.connect(_on_carried_exiting, CONNECT_ONE_SHOT)
	if object.has_method("begin_carry"):
		object.begin_carry()
	else:
		if object is Knife: object.pick_up_knife()
		object.freeze = true
		ray_cast.add_exception(object)
	
	if player and carried_object is RigidBody3D:
		carried_object.add_collision_exception_with(player)


func drop_object() -> void:
	_reset_throw_state()
	if not is_instance_valid(carried_object):
		carried_object = null
		return
	var impact = carried_object.get_node_or_null("ThrowImpact")
	if impact: impact.disarm()
	if carried_object.tree_exiting.is_connected(_on_carried_exiting): carried_object.tree_exiting.disconnect(_on_carried_exiting)

	if player and carried_object is RigidBody3D:
		carried_object.remove_collision_exception_with(player)

	if carried_object.has_method("end_carry"):
		carried_object.end_carry()
	else:
		carried_object.freeze = false
		ray_cast.remove_exception(carried_object)
	carried_object = null
	last_hovered_object = null
	object_focused.emit(null)


func throw_object(force: float) -> void:
	if not interaction_allowed(): return
	if carried_object == null:
		return

	var object := carried_object
	var throw_direction := -carry_position.global_transform.basis.z.normalized()
	var throw_vector := throw_direction * force

	drop_object()
	var bodies: Array[PhysicsBody3D] = []
	if object.has_method("get_throw_bodies"): bodies.assign(object.get_throw_bodies())
	elif object is RigidBody3D: bodies.append(object)
	ThrowImpact.ensure(object).arm(player, throw_damage_per_speed, bodies, throw_vector)
	
	if object.has_method("throw"):
		object.throw(throw_vector)
	else:
		object.apply_central_impulse(throw_vector)

func _on_carried_exiting() -> void:
	carried_object = null
	last_hovered_object = null
	_reset_throw_state()
	object_focused.emit(null)

func _reset_throw_state() -> void:
	is_holding_button = false
	is_charging = false
	hold_timer = 0.0
	current_throw_force = min_throw_force
	charge_updated.emit(0.0)
