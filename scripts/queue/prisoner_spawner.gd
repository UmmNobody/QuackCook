extends Node
## Finite waves. The game loop supplies the count; this node does not advance days.

signal wave_started(total: int)
signal wave_spawn_finished(total: int)
signal wave_completed(total: int)
signal prisoner_spawned(prisoner: Node3D)

@export var prisoner_scene: PackedScene = preload("res://scenes/characters/prisoner/prisoner.tscn")
@export_range(1, 50) var max_active_prisoners: int = 12
@export_range(0.1, 30.0) var spawn_interval: float = 2.0
@export_range(1.0, 300.0) var patience_seconds: float = 45.0
@export_range(1, 4) var minimum_foods: int = 2
@export_range(1, 4) var maximum_foods: int = 4
@export var use_example_orders: bool = true
@export var spawning_paused: bool = false
@export var use_navigation: bool = false

var actor_parent: Node3D
var elapsed: float = 0
var wave_total: int = 0
var wave_spawned: int = 0
var wave_active: bool = false
var _wave_actors: Dictionary = {}
var _wave_generation: int = 0

## Returns false for invalid setup/count or while the previous wave is still active.
func start_wave(count: int) -> bool:
	if count <= 0 or wave_active or prisoner_scene == null: return false
	if not is_instance_valid(actor_parent) or not actor_parent.is_inside_tree(): return false
	if not is_instance_valid(QueueManager.layout_owner): return false
	_wave_generation += 1
	_wave_actors.clear()
	wave_total = count
	wave_spawned = 0
	wave_active = true
	elapsed = spawn_interval
	wave_started.emit(count)
	return true

func remaining_to_spawn() -> int:
	return wave_total - wave_spawned if wave_active else 0

func wave_alive_count() -> int:
	var count: int = 0
	for id in _wave_actors:
		var actor = instance_from_id(id)
		if is_instance_valid(actor) and not actor.is_incapacitated(): count += 1
	return count

func wave_pending_count() -> int:
	# Includes unconscious prisoners until they are disposed of.
	return _wave_actors.size()

## Cancel pending spawns/tracking, without deleting prisoners already in the scene.
## For a full restart call this BEFORE QueueManager.reset_queue().
func cancel_wave() -> void:
	_wave_generation += 1
	wave_active = false
	wave_total = 0
	wave_spawned = 0
	_wave_actors.clear()
	elapsed = 0

func _process(delta: float) -> void:
	if spawning_paused or remaining_to_spawn() == 0: return
	elapsed = minf(elapsed + delta, spawn_interval)
	if elapsed >= spawn_interval:
		spawn_one()

## Manual test step (also works while paused). Always consumes the active wave quota.
func spawn_one(order_override: Array[int] = []) -> Node3D:
	if remaining_to_spawn() <= 0 or prisoner_scene == null: return null
	if not is_instance_valid(actor_parent) or not QueueManager.can_spawn(): return null
	if QueueManager.active_count() >= max_active_prisoners: return null
	var order: Array[int] = []
	order.assign(order_override)
	if order.is_empty():
		if use_example_orders and QueueManager.next_ticket == 1:
			order.assign([FoodItem.Type.CHICKEN, FoodItem.Type.MIXED_VEG, FoodItem.Type.WATER])
		elif use_example_orders and QueueManager.next_ticket == 2:
			order.assign([FoodItem.Type.MIXED_VEG, FoodItem.Type.RICE, FoodItem.Type.WATER])
		else:
			var choices: Array[int] = [FoodItem.Type.CHICKEN, FoodItem.Type.MIXED_VEG, FoodItem.Type.RICE, FoodItem.Type.WATER]
			choices.shuffle()
			var minimum: int = clampi(minimum_foods, 1, 4)
			var maximum: int = clampi(maximum_foods, minimum, 4)
			order.assign(choices.slice(0, randi_range(minimum, maximum)))
	var actor = prisoner_scene.instantiate()
	actor.use_navigation = use_navigation
	actor.configure(order, patience_seconds)
	actor_parent.add_child(actor)
	if not QueueManager.admit(actor):
		actor.queue_free()
		return null
	var id: int = actor.get_instance_id()
	_wave_actors[id] = true
	actor.tree_exited.connect(_on_wave_actor_exited.bind(id, _wave_generation), CONNECT_ONE_SHOT)
	wave_spawned += 1
	elapsed = 0
	prisoner_spawned.emit(actor)
	if wave_spawned == wave_total:
		wave_spawn_finished.emit(wave_total)
	return actor

func _on_wave_actor_exited(id: int, generation: int) -> void:
	if generation != _wave_generation or not wave_active: return
	_wave_actors.erase(id)
	if remaining_to_spawn() == 0 and _wave_actors.is_empty():
		wave_active = false
		wave_completed.emit(wave_total)
