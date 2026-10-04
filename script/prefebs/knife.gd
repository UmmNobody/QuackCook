extends RigidBody3D
class_name Knife

@export var min_cut_speed: float = 3.0
@export var spin_speed: float = 25.0

@export var min_throw_force: float = 5.0
@export var max_throw_force: float = 25.0

@export var min_bounces: int = 1
@export var max_bounces: int = 4

var is_stuck: bool = false
var current_bounces: int = 0
var target_bounces: int = 1

@onready var outline_mesh = $MeshInstance3D/OutlineMesh
var player: Node3D = null

func _ready() -> void:
	player = get_tree().get_first_node_in_group("Player")
	if player and player.head:
		player.head.object_focused.connect(_set_selected)
	
	outline_mesh.visible = false
	
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

func _set_selected(object: Node) -> void:
	outline_mesh.visible = (self == object)

# --- Throw System ---

func throw(throw_force: Vector3) -> void:
	is_stuck = false
	freeze = false
	reparent(get_tree().current_scene)
	
	var force_magnitude: float = throw_force.length()
	
	var raw_bounces: float = remap(force_magnitude, min_throw_force, max_throw_force, float(max_bounces), float(min_bounces))
	target_bounces = clampi(roundi(raw_bounces), min_bounces, max_bounces)
	current_bounces = 0

	apply_central_impulse(throw_force)
	angular_velocity = global_transform.basis.x * spin_speed
	
	print("ปามีดแรง: ", force_magnitude, " -> ตั้งค่าให้เด้ง: ", target_bounces, " ครั้ง")

func _on_body_entered(body: Node) -> void:
	if is_stuck:
		return

	if body.is_in_group("Cuttable") and linear_velocity.length() >= min_cut_speed:
		if body.has_method("cut"):
			body.cut()
			linear_velocity *= 0.5
		return

	if not (body.is_in_group("Cuttable")):
		current_bounces += 1
		
		if current_bounces >= target_bounces:
			stick_to_surface(body)
		else:
			angular_velocity *= 0.6
			linear_velocity *= 0.8

func stick_to_surface(surface: Node) -> void:
	is_stuck = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true

func pick_up_knife() -> void:
	is_stuck = false
	freeze = false
	current_bounces = 0
