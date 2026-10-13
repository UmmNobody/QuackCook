extends Node
## Repeated hits refresh duration, never stack damage or postpone the next tick.
const FireScene = preload("res://scenes/effects/particles/burning_fire.tscn")
const DURATION := 3.0
const DAMAGE := 10.0
var remaining := 0.0
var _tick_elapsed := 0.0
var _source: Node3D
var fire: CPUParticles3D

func _ready() -> void:
	fire = FireScene.instantiate()
	fire.name = "BurningFire"
	fire.position = Vector3(0, 1, 0)
	fire.emission_box_extents = Vector3(0.3, 0.65, 0.25)
	fire.amount = 48
	set_physics_process(false)

func ignite(source: Node3D = null) -> void:
	if get_parent().is_incapacitated(): return
	if fire.get_parent() == null: get_parent().add_child(fire)
	if remaining <= 0.0: _tick_elapsed = 0.0
	remaining = DURATION
	_source = source
	fire.set_active(true)
	set_physics_process(true)

func extinguish() -> void:
	remaining = 0.0
	_tick_elapsed = 0.0
	_source = null
	if is_instance_valid(fire): fire.set_active(false)
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	var actor := get_parent()
	if actor.is_incapacitated() or actor.is_queued_for_deletion():
		extinguish()
		return
	var elapsed := minf(maxf(delta, 0.0), remaining)
	remaining = maxf(0.0, remaining - elapsed)
	_tick_elapsed += elapsed
	while _tick_elapsed >= 1.0 - 0.00001:
		_tick_elapsed = maxf(0.0, _tick_elapsed - 1.0)
		actor.take_damage(DAMAGE, _source if is_instance_valid(_source) else null)
		if actor.is_incapacitated(): return
	if remaining <= 0.00001: extinguish()
