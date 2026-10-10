extends StaticBody3D

@onready var outline: MeshInstance3D = $Outline
@onready var indicator: MeshInstance3D = $Button
@onready var title: Label3D = $Title
@onready var hint: Label3D = $Hint
var focused: bool = false
var indicator_material: StandardMaterial3D

func _ready() -> void:
	indicator_material = indicator.material_override.duplicate()
	indicator.material_override = indicator_material
	var player := get_tree().get_first_node_in_group("Player")
	if player != null: player.get_node("Head").object_focused.connect(_on_focus)
	_on_focus(null)

func _on_focus(target: Node) -> void:
	focused = target == self
	outline.visible = focused
	hint.visible = focused

func _process(_delta: float) -> void:
	indicator_material.albedo_color = Color("89bca4") if GameManager.can_open_kitchen() or GameManager.can_close_kitchen() else Color("777e88")
	var preparing := GameManager.state == GameManager.State.PREPARING
	title.text = "OPEN\nKITCHEN" if preparing else "CLOSE\nKITCHEN"
	if focused:
		hint.text = "Open kitchen now (%d s remaining)" % ceili(GameManager.preparation_remaining) if preparing else GameManager.close_block_reason()

func interact_with(_item: Node, player_head: Node) -> bool:
	if player_head != null and player_head.has_method("interaction_allowed") and not player_head.interaction_allowed(): return true
	if GameManager.state == GameManager.State.PREPARING:
		GameManager.open_kitchen()
	else:
		GameManager.finish_service()
	return true
