extends Button
@export var hover_scale: float = 1.2
@export var hover_shift: float = 18.0
@export var animation_duration: float = 0.16
@onready var visual: Label = $Visual
var _tween: Tween
func _ready() -> void:
	mouse_entered.connect(_animate)
	mouse_exited.connect(_animate)
	focus_entered.connect(_animate)
	focus_exited.connect(_animate)
	resized.connect(_update_pivot)
	_update_pivot()
	_animate()
func _update_pivot() -> void:
	visual.pivot_offset = Vector2(0, size.y * 0.5)
func _animate() -> void:
	var highlighted := not disabled and (is_hovered() or has_focus())
	if _tween: _tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(visual, "scale", Vector2.ONE * (hover_scale if highlighted else 1.0), animation_duration)
	_tween.tween_property(visual, "position:x", hover_shift if highlighted else 0.0, animation_duration)
	visual.modulate = Color(1,1,1,0.3 if disabled else 1.0)
