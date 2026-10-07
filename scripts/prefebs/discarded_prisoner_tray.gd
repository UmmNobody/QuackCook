extends RigidBody3D
## A thrown tray is scene-owned debris, never another queue actor or pickup item.

var remaining_lifetime: float = 8.0

func _ready() -> void:
	add_to_group("DiscardedPrisonerTrays")

func _physics_process(delta: float) -> void:
	remaining_lifetime -= delta
	if remaining_lifetime <= 0: queue_free()
