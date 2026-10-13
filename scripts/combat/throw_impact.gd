extends Node
## One launch record shared by all colliders of an item (including ragdoll bones).

var armed: bool = false
var damage_per_speed: float = 2.0
var thrower: Node3D
var hit_targets: Dictionary = {}
var bodies: Array[PhysicsBody3D] = []
var original_masks: Dictionary = {}
var still_time: float = 0.0
var launch_generation: int = 0
var sampled_velocities: Dictionary = {}
var hit_speeds: Dictionary = {}
var trail: MeshInstance3D

static func ensure(item: Node) -> Node:
	var impact = item.get_node_or_null("ThrowImpact")
	if impact == null:
		impact = load("res://scripts/combat/throw_impact.gd").new()
		impact.name = "ThrowImpact"
		item.add_child(impact)
	return impact

func arm(source: Node3D, multiplier: float, collision_bodies: Array[PhysicsBody3D], launch_impulse: Vector3 = Vector3.ZERO) -> void:
	disarm()
	thrower = source
	damage_per_speed = maxf(0.0, multiplier)
	hit_targets.clear()
	hit_speeds.clear()
	bodies.assign(collision_bodies)
	still_time = 0.0
	armed = true
	var total_mass: float = 0.0
	for body in bodies: total_mass += body.mass
	for body in bodies:
		# Seed the first physics step before the impulse is applied. Later hits use
		# fresh velocity samples, so slowing down or bouncing changes damage.
		sampled_velocities[body.get_instance_id()] = body.linear_velocity + launch_impulse / maxf(total_mass, 0.001)
		original_masks[body.get_instance_id()] = body.collision_mask
		body.collision_mask |= 4 # Live prisoners.
		PhysicsServer3D.body_set_max_contacts_reported(body.get_rid(), 16)
		if body is RigidBody3D:
			body.contact_monitor = true
			body.max_contacts_reported = maxi(16, body.max_contacts_reported)
			body.continuous_cd = true
			var callback: Callable = _on_body_entered.bind(body)
			if not body.body_entered.is_connected(callback): body.body_entered.connect(callback)
	set_physics_process(true)
	if not bodies.is_empty():
		if not is_instance_valid(trail):
			trail = preload("res://scenes/effects/throw_trail.tscn").instantiate()
			get_parent().add_child(trail)
		trail.start(bodies[0])

func disarm() -> void:
	if is_instance_valid(trail): trail.stop()
	armed = false
	launch_generation += 1
	for body in bodies:
		if is_instance_valid(body) and original_masks.has(body.get_instance_id()):
			body.collision_mask = original_masks[body.get_instance_id()]
	original_masks.clear()
	sampled_velocities.clear()
	bodies.clear()
	set_physics_process(false)

func _on_body_entered(body: Node, projectile: PhysicsBody3D) -> void:
	# The collision solver may already have stopped/reversed the projectile.
	# Capture the previous step's velocity NOW, not after the deferred callback.
	var incoming: Vector3 = sampled_velocities.get(projectile.get_instance_id(), Vector3.ZERO)
	_report_contact.call_deferred(body, launch_generation, incoming.length())

func _report_contact(body: Node, generation: int, impact_speed: float) -> void:
	if not armed or generation != launch_generation or not is_instance_valid(body): return
	if not is_finite(impact_speed) or impact_speed <= 0.0 or damage_per_speed <= 0.0: return
	var target: Node = body
	if body.has_meta("prisoner_owner"): target = body.get_meta("prisoner_owner")
	if not is_instance_valid(target) or target == get_parent() or target == thrower: return
	if target.is_queued_for_deletion() or not target.has_method("take_damage"): return
	if target.has_method("is_incapacitated") and target.is_incapacitated(): return
	var id: int = target.get_instance_id()
	if hit_targets.has(id): return
	hit_targets[id] = true
	hit_speeds[id] = impact_speed
	target.take_damage(impact_speed * damage_per_speed, thrower)
	var item := get_parent()
	var food: FoodItem = item as FoodItem
	if item is Cookware or item is Tray: food = item.current_food
	if is_instance_valid(food) and food.is_burning() and target.has_method("ignite"):
		target.ignite(thrower)

func _physics_process(delta: float) -> void:
	if not armed: return
	var moving: bool = false
	for body in bodies:
		if not is_instance_valid(body): continue
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if state == null: continue
		if state.linear_velocity.length_squared() > 0.04 or state.angular_velocity.length_squared() > 0.04: moving = true
		for contact in state.get_contact_count():
			var incoming: Vector3 = sampled_velocities.get(body.get_instance_id(), state.linear_velocity)
			_report_contact.call_deferred(state.get_contact_collider_object(contact), launch_generation, incoming.length())
		sampled_velocities[body.get_instance_id()] = state.linear_velocity
	still_time = 0.0 if moving else still_time + delta
	if still_time >= 0.75: disarm()
