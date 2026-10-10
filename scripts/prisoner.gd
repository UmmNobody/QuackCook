extends CharacterBody3D
signal service_completed
signal anger_started
## Queue movement is assigned by QueueManager; Visuals drives the imported model.

enum State { 
	WAITING_ENTRY, 
	MOVING_IN_QUEUE, 
	WAITING_FOOD, 
	BLOCKED, 
	LEAVING, 
	ANGRY_EXIT, 
	CHASING_PLAYER, 
	ATTACKING, 
	PICKING_UP_TRAY, 
	WAITING_WITH_TRAY, 
	THROWING_TRAY, 
	ENTERING_COMBAT,
	INCAPACITATED
}

const MENU: Array[int] = [FoodItem.Type.CHICKEN, FoodItem.Type.MIXED_VEG, FoodItem.Type.RICE, FoodItem.Type.WATER]
const ATTACK_CLIPS: Array[StringName] = [&"P1_Punch_Combo", &"P1_Kick_Front_R", &"P1_Boxing_Flurry"]
const ATTACK_HITS: Array = [[0.24, 0.60], [0.40], [0.18, 0.36, 0.54, 0.72]]

# Map ชื่อย่อตามประเภทอาหารเพื่อลด Magic Array
const FOOD_SHORT_NAMES: Dictionary = {
	FoodItem.Type.CHICKEN: "C",
	FoodItem.Type.MIXED_VEG: "V",
	FoodItem.Type.RICE: "R",
	FoodItem.Type.WATER: "W"
}

@export_group("Movement & Patience")
@export var use_navigation: bool = false
var navigation_agent: NavigationAgent3D
var navigation_update_remaining: float = 0.0
var service_reported: bool = false
@export_range(0.1, 10.0) var walk_speed: float = 1.8
@export_range(0.1, 10.0) var chase_speed: float = 2.8
@export_range(1.0, 300.0) var patience_duration: float = 45.0

@export_group("Combat Settings")
@export_range(0.0, 1000.0) var attack_damage: float = 10.0
@export_range(0.3, 3.0) var attack_range: float = 1.2
@export_range(0.1, 5.0) var attack_interval: float = 1.0

@export_group("Serving Tray")
@export var serving_tray_scene: PackedScene = preload("res://scenes/serving_tray.tscn")
@export_range(0.1, 5.0) var tray_pickup_duration: float = 1.96
@export_range(0.1, 10.0) var tray_throw_forward_speed: float = 3.5
@export_range(0.1, 10.0) var tray_throw_up_speed: float = 3.0
@export_range(1.0, 300.0) var discarded_tray_lifetime: float = 8.0

@export_group("Health")
@export_range(1.0, 1000.0) var max_health: float = 100.0
var health: float = 100.0
var ragdoll: Node
signal health_changed(current: float, maximum: float)
signal incapacitated

# Node References
@onready var info: Label3D = $Info
@onready var patience_fill: MeshInstance3D = $Patience/Fill
@onready var visuals: Node3D = $Visuals
@onready var tray_hold_point: Marker3D = $TrayHoldPoint

# Internal State Variables
var state: State = State.WAITING_ENTRY
var ticket: int = 0
var wanted: Array[int] = []
var received: Array[int] = []
var patience: float = 45.0

var slot_index: int = -1
var target_index: int = -1
var destination: Vector3
var escape_points: Array[Vector3] = []

var serving_tray: Node3D
var thrown_tray: RigidBody3D
var fight_target: Node3D
var anger_reason: String = ""

# Timers & Counters
var tray_pickup_elapsed: float = 0.0
var combat_transition_elapsed: float = 0.0
var attack_elapsed: float = 0.0
var attack_timer: float = 0.0
var attack_sequence: int = -1
var next_attack_hit: int = 0
var attacks_made: int = 0
var attack_in_progress: bool = false


func _ready() -> void:
	if use_navigation:
		navigation_agent = NavigationAgent3D.new()
		navigation_agent.path_desired_distance = 0.2
		navigation_agent.target_desired_distance = 0.6
		add_child(navigation_agent)
	health = max_health
	patience = patience_duration
	visuals.sync_tray(tray_hold_point)
	_update_display()

func is_incapacitated() -> bool:
	return state == State.INCAPACITATED

