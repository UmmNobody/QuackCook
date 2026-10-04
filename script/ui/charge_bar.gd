extends ProgressBar

@export var player_controller: Node3D 

func _ready() -> void:
	visible = false
	max_value = 1.0
	min_value = 0.0
	value = 0.0
	
	var player = get_tree().get_first_node_in_group("Player")
	if player:
		player.get_node("Head").charge_updated.connect(_on_charge_updated)

func _on_charge_updated(progress_ratio: float) -> void:
	value = progress_ratio
	visible = progress_ratio > 0.0
