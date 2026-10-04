extends RigidBody3D
class_name FoodItem

enum Type { NONE, RICE, CHICKEN, CARROT, CABBAGE, MIXED_VEG, WATER }
@export var item_type: Type = Type.NONE

@export var current_state: State = State.RAW:
	set(value):
		current_state = value
		_update_visuals()
		
@export var cook_duration: float = 3.0
var cook_progress: float = 0.0

var is_cooking: bool = false
var cook_timer: float = 0.

enum State { RAW, CUT, COOKED, BURNT }
		
@export var raw_mesh: Node3D
@export var cut_mesh: Node3D
@export var cooked_mesh: Node3D
@export var burnt_mesh: Node3D

func _ready() -> void:
	_update_visuals()
	
	var player = get_tree().get_first_node_in_group("Player")
	if player and player.head:
		player.head.object_focused.connect(_set_selected)
	
# --- Outline focus system ---
func _set_selected(object: Node) -> void:
	var is_focused := (self == object)
	var active_mesh := _get_active_mesh()
	
	if active_mesh:
		var outline = active_mesh.get_node_or_null("OutlineMesh")
		if outline:
			outline.visible = is_focused

func _get_active_mesh() -> MeshInstance3D:
	match current_state:
		State.RAW:
			return raw_mesh as MeshInstance3D
		State.CUT:
			return cut_mesh as MeshInstance3D
		State.COOKED:
			return cooked_mesh as MeshInstance3D
		State.BURNT:
			return burnt_mesh as MeshInstance3D
	return null

# --- Interact system ---
func interact_with(held_item: Node, player_head: Node) -> bool:
	if held_item is Pan:
		var pan := held_item as Pan
		if pan.can_accept_food(self):
			pan.add_food(self)
			return true
	
	if held_item is Tray:
		var tray := held_item as Tray
		if tray.current_food == null:
			print("current null")
			if tray.can_accept_food(self):
				tray.add_food(self)
				return true
		else:
			print("current full")
			if tray.can_combine(tray.current_food, self):
				tray.combine_food(self)
				return true

	return false

# --- Cooking System ---

func cook() -> void:
	if current_state == State.RAW or current_state == State.CUT:
		current_state = State.COOKED
		
func _update_visuals() -> void:
	if not is_node_ready():
		await ready
		
	if raw_mesh: raw_mesh.visible = (current_state == State.RAW)
	if cut_mesh: cut_mesh.visible = (current_state == State.CUT)
	if cooked_mesh: cooked_mesh.visible = (current_state == State.COOKED)
	if burnt_mesh:burnt_mesh.visible = (current_state == State.BURNT)

func cut():
	if current_state == State.RAW:
		current_state = State.CUT

# Cooking
func get_cook_duration() -> float:
	return cook_duration

func get_cook_progress() -> float:
	return cook_progress

func add_cook_progress(amount: float) -> void:
	if can_be_cooked():
		cook_progress += amount
		if cook_progress >= cook_duration:
			cook()

func can_be_cooked() -> bool:
	return (current_state == State.RAW or current_state == State.CUT) and cook_progress < cook_duration