func take_damage(amount: float, source: Node3D = null) -> void:
	if amount <= 0 or is_incapacitated() or is_queued_for_deletion(): return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	visuals.play_hit_feedback(health > 0.0)
	if health <= 0:
		_incapacitate()
	elif anger_reason.is_empty():
		if is_instance_valid(QueueManager.layout_owner): QueueManager.make_angry(self, "Hit by a thrown object")
		else:
			var route: Array[Vector3] = []
			begin_anger(route, source, "Hit by a thrown object")
	_update_display()

func _incapacitate() -> void:
	state = State.INCAPACITATED
	attack_in_progress = false
	attack_timer = 0.0
	velocity = Vector3.ZERO
	fight_target = null
	escape_points.clear()
	QueueManager.release_incapacitated(self)
	visuals.animation_player.pause()
	collision_layer = 0
	collision_mask = 0
	$CollisionShape3D.set_deferred("disabled", true)
	$Patience.hide()
	add_to_group("Pickable")
	add_to_group("Focusable")
	# Build physics after any contact callbacks have finished.
	_start_ragdoll.call_deferred()
	incapacitated.emit()

func _start_ragdoll() -> void:
	if is_queued_for_deletion(): return
	if has_serving_tray():
		thrown_tray = serving_tray.throw_into_scene(get_parent(), Vector3.ZERO, discarded_tray_lifetime)
		serving_tray = null
	ragdoll = preload("res://scripts/prisoner_ragdoll.gd").new()
	ragdoll.name = "Ragdoll"
	add_child(ragdoll)
	ragdoll.setup(self)
	ragdoll.start()

func can_pick_up() -> bool:
	return is_incapacitated() and is_instance_valid(ragdoll) and ragdoll.active and not ragdoll.held

func begin_carry() -> void:
	ragdoll.pick_up()

func update_carry(target: Transform3D, weight: float) -> void:
	ragdoll.follow(target, weight)

func end_carry() -> void:
	ragdoll.drop()

func throw(impulse: Vector3) -> void:
	if is_incapacitated(): ragdoll.throw_body(impulse)

func get_throw_bodies() -> Array[PhysicsBody3D]:
	return ragdoll.bones

func can_dispose() -> bool:
	return is_incapacitated()


func configure(order: Array[int], seconds: float) -> void:
	wanted.clear()
	for food in order:
		if food in MENU and food not in wanted:
			wanted.append(food)
	received.clear()
	patience_duration = maxf(1.0, seconds)
	patience = patience_duration


func food_name(food: int) -> String:
	match food:
		FoodItem.Type.CHICKEN: return "Chicken"
		FoodItem.Type.MIXED_VEG: return "Veg"
		FoodItem.Type.RICE: return "Rice"
		FoodItem.Type.WATER: return "Water"
		_: return "?"


func order_text() -> String:
	var names: PackedStringArray = []
	for food in MENU:
		if needs_food(food):
			names.append(food_name(food))
	return ", ".join(names) if not names.is_empty() else "Complete"


func needs_food(food: int) -> bool:
	return food in wanted and food not in received


func complete() -> bool:
	return received.size() == wanted.size()


func receive_food(food: int) -> void:
	if is_incapacitated(): return
	if not has_serving_tray() or not serving_tray.show_food(food):
		return
	if needs_food(food):
		received.append(food)
	_update_display()


func has_serving_tray() -> bool:
	return is_instance_valid(serving_tray) and not serving_tray.is_queued_for_deletion()


func give_serving_tray() -> bool:
	if is_incapacitated(): return false
	if has_serving_tray():
		return true
	if serving_tray_scene == null:
		return false
		
	serving_tray = serving_tray_scene.instantiate()
	tray_hold_point.add_child(serving_tray)
	serving_tray.transform = Transform3D.IDENTITY
	visuals.sync_tray(tray_hold_point)
	return true


func wait_at_tray_pickup() -> void:
	if is_incapacitated(): return
	if state == State.PICKING_UP_TRAY:
		return
		
	if has_serving_tray():
		state = State.WAITING_WITH_TRAY
	else:
		tray_pickup_elapsed = 0.0
		state = State.PICKING_UP_TRAY
	_update_display()


func tray_pickup_complete() -> bool:
	return has_serving_tray() and state != State.PICKING_UP_TRAY


func face_towards(point: Vector3) -> void:
	visuals.face_direction(point - global_position)


func is_moving() -> bool:
	return state == State.MOVING_IN_QUEUE


func is_departing() -> bool:
	return state in [
		State.LEAVING, 
		State.ANGRY_EXIT, 
		State.CHASING_PLAYER, 
		State.ATTACKING, 
		State.THROWING_TRAY, 
		State.ENTERING_COMBAT,
		State.INCAPACITATED
	]


