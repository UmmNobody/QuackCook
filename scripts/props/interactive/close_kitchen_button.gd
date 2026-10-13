extends StaticBody3D
## Lever pose follows accepted kitchen state, including automatic opening.
@export var highlight_material: Material
@onready var motion = $Motion
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	for mesh in $Lever.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mesh)
	var player := get_tree().get_first_node_in_group("Player")
	if player != null: player.get_node("Head").object_focused.connect(_on_focus)
	GameManager.session_changed.connect(_sync_kitchen_state)
	_on_focus(null)
	_sync_kitchen_state()

func _on_focus(target: Node) -> void:
	for mesh in _meshes:
		mesh.material_overlay = highlight_material if target == self else null

func _sync_kitchen_state() -> void:
	motion.set_open(GameManager.state == GameManager.State.SERVING)

func _physics_process(delta: float) -> void:
	# The report pauses gameplay; let the closing lever finish alongside the shutter.
	if get_tree().paused:
		if GameManager.state != GameManager.State.SUMMARY or GameManager.pause_menu_open: return
	motion.advance(delta)

func interact_with(_item: Node, player_head: Node) -> bool:
	if get_tree().paused: return true
	if player_head != null and player_head.has_method("interaction_allowed") and not player_head.interaction_allowed(): return true
	if GameManager.state == GameManager.State.PREPARING:
		if GameManager.open_kitchen(): AudioManager.cue("lever1", self, true)
	else:
		if not GameManager.finish_service().is_empty(): AudioManager.cue("lever2", self, true)
	return true
