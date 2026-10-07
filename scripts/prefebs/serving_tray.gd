extends Node3D
## Visual contents of an individual prisoner's tray; independent of kitchen Tray.

const DISCARDED_TRAY_SCRIPT = preload("res://scripts/prefebs/discarded_prisoner_tray.gd")

@onready var food_models: Dictionary = {
	FoodItem.Type.CHICKEN: $Food/Chicken,
	FoodItem.Type.MIXED_VEG: $Food/Vegetables,
	FoodItem.Type.RICE: $Food/Rice,
	FoodItem.Type.WATER: $Food/Water,
}

func _ready() -> void:
	clear_food()

func show_food(food_type: int) -> bool:
	if not food_models.has(food_type): return false
	food_models[food_type].visible = true
	return true

func has_food(food_type: int) -> bool:
	return food_models.has(food_type) and food_models[food_type].visible

func clear_food() -> void:
	for model in food_models.values(): model.visible = false

func throw_into_scene(scene_parent: Node, throw_velocity: Vector3, lifetime: float) -> RigidBody3D:
	var pose: Transform3D = global_transform
	var body := RigidBody3D.new()
	body.set_script(DISCARDED_TRAY_SCRIPT)
	body.name = "DiscardedPrisonerTray"
	body.collision_layer = 0
	body.collision_mask = 1 # World layer; NPCs are on layer 4.
	body.mass = 0.5
	body.continuous_cd = true
	body.remaining_lifetime = lifetime
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.72, 0.07, 0.48)
	collider.shape = box
	body.add_child(collider)
	scene_parent.add_child(body)
	# Player currently shares the world's layer, so exclude it explicitly.
	for player in get_tree().get_nodes_in_group("Player"):
		if player is PhysicsBody3D: body.add_collision_exception_with(player)
	body.global_transform = pose
	# Reparent the same tray, preserving every food already on it.
	reparent(body, true)
	body.linear_velocity = throw_velocity
	body.angular_velocity = Vector3(3.0, 1.5, 2.0)
	return body