func set_waiting(in_service: bool, wants_here: bool) -> void:
	if is_incapacitated(): return
	state = State.WAITING_ENTRY if not in_service else (State.WAITING_FOOD if wants_here else State.BLOCKED)
	_update_display()


func move_to_slot(index: int, point: Vector3) -> void:
	if is_incapacitated(): return
	target_index = index
	destination = point
	state = State.MOVING_IN_QUEUE
	_update_display()


func begin_exit(point: Vector3) -> void:
	if is_incapacitated(): return
	destination = point
	state = State.LEAVING
	if complete() and anger_reason.is_empty() and not service_reported:
		service_reported = true
		service_completed.emit()
	_update_display()


func begin_anger(points: Array[Vector3], target: Node3D, reason: String) -> void:
	if is_incapacitated() or not anger_reason.is_empty():
		return
		
	escape_points.assign(points)
	fight_target = target
	anger_reason = reason
	anger_started.emit()
	target_index = -1
	combat_transition_elapsed = 0.0
	state = State.THROWING_TRAY if has_serving_tray() else State.ENTERING_COMBAT
	
	if state == State.ENTERING_COMBAT:
		visuals.set_combat_hands(true)
		
	_update_display()


func _throw_serving_tray() -> void:
	if not has_serving_tray():
		return
		
	var throw_velocity: Vector3 = visuals.global_basis.z.normalized() * tray_throw_forward_speed + Vector3.UP * tray_throw_up_speed
	thrown_tray = serving_tray.throw_into_scene(get_parent(), throw_velocity, discarded_tray_lifetime)
	serving_tray = null
	visuals.set_combat_hands(true)


func _physics_process(delta: float) -> void:
	if is_incapacitated():
		if is_instance_valid(ragdoll): info.global_position = ragdoll.center() + Vector3.UP * 0.8
		return
	visuals.advance(delta, tray_hold_point)
	
	velocity.x = 0.0
	velocity.z = 0.0
	
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	else:
		velocity.y = 0.0

	# Process patience
	if state in [State.WAITING_FOOD, State.BLOCKED] and not complete():
		patience = maxf(0.0, patience - delta)
		if patience <= 0.0:
			QueueManager.make_angry(self, "Patience exhausted")

	# State Machine Logic
	match state:
		State.PICKING_UP_TRAY:
			tray_pickup_elapsed += delta
			if tray_pickup_elapsed >= tray_pickup_duration * 0.55 and not has_serving_tray():
				give_serving_tray()
			if tray_pickup_elapsed >= tray_pickup_duration and has_serving_tray():
				state = State.WAITING_WITH_TRAY

		State.MOVING_IN_QUEUE, State.LEAVING:
			if _walk_to(destination, walk_speed, delta):
				if state == State.LEAVING:
					queue_free()
				else:
					QueueManager.arrived(self, target_index)

		State.THROWING_TRAY:
			combat_transition_elapsed += delta
			var duration: float = visuals.clip_duration(&"P1_Tray_Throw")
			if combat_transition_elapsed >= duration * 0.48:
				_throw_serving_tray()
			if combat_transition_elapsed >= duration:
				combat_transition_elapsed = 0.0
				state = State.ENTERING_COMBAT

		State.ENTERING_COMBAT:
			combat_transition_elapsed += delta
			if combat_transition_elapsed >= visuals.clip_duration(&"P1_Combat_Enter"):
				state = State.ANGRY_EXIT

		State.ANGRY_EXIT:
			if escape_points.is_empty():
				state = State.CHASING_PLAYER
			elif _walk_to(escape_points[0], chase_speed, delta):
				escape_points.pop_front()

		State.CHASING_PLAYER, State.ATTACKING:
			attack_timer = maxf(0.0, attack_timer - delta)
			if is_instance_valid(fight_target):
				var gap: Vector3 = fight_target.global_position - global_position
				gap.y = 0.0
				if gap.length() > attack_range:
					attack_in_progress = false
					state = State.CHASING_PLAYER
					_chase_target(delta)
				else:
					state = State.ATTACKING
					face_towards(fight_target.global_position)
					if not attack_in_progress and attack_timer <= 0.0:
						_start_attack()
					if attack_in_progress:
						_advance_attack(delta)
			else:
				attack_in_progress = false

	move_and_slide()
	visuals.sync_tray(tray_hold_point)
	_update_display()


