extends Node3D
## PlayerBarrier stays fixed; only the visible leaf and aiming collider move.
@export_range(0.0, 3.0) var close_delay: float = 0.35
@export_range(0.2, 2.0) var passage_half_depth: float = 0.85
@onready var motion = $Motion
@onready var sensor: Area3D = $ApproachArea
@onready var leaf: AnimatableBody3D = $LeafRayCollision
@onready var door_mesh: MeshInstance3D = $Model/Door/door_B_ROOT_001/Door_Hinge_CTRL_001/door_B_001
var _clear_time := 0.0
# Only retain weak references while a first crossing is in progress.
var _crossings: Dictionary = {}

func _ready() -> void:
	leaf.global_transform = door_mesh.global_transform

func _physics_process(delta: float) -> void:
	var needed := false
	var overlapping := sensor.get_overlapping_bodies()
	for id in _crossings.keys():
		var crossing: Dictionary = _crossings[id]
		var body = crossing.body.get_ref()
		if not is_instance_valid(body) or body.is_incapacitated():
			_crossings.erase(id)
			continue
		var local_position := to_local(body.global_position)
		if local_position.z * crossing.entry_side < -passage_half_depth:
			body.kitchen_door_passed = true
			_crossings.erase(id)
		elif body not in overlapping:
			# Withdrawing on the entry side does not consume a passage.
			_crossings.erase(id)
		else:
			needed = true
	for body in overlapping:
		if not body.has_method("can_open_kitchen_door") or not body.can_open_kitchen_door(): continue
		if _crossings.has(body.get_instance_id()): continue
		var local_position := to_local(body.global_position)
		var local_velocity: Vector3 = global_basis.inverse() * body.velocity
		# Only the first escape route into the kitchen may initiate opening.
		if absf(local_position.z) < passage_half_depth or local_position.z * local_velocity.z < -0.1:
			var entry_side := signf(local_position.z)
			if entry_side == 0.0: entry_side = -signf(local_velocity.z)
			if entry_side == 0.0: entry_side = -1.0
			_crossings[body.get_instance_id()] = {"body": weakref(body), "entry_side": entry_side}
			needed = true
	if needed:
		_clear_time = 0.0
		motion.set_open(true)
	else:
		_clear_time += delta
		if _clear_time >= close_delay: motion.set_open(false)
	motion.advance(delta)
	leaf.global_transform = door_mesh.global_transform
