extends StaticBody3D
class_name Trash

@onready var outline_mesh = $MeshInstance3D/OutlineMesh

var player: Node3D = null
var last_trashed_item: PackedScene = null

func _ready() -> void:
	player = get_tree().get_first_node_in_group("Player")
	if player and player.head:
		player.head.object_focused.connect(_set_selected)
	
	outline_mesh.visible = false

func _set_selected(object: Node) -> void:
	outline_mesh.visible = (self == object)

func interact_with(held_item: Node, player_head: Node) -> bool:
	if held_item == null:
		return false

	tween_effect()

	if held_item is Pan or held_item is Tray:
		if held_item.current_food != null:
			held_item.clear_food()
			return true
		return false

	player_head.drop_object()
	held_item.queue_free()
	return true


func tween_effect() -> void:
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(1.1, 0.8, 1.1), 0.08)
	tween.tween_property(self, "scale", Vector3(1.0, 1.0, 1.0), 0.1)
