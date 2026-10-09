extends Node
## Keeps the original prisoner alive in the scene until the player disposes of it.

var prisoner: CharacterBody3D
var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var bones: Array[PhysicsBody3D] = []
var held: bool = false
var active: bool = false
var carry_anchor: Transform3D
var outline: StandardMaterial3D

func setup(actor: CharacterBody3D) -> void:
	prisoner = actor
	skeleton = actor.visuals.skeleton
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "CorpsePhysics"
	skeleton.add_child(simulator)
	simulator.active = false
	# The source rig has hands/feet parented to root. Root is the torso body.
	_add_bone("root", Vector3(0, 0.62, 0), 0.32, 0.95, 3.0)
	_add_bone("head", Vector3(0, 0.23, 0.03), 0.22, 0.44, 0.7)
	_add_bone("hand.L", Vector3(0, -0.02, 0.06), 0.085, 0.17, 0.2)
	_add_bone("hand.R", Vector3(0, -0.02, 0.06), 0.085, 0.17, 0.2)
	_add_bone("foot.L", Vector3(0, -0.05, 0.04), 0.10, 0.20, 0.3)
	_add_bone("foot.R", Vector3(0, -0.05, 0.04), 0.10, 0.20, 0.3)
	for bone in bones:
		for other in bones:
			if other != bone: bone.add_collision_exception_with(other)
	outline = StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.025
	outline.albedo_color = Color("ffdb66")
	var player = get_tree().get_first_node_in_group("Player")
	if player != null: player.get_node("Head").object_focused.connect(_set_focus)

func _add_bone(bone_name: String, offset: Vector3, radius: float, height: float, mass: float) -> void:
	var bone := PhysicalBone3D.new()
	bone.name = "Ragdoll_" + bone_name.replace(".", "_")
	bone.mass = mass
	bone.linear_damp = 0.4
	bone.angular_damp = 1.5
	bone.collision_layer = 0
	bone.collision_mask = 0
	bone.body_offset = Transform3D(Basis.IDENTITY, offset)
	bone.joint_offset = bone.body_offset.affine_inverse()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.shape = shape
	bone.add_child(collider)
	simulator.add_child(bone)
	bone.set("bone_name", bone_name)
	if bone_name != "root": bone.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
	bone.set_meta("prisoner_owner", prisoner)
	bones.append(bone)

func start() -> void:
	if active: return
	active = true
	for bone in bones:
		bone.collision_layer = 2 # Raycast can select the whole corpse via any bone.
		bone.collision_mask = 1 # Floor/props, but does not obstruct the living queue.
		for player in get_tree().get_nodes_in_group("Player"): bone.add_collision_exception_with(player)
	simulator.active = true
	simulator.physical_bones_start_simulation()
	# A small off-centre impulse makes a stationary body topple instead of balancing.
	bones[0].apply_impulse(prisoner.visuals.global_basis.z * 1.5, Vector3(0, 0.3, 0))

func center() -> Vector3:
	if held: return (prisoner.global_transform * carry_anchor).origin
	return bones[0].global_position

func pick_up() -> void:
	if not active or held: return
	var local_poses: Array[Transform3D] = []
	var physical_poses: Dictionary = {}
	for i in skeleton.get_bone_count(): local_poses.append(skeleton.get_bone_pose(i))
	for bone in bones:
		physical_poses[bone.get_bone_id()] = skeleton.global_transform.affine_inverse() * bone.global_transform * bone.body_offset.affine_inverse()
	carry_anchor = prisoner.global_transform.affine_inverse() * Transform3D(prisoner.global_basis, center())
	simulator.physical_bones_stop_simulation()
	simulator.active = false
	# Preserve LOCAL poses of non-physical intermediary bones. Their global poses
	# outside the modifier callback can be the pre-simulation pose and stretch the neck.
	for i in local_poses.size(): skeleton.set_bone_pose(i, local_poses[i])
	for bone in bones: skeleton.set_bone_global_pose(bone.get_bone_id(), physical_poses[bone.get_bone_id()])
	for bone in bones:
		bone.collision_layer = 0
		bone.collision_mask = 0
	held = true
	_set_focus(null)

func follow(target: Transform3D, weight: float) -> void:
	if held:
		prisoner.global_transform = prisoner.global_transform.interpolate_with(target * carry_anchor.affine_inverse(), weight)

func drop() -> void:
	if not held: return
	held = false
	for bone in bones:
		bone.collision_layer = 2
		bone.collision_mask = 1
	simulator.active = true
	simulator.physical_bones_start_simulation()
	for bone in bones:
		bone.linear_velocity = Vector3.ZERO
		bone.angular_velocity = Vector3.ZERO

func throw_body(impulse: Vector3) -> void:
	# Equal launch velocity keeps the joints together; damage is independent of mass.
	var total_mass: float = 0.0
	for bone in bones: total_mass += bone.mass
	for bone in bones: bone.apply_central_impulse(impulse * (bone.mass / total_mass))

func _set_focus(target: Node) -> void:
	for mesh in skeleton.get_children():
		if mesh is MeshInstance3D: mesh.material_overlay = outline if target == prisoner and active and not held else null
