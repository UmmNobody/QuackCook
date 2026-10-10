extends StaticBody3D

@export var highlight_material: Material
@onready var motion = $Motion
@onready var door_body: AnimatableBody3D = $DoorCollision
@onready var body_mesh: MeshInstance3D = $Model/Fridge/fridge_B_ROOT_001/fridge_B_001
@onready var door_mesh: MeshInstance3D = $Model/Fridge/fridge_B_ROOT_001/Fridge_Hinge_CTRL_001/fridge_B_door_001
@onready var hint: Label3D = $Hint

func _ready() -> void:
	door_body.global_transform = door_mesh.global_transform
	var player := get_tree().get_first_node_in_group("Player")
	if player and player.head:
		player.head.object_focused.connect(_set_selected)
	_set_selected(null)

func _physics_process(delta: float) -> void:
	motion.advance(delta)
	door_body.global_transform = door_mesh.global_transform
	hint.text = "Close fridge" if motion.target_open else "Open fridge"

func can_access_contents() -> bool:
	return is_node_ready() and motion.fully_open()

func interact_with(_held_item: Node, player_head: Node) -> bool:
	if player_head.interaction_allowed() and not get_tree().paused:
		motion.set_open(not motion.target_open)
	return true

func _set_selected(target: Node) -> void:
	var selected := target == self or target == door_body
	body_mesh.material_overlay = highlight_material if selected else null
	door_mesh.material_overlay = highlight_material if selected else null
	hint.visible = selected
