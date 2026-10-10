extends Node
## Advance imported hinge clips with physics, including smooth mid-animation reversal.
@export var animation_player_path: NodePath
@export var open_animation: StringName
@export var close_animation: StringName
@export_range(0.1, 8.0) var playback_speed: float = 1.0
var target_open := false
@onready var player: AnimationPlayer = get_node(animation_player_path)

func _ready() -> void:
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(close_animation)
	player.seek(player.get_animation(close_animation).length, true)
	player.pause()

func set_open(open: bool) -> void:
	if open == target_open: return
	target_open = open
	var clip: Animation = player.get_animation(open_animation if open else close_animation)
	var hinge := player.get_node(player.root_node).get_node(clip.track_get_path(0)) as Node3D
	var current := hinge.quaternion
	var best_time := 0.0
	var best_distance := INF
	for i in 101:
		var time := clip.length * float(i) / 100.0
		var pose := clip.rotation_track_interpolate(0, time)
		var distance := current.angle_to(pose)
		if distance < best_distance:
			best_distance = distance
			best_time = time
	player.play(open_animation if open else close_animation, 0.0, playback_speed)
	player.seek(best_time, true)
	player.advance(0.0)

func advance(delta: float) -> void:
	if player.is_playing(): player.advance(delta)

func fully_open() -> bool:
	return target_open and not player.is_playing()
