extends Node3D
## Owned by the player, but top-level so following the torso does not move
## the simulated body twice. Geometry and joints live in player_ragdoll.tscn.

@onready var torso: RigidBody3D = $Torso
@onready var view: Marker3D = $Head/View
var bodies: Array[RigidBody3D] = []

func start(player: PhysicsBody3D, carried: Node3D, launch: Vector3, tumble: Vector3) -> void:
	for child in get_children():
		if child is RigidBody3D: bodies.append(child)
	for body in bodies:
		body.add_collision_exception_with(player)
		if carried is PhysicsBody3D: body.add_collision_exception_with(carried)
		if is_instance_valid(carried) and carried.has_method("get_throw_bodies"):
			for part in carried.get_throw_bodies(): body.add_collision_exception_with(part)
		for other in bodies:
			if other != body: body.add_collision_exception_with(other)
		body.freeze = false
		body.sleeping = false
		body.linear_velocity = launch
		body.angular_velocity = tumble

func center() -> Vector3:
	return torso.global_position

func view_transform() -> Transform3D:
	return view.global_transform.orthonormalized()

func body_rids() -> Array[RID]:
	var result: Array[RID] = []
	for body in bodies: result.append(body.get_rid())
	return result

func stop() -> void:
	for body in bodies:
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
