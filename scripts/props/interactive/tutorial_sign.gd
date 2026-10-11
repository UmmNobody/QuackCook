extends StaticBody3D
## Fixed wall guide, using the same focus and interaction contract as kitchen props.

@onready var outline: MeshInstance3D = $Outline
@onready var hint: Label3D = get_node_or_null("Hint")

func _ready() -> void:
	var player := get_tree().get_first_node_in_group("Player")
	if player != null: player.get_node("Head").object_focused.connect(_on_focus)
	_on_focus(null)

func _on_focus(target: Node) -> void:
	outline.visible = target == self
	if hint != null: hint.visible = target == self

func interact_with(_item: Node, player_head: Node) -> bool:
	if player_head != null and not player_head.interaction_allowed(): return true
	GameManager.open_tutorial()
	return true
