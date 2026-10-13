extends Node3D

@onready var animation_player: AnimationPlayer = $Police/AnimationPlayer

func _ready() -> void:
	# Keep the imported model untouched; this scene owns its looping animation.
	var library := animation_player.get_animation_library("").duplicate(true) as AnimationLibrary
	animation_player.remove_animation_library("")
	animation_player.add_animation_library("", library)
	library.get_animation("Police_Dance_01").loop_mode = Animation.LOOP_LINEAR
	animation_player.play("Police_Dance_01")
