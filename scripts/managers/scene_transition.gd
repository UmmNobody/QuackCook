extends CanvasLayer
## Persistent overlay: also runs while a daily report or pause menu owns the pause.
@export_range(0.0, 2.0) var duration: float = 0.55
@onready var curtain: ColorRect = $Curtain
var busy := false

func _ready() -> void:
	curtain.hide()
	curtain.resized.connect(_resize)
	_resize()

func _resize() -> void:
	curtain.material.set_shader_parameter("node_resolution", curtain.size)

func _input(_event: InputEvent) -> void:
	if busy: get_viewport().set_input_as_handled()

func cover() -> bool:
	if busy: return false
	busy = true
	curtain.show()
	await _animate(0.0, 1.0)
	return true

func reveal() -> void:
	# Allow change_scene_to_file and the new scene's layout to finish under black.
	await get_tree().process_frame
	await get_tree().process_frame
	await _animate(1.0, 0.0)
	curtain.hide()
	busy = false

func _animate(from: float, to: float) -> void:
	curtain.material.set_shader_parameter("factor", from)
	if duration <= 0.0:
		curtain.material.set_shader_parameter("factor", to)
		return
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(func(value: float): curtain.material.set_shader_parameter("factor", value), from, to, duration)
	await tween.finished
