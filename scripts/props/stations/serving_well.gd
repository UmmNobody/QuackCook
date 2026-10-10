extends StaticBody3D
## One refillable food well. Counts are portions, not physical FoodItem nodes.

signal servings_changed(current: int, maximum: int)

@export_group("Food")
@export var accepted_type: FoodItem.Type = FoodItem.Type.CHICKEN
@export var accepted_state: FoodItem.State = FoodItem.State.COOKED

@export_group("Servings")
## Maximum portions this well can store.
@export_range(1, 100, 1, "or_greater") var capacity: int = 4:
	set(value):
		capacity = maxi(1, value)
		if is_node_ready():
			current_servings = current_servings
## One accepted FoodItem is consumed for each successful refill.
@export_range(1, 100, 1, "or_greater") var servings_per_refill: int = 4:
	set(value):
		servings_per_refill = maxi(1, value)
## Applied once when this scene enters the game; clamped to capacity.
@export_range(0, 100, 1, "or_greater") var initial_servings: int = 0

var current_servings: int = 0:
	set(value):
		current_servings = clampi(value, 0, capacity)
		if is_node_ready():
			_update_display()
			servings_changed.emit(current_servings, capacity)

@onready var outline: Node3D = $OutlineMesh
@onready var food_display: Node3D = $FoodDisplay
@onready var count_label: Label3D = $CountLabel

func _ready() -> void:
	outline.visible = false
	current_servings = initial_servings
	_connect_focus.call_deferred()

func _connect_focus() -> void:
	var player = get_tree().get_first_node_in_group("Player")
	if player:
		var head = player.get_node_or_null("Head")
		if head and head.has_signal("object_focused"):
			head.object_focused.connect(_set_selected)

func _set_selected(target: Node) -> void:
	outline.visible = target == self

func can_accept_food(food: FoodItem) -> bool:
	return (
		current_servings < capacity
		and is_instance_valid(food)
		and not food.is_queued_for_deletion()
		and food.item_type == accepted_type
		and food.current_state == accepted_state
	)

func interact_with(held_item: Node, player_head: Node) -> bool:
	# Always consume this click, including failed refills, to avoid charging a throw.
	var food: FoodItem = null
	var in_container := held_item is Cookware or held_item is Tray
	if in_container:
		food = held_item.current_food
	elif held_item is FoodItem and held_item.item_type == FoodItem.Type.WATER:
		food = held_item as FoodItem

	if not can_accept_food(food):
		return true

	if in_container:
		held_item.clear_food()
	else:
		player_head.drop_object()
		food.queue_free()
	current_servings += servings_per_refill
	return true

## Called by this well's button now; later the serving system can use the result.
func serve_one() -> bool:
	if current_servings <= 0:
		return false
	current_servings -= 1
	return true

func _update_display() -> void:
	count_label.text = "%d/%d" % [current_servings, capacity]
	food_display.visible = current_servings > 0
