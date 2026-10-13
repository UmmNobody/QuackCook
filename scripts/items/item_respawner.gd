extends Node3D
## Recover loose pickable items without replacing them or resetting their food state.
@export var fall_height: float = -10.0
@export_range(0.05, 2.0) var check_interval: float = 0.2
@export_range(0.0, 30.0, 0.1) var respawn_delay: float = 5.0
@onready var respawn_point: Marker3D = $RespawnPoint
@onready var recovery_area: Area3D = get_node_or_null("RecoveryArea")
var _elapsed := 0.0
var _pending: Dictionary = {}

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < check_interval: return
	var elapsed := _elapsed
	_elapsed = 0.0
	var pending: Dictionary = {}
	var recovered := false
	var outside_items: Array[Node3D] = recovery_area.get_overlapping_bodies() if recovery_area != null else []
	for item in get_tree().get_nodes_in_group("Pickable"):
		if not item is RigidBody3D or item.is_queued_for_deletion(): continue
		if item.global_position.y >= fall_height and not outside_items.has(item): continue
		if not _can_recover(item): continue
		var id: int = item.get_instance_id()
		# First observation starts at zero so no item returns before the full delay.
		var waiting: float = float(_pending[id]) + elapsed if _pending.has(id) else 0.0
		if waiting >= respawn_delay and not recovered and recover_item(item):
			recovered = true # Stagger simultaneous recoveries to avoid stacking overlaps.
		else:
			pending[id] = waiting
	# Leaving the area, picking up, deleting or attaching an item cancels its timer.
	_pending = pending

func _can_recover(item: RigidBody3D) -> bool:
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
	return collision != null and not collision.disabled and collision.shape != null

func recover_item(item: RigidBody3D) -> bool:
	if not _can_recover(item): return false
	var collision := item.get_node("CollisionShape3D") as CollisionShape3D
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
	_pending.erase(item.get_instance_id())
	return true
