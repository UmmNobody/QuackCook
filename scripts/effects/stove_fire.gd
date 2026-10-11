extends CPUParticles3D
## Low-poly burner flames. The stove controls this while food is cooking.

var active: bool = false

func set_active(value: bool) -> void:
	if active == value: return
	active = value
	visible = value
	if value: restart()
	emitting = value
