extends Node
## The imported clip contains closed -> open -> closed. Hold the open pose
## during service; only this presentation controller runs behind the report.
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
@export var animation_name: StringName = &"Shutter_Open_Close"
## Time at which the combined animation is fully open.
@export_range(0.01, 30.0, 0.01) var opened_time: float = 2.5
@export_range(0.1, 5.0, 0.1) var playback_speed: float = 1.0

var target_open := false
var moving := false
var animation_time := 0.0
var _end_time := 0.0
var _clip: Animation
@onready var animation_player: AnimationPlayer = get_node_or_null(animation_player_path)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if animation_player == null or not animation_player.has_animation(animation_name):
		push_error("KitchenShutter: assign an AnimationPlayer containing " + str(animation_name))
		set_process(false)
		return
	_clip = animation_player.get_animation(animation_name)
	if opened_time <= 0.0 or opened_time >= _clip.length:
		push_error("KitchenShutter: opened_time must be inside the combined animation.")
		set_process(false)
		return
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_player.play(animation_name)
	animation_player.seek(0.0, true)
	animation_player.pause()
	GameManager.session_changed.connect(_sync_kitchen_state)
	_sync_kitchen_state()

func _sync_kitchen_state() -> void:
	var should_open := GameManager.state == GameManager.State.SERVING
	if should_open == target_open: return
	target_open = should_open
	var start := 0.0 if target_open else opened_time
	_end_time = opened_time if target_open else _clip.length
	# Next day can begin before closing finishes (including zero preparation).
	# Match the current pose when switching halves instead of jumping the panel.
	animation_time = _matching_time(start, _end_time) if moving else start
	moving = true
	animation_player.seek(animation_time, true)

func _process(delta: float) -> void:
	if not moving: return
	if get_tree().paused:
		if GameManager.state != GameManager.State.SUMMARY or GameManager.pause_menu_open: return
	animation_time = minf(animation_time + delta * playback_speed, _end_time)
	animation_player.seek(animation_time, true)
	if animation_time >= _end_time: moving = false

func _matching_time(start: float, end: float) -> float:
	var best_time := start
	var best_distance := INF
	for sample in 151:
		var candidate := lerpf(start, end, float(sample) / 150.0)
		var distance := 0.0
		for track in _clip.get_track_count():
			if _clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
				distance += _clip.position_track_interpolate(track, animation_time).distance_squared_to(_clip.position_track_interpolate(track, candidate))
		if distance < best_distance:
			best_distance = distance
			best_time = candidate
	return best_time