func _start_attack() -> void:
	attack_sequence = (attack_sequence + 1) % ATTACK_CLIPS.size()
	attack_elapsed = 0.0
	next_attack_hit = 0
	attack_in_progress = true
	attack_timer = maxf(attack_interval, visuals.clip_duration(ATTACK_CLIPS[attack_sequence]))
	visuals.play(ATTACK_CLIPS[attack_sequence], 1.0, true)


func _advance_attack(delta: float) -> void:
	if is_incapacitated(): return
	attack_elapsed += delta
	var duration: float = visuals.clip_duration(ATTACK_CLIPS[attack_sequence])
	var hits: Array = ATTACK_HITS[attack_sequence]
	
	while next_attack_hit < hits.size() and attack_elapsed >= duration * hits[next_attack_hit]:
		if is_incapacitated() or not is_instance_valid(fight_target): return
		next_attack_hit += 1
		attacks_made += 1
		if fight_target.has_method("take_damage"):
			fight_target.take_damage(attack_damage, self)
		QueueManager.attack_contact.emit(self, fight_target)
		
	if attack_elapsed >= duration:
		attack_in_progress = false


func _chase_target(delta: float) -> void:
	if not use_navigation or navigation_agent == null:
		_walk_to(fight_target.global_position, chase_speed, delta)
		return
	if NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) == 0: return
	navigation_update_remaining -= delta
	if navigation_update_remaining <= 0.0:
		navigation_agent.target_position = fight_target.global_position
		navigation_update_remaining = 0.25
	if not navigation_agent.is_navigation_finished():
		_walk_to(navigation_agent.get_next_path_position(), chase_speed, delta)

func _walk_to(point: Vector3, speed: float, delta: float) -> bool:
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= 0.025:
		return true
		
	var direction: Vector3 = offset / distance
	visuals.face_direction(direction)
	var step_speed: float = minf(speed, distance / maxf(delta, 0.0001))
	velocity.x = direction.x * step_speed
	velocity.z = direction.z * step_speed
	return false


func _update_display() -> void:
	if not is_node_ready():
		return
	if is_incapacitated():
		info.text = "#%d UNCONSCIOUS\nPick up / Trash" % ticket
		info.modulate = Color("a9b3c6")
		$Patience.hide()
		return
		
	const STATE_NAMES: Array[String] = [
		"ENTRY", "WALK", "WAIT FOOD", "BLOCKED", "EXIT", 
		"ANGRY", "CHASE", "ATTACK", "TAKE TRAY", "TRAY READY", 
		"THROW TRAY", "COMBAT READY"
	]
	
	var state_name: String = STATE_NAMES[state]
	var remaining: PackedStringArray = []
	
	for food in MENU:
		if needs_food(food):
			remaining.append(FOOD_SHORT_NAMES.get(food, "?"))
			
	if not anger_reason.is_empty():
		info.text = "#%d  ANGRY\n%s" % [ticket, anger_reason]
		info.modulate = Color("ec5c55")
	else:
		info.text = "#%d  %s\n%s" % [ticket, state_name, "Need: " + " ".join(remaining) if not remaining.is_empty() else "Complete"]
		info.modulate = Color("65ce95") if complete() else Color.WHITE

	# Update Patience Bar
	var ratio: float = clampf(patience / patience_duration, 0.0, 1.0)
	patience_fill.scale.x = maxf(0.001, ratio)
	patience_fill.position.x = -0.42 * (1.0 - ratio)
	$Patience.visible = not complete() and not is_departing()
	info.text += "\nHP %d/%d" % [ceili(health), ceili(max_health)]
	
	_update_animation()


func _update_animation() -> void:
	match state:
		State.PICKING_UP_TRAY:
			visuals.play(&"P1_Tray_Pickup", visuals.clip_duration(&"P1_Tray_Pickup") / tray_pickup_duration)
		State.THROWING_TRAY:
			visuals.play(&"P1_Tray_Throw")
		State.ENTERING_COMBAT:
			visuals.play(&"P1_Combat_Enter")
		State.ANGRY_EXIT, State.CHASING_PLAYER:
			visuals.play(&"P1_Combat_Walk" if velocity.length_squared() > 0.01 else &"P1_Combat_Idle")
		State.ATTACKING:
			if not attack_in_progress:
				visuals.play(&"P1_Combat_Idle")
		State.MOVING_IN_QUEUE, State.LEAVING:
			visuals.play(&"P1_Tray_Walk" if has_serving_tray() else &"P1_Walk_Waddle_Blockout")
		_:
			visuals.play(&"P1_Tray_Idle" if has_serving_tray() else &"P1_Idle")
