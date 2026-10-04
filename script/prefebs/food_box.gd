extends StaticBody3D

@export var food_scene:PackedScene

@onready var outline_mesh = $MeshInstance3D/OutlineMesh

var player: Node3D = null

func _ready() -> void:
	player = get_tree().get_first_node_in_group("Player")
	if player and player.head:
		player.head.object_focused.connect(_set_selected)
	
	outline_mesh.visible = false
	
func _set_selected(object: Node) -> void:
	outline_mesh.visible = (self == object)
	
func interact_with(held_item: Node, player_head: Node) -> bool:
	if held_item != null:
		return true

	if not food_scene:
		push_warning("ยังไม่ได้ตั้งค่า food_scene ใน Inspector!")
		return false

	var new_food = food_scene.instantiate()
	get_tree().current_scene.add_child(new_food)
	new_food.global_position = global_position + Vector3(0, 0.5, 0)
	
	player_head.pick_up(new_food)

	return false
