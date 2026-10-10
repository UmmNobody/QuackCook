extends RigidBody3D
class_name Tray

@export var mixed_veg_scene: PackedScene

@onready var food_snap_point: Marker3D = $FoodSnapPoint
@onready var outline_mesh: MeshInstance3D = $MeshInstance3D/OutlineMesh

var current_food: FoodItem = null
var player: Node3D = null

func _ready() -> void:
	player = get_tree().get_first_node_in_group("Player")
	if player and player.head:
		player.head.object_focused.connect(_set_selected)
	if outline_mesh:
		outline_mesh.visible = false

func _set_selected(object: Node) -> void:
	if outline_mesh:
		outline_mesh.visible = (self == object)

func interact_with(held_item: Node, player_head: Node) -> bool:
	# 1. ถืออาหารมาใส่หรือผสมในถาด
	if held_item is FoodItem:
		var food := held_item as FoodItem
		if current_food == null:
			if can_accept_food(food):
				player_head.drop_object()
				add_food(food)
				return true
		else:
			if can_combine(current_food, food):
				player_head.drop_object()
				combine_food(food)
				return true
		return true

	# 2. ถือกระทะหรือหม้อมาปฏิสัมพันธ์กับถาด
	if held_item is Cookware:
		var cookware := held_item as Cookware
		return cookware.handle_tray_transfer(self)

	return false

func can_accept_food(food: FoodItem) -> bool:
	if food == null:
		return false
	if current_food != null:
		return can_combine(current_food, food)
	if food.current_state == FoodItem.State.COOKED:
		return true
	if food.current_state == FoodItem.State.CUT and (food.item_type == FoodItem.Type.CARROT or food.item_type == FoodItem.Type.CABBAGE):
		return true
	if food.item_type == FoodItem.Type.MIXED_VEG:
		return true
	return false

func can_combine(f1: FoodItem, f2: FoodItem) -> bool:
	if f1 == null or f2 == null:
		return false
	if f1.current_state != FoodItem.State.CUT or f2.current_state != FoodItem.State.CUT:
		return false
	var pair := [f1.item_type, f2.item_type]
	pair.sort()
	return pair == [FoodItem.Type.CARROT, FoodItem.Type.CABBAGE]

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

func combine_food(food: FoodItem) -> bool:
	if not can_combine(current_food, food):
		return false

	var old_food := current_food
	current_food = null
	old_food.queue_free()
	food.queue_free()

	if mixed_veg_scene:
		var mixed_veg := mixed_veg_scene.instantiate() as FoodItem
		get_parent().add_child(mixed_veg)
		add_food(mixed_veg)
	return true

func remove_food() -> FoodItem:
	if current_food == null:
		return null
		
	var food_to_remove := current_food
	current_food = null
	
	food_to_remove.freeze = false
	var food_col = food_to_remove.get_node_or_null("CollisionShape3D")
	if food_col:
		food_col.disabled = false
		
	food_to_remove.reparent(get_parent())
	return food_to_remove

func clear_food() -> void:
	if current_food:
		current_food.queue_free()
		current_food = null
