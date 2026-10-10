extends Node3D
## PlayerBarrier stays fixed; only the visible leaf and aiming collider move.
@export_range(0.0, 3.0) var close_delay: float = 0.35
@export_range(0.2, 2.0) var passage_half_depth: float = 0.85
@onready var motion = $Motion
@onready var sensor: Area3D = $ApproachArea
@onready var leaf: AnimatableBody3D = $LeafRayCollision
@onready var door_mesh: MeshInstance3D = $Model/Door/door_B_ROOT_001/Door_Hinge_CTRL_001/door_B_001
var _clear_time := 0.0

func _ready() -> void:
	leaf.global_transform = door_mesh.global_transform

func _physics_process(delta: float) -> void:
	var needed := false
	for body in sensor.get_overlapping_bodies():
		if not body is CharacterBody3D or not body.has_method("is_incapacitated"): continue
		if body.is_incapacitated(): continue
		var local_position := to_local(body.global_position)
		var local_velocity: Vector3 = global_basis.inverse() * body.velocity
		# Ignore queue traffic parallel to the wall, but stay open while occupied.
		if absf(local_position.z) < passage_half_depth or local_position.z * local_velocity.z < -0.1:
			needed = true
			break
	if needed:
		_clear_time = 0.0
		motion.set_open(true)
	else:
		_clear_time += delta
		if _clear_time >= close_delay: motion.set_open(false)
	motion.advance(delta)
	leaf.global_transform = door_mesh.global_transform
