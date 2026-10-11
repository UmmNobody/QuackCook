extends StaticBody3D
class_name Stove

@onready var outline_mesh = $MeshInstance3D/OutlineMesh
@onready var stove_snap_point: Marker3D = $PanSnapPoint
@onready var fire: CPUParticles3D = $PanSnapPoint/StoveFire

# --- Node UI 3D ---
@onready var cooking_ui_3d: Sprite3D = $CookingUI3D
@onready var progress_bar: ProgressBar = $CookingUI3D/SubViewport/ProgressBar

var player: Node3D = null
var current_cookware: Cookware = null

func _ready() -> void:
	player = get_tree().get_first_node_in_group("Player")
	if player and player.head:
		player.head.object_focused.connect(_set_selected)
	
	if outline_mesh:
		outline_mesh.visible = false
		
	_hide_cooking_ui()

func _set_selected(object: Node) -> void:
	if outline_mesh:
		outline_mesh.visible = (self == object)

func interact_with(held_item: Node, player_head: Node) -> bool:
	if held_item is Cookware and current_cookware == null:
		var cookware := held_item as Cookware
		player_head.drop_object()
		place_cookware(cookware)
		return true

	if held_item is FoodItem and current_cookware != null:
		var food := held_item as FoodItem
		if current_cookware.can_accept_food(food):
			player_head.drop_object()
			current_cookware.add_food(food)
			_setup_cooking_ui()
			return true

	if held_item == null and current_cookware != null:
		var cookware := current_cookware
		current_cookware = null
		cookware.remove_from_stove()
		player_head.pick_up(cookware)
		_hide_cooking_ui()
		return true

	return false

func place_cookware(cookware: Cookware) -> bool:
	if current_cookware != null:
		return false
		
	current_cookware = cookware
	current_cookware.place_on_stove(self, stove_snap_point)
	_setup_cooking_ui()
	return true

func _setup_cooking_ui() -> void:
	if current_cookware and current_cookware.current_food:
		var food := current_cookware.current_food
		progress_bar.max_value = food.cook_duration
		progress_bar.value = food.cook_progress
		cooking_ui_3d.visible = true
	else:
		_hide_cooking_ui()
	_update_fire()

func _hide_cooking_ui() -> void:
	cooking_ui_3d.visible = false
	fire.set_active(false)

func _update_fire() -> void:
	var cooking := is_instance_valid(current_cookware) and current_cookware.is_on_stove
	cooking = cooking and is_instance_valid(current_cookware.current_food)
	fire.set_active(cooking and current_cookware.current_food.can_be_cooked())

func _physics_process(delta: float) -> void:
	if current_cookware and current_cookware.current_food:
		var food := current_cookware.current_food
		
		if food.can_be_cooked():
			food.add_cook_progress(delta)
			progress_bar.value = food.cook_progress
			
			if not cooking_ui_3d.visible:
				_setup_cooking_ui()
	_update_fire()

func _on_snap_area_body_entered(body: Node3D) -> void:
	if body is Cookware:
		var cookware := body as Cookware
		
		if current_cookware != null or cookware.is_on_stove:
			return
			
		if player and player.head and player.head.carried_object == cookware:
			return
			
		place_cookware(cookware)
