extends StaticBody3D
## This button belongs to its parent food well and serves exactly one portion.

@onready var outline: MeshInstance3D = $OutlineMesh

## Optional station callback supplied by a queue scene. Standalone tables still work.
var serve_handler: Callable

func _ready() -> void:
	outline.visible = false
	_connect_focus.call_deferred()

func _connect_focus() -> void:
	var player = get_tree().get_first_node_in_group("Player")
	if player:
		var head = player.get_node_or_null("Head")
		if head and head.has_signal("object_focused"):
			head.object_focused.connect(_set_selected)

func _set_selected(target: Node) -> void:
	outline.visible = target == self

func interact_with(_held_item: Node, _player_head: Node) -> bool:
	if serve_handler.is_valid():
		serve_handler.call()
	else:
		get_parent().serve_one()
	return true
