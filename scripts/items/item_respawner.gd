extends Node3D
## Recover loose pickable items without replacing them or resetting their food state.
@export var fall_height: float = -10.0
@export_range(0.05, 2.0) var check_interval: float = 0.2
@onready var respawn_point: Marker3D = $RespawnPoint
var _elapsed := 0.0

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < check_interval: return
	_elapsed = 0.0
	for item in get_tree().get_nodes_in_group("Pickable"):
		if not item is RigidBody3D or item.is_queued_for_deletion(): continue
		if item.global_position.y >= fall_height: continue
		if recover_item(item): break # Stagger simultaneous recoveries.

func recover_item(item: RigidBody3D) -> bool:
	if not is_instance_valid(item) or item.is_queued_for_deletion(): return false
	for player in get_tree().get_nodes_in_group("Player"):
		if player.get_node("Head").carried_object == item: return false
	# Food on a tray/pan/pot travels back with that container, not separately.
	var ancestor := item.get_parent()
	while ancestor != null:
		if ancestor is PhysicsBody3D: return false
		ancestor = ancestor.get_parent()
	if item is Cookware and item.is_on_stove: return false
	if item.freeze and not (item is Knife and item.is_stuck): return false
	var collision := item.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.disabled: return false
	var pose := Transform3D(respawn_point.global_basis.orthonormalized().scaled(item.global_basis.get_scale()), respawn_point.global_position)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.collision_mask = 15
	query.exclude = [item.get_rid()]
	query.margin = 0.05
	var found := false
	for step in 16:
		query.transform = pose * collision.transform
		if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			found = true
			break
		pose.origin.y += 0.35
	if not found: return false # Retry later rather than spawning inside another object.
	var impact := item.get_node_or_null("ThrowImpact")
	if impact != null: impact.disarm()
	if item is Knife: item.pick_up_knife()
	item.global_transform = pose
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.sleeping = false
	item.reset_physics_interpolation()
	return true
