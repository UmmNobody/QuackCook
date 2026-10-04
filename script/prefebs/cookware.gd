extends RigidBody3D
class_name Cookware

@onready var food_snap_point: Marker3D = $FoodSnapPoint
@onready var outline_mesh: MeshInstance3D = $MeshInstance3D/OutlineMesh

var current_food: FoodItem = null
var is_on_stove: bool = false
var current_stove: Node = null

func _ready() -> void:
	var player = get_tree().get_first_node_in_group("Player")
	if player and player.head:
		player.head.object_focused.connect(_set_selected)
	if outline_mesh:
		outline_mesh.visible = false

func _set_selected(object: Node) -> void:
	if outline_mesh:
		outline_mesh.visible = (self == object)

func interact_with(held_item: Node, player_head: Node) -> bool:
	if held_item is FoodItem and can_accept_food(held_item as FoodItem):
		player_head.drop_object()
		add_food(held_item as FoodItem)
		return true

	if held_item is Tray:
		return handle_tray_transfer(held_item as Tray)

	if held_item == null:
		if is_on_stove:
			remove_from_stove()
		player_head.pick_up(self)
		return true

	return false

# ฟังก์ชันนี้ให้คลาสลูกไป Override เอาเอง
func can_accept_food(food: FoodItem) -> bool:
	if current_food != null or food == null:
		return false
	return food.can_be_cooked()

func add_food(food: FoodItem) -> bool:
	if not can_accept_food(food):
		return false

	current_food = food
	food.freeze = true
	var food_col = food.get_node_or_null("CollisionShape3D")
	if food_col:
		food_col.disabled = true
	
	food.reparent(food_snap_point)
	food.transform = Transform3D.IDENTITY
	return true

func remove_food() -> FoodItem:
	if current_food == null:
		return null
	var food_to_remove := current_food
	current_food = null
	return food_to_remove

func handle_tray_transfer(tray: Tray) -> bool:
	if tray.current_food != null and current_food == null:
		var food_on_tray := tray.current_food
		var is_raw_mixed_veg := (
			food_on_tray.item_type == FoodItem.Type.MIXED_VEG 
			and food_on_tray.current_state == FoodItem.State.RAW
		)
		
		if is_raw_mixed_veg and can_accept_food(food_on_tray):
			var food = tray.remove_food()
			add_food(food)
			return true
			
	elif current_food != null and tray.current_food == null:
		if tray.can_accept_food(current_food):
			var food = remove_food()
			tray.add_food(food)
			return true

	return true

func clear_food() -> void:
	if current_food:
		current_food.queue_free()
		current_food = null

func place_on_stove(stove: Node, snap_point: Marker3D) -> void:
	is_on_stove = true
	current_stove = stove
	freeze = true
	reparent.call_deferred(snap_point)
	global_transform = snap_point.global_transform

func remove_from_stove() -> void:
	if not is_on_stove:
		return
		
	is_on_stove = false
	if current_stove and "current_cookware" in current_stove:
		if current_stove.current_cookware == self:
			current_stove._hide_cooking_ui()
			current_stove.current_cookware = null
			
	current_stove = null
	freeze = false
	reparent(get_tree().current_scene)
