extends RigidBody3D
class_name FoodItem

const BurningFire = preload("res://scenes/effects/particles/burning_fire.tscn")
const BurntMaterial = preload("res://resources/materials/burnt_food.tres")

enum Type { NONE, RICE, CHICKEN, CARROT, CABBAGE, MIXED_VEG, WATER }
@export var item_type: Type = Type.NONE

@export var current_state: State = State.RAW:
	set(value):
		current_state = value
		_update_visuals()
		
@export var cook_duration: float = 3.0
var cook_progress: float = 0.0
@export_range(0.0, 30.0, 0.1) var burn_grace_seconds: float = 3.0
var burn_grace_elapsed: float = 0.0
var burn_progress: float = 0.0
var burning_fire: CPUParticles3D
var _original_materials: Dictionary = {}

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
			return (cooked_mesh if cooked_mesh != null else burnt_mesh) as MeshInstance3D
	return null

# --- Interact system ---
func interact_with(held_item: Node, player_head: Node) -> bool:
	if held_item is Cookware:
		var cookware := held_item as Cookware
		if cookware.can_accept_food(self):
			cookware.add_food(self)
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
	if cooked_mesh: cooked_mesh.visible = current_state in [State.COOKED, State.BURNT]
	if burnt_mesh and burnt_mesh != cooked_mesh:
		burnt_mesh.visible = current_state == State.BURNT and cooked_mesh == null
	var active := _get_active_mesh()
	for mesh in [raw_mesh, cut_mesh, cooked_mesh, burnt_mesh]:
		if not mesh is MeshInstance3D: continue
		if not _original_materials.has(mesh): _original_materials[mesh] = mesh.material_override
		mesh.material_override = BurntMaterial if is_burning() and mesh == active else _original_materials[mesh]
		var outline: Node3D = mesh.get_node_or_null("OutlineMesh")
		if outline != null: outline.visible = false
	if is_burning() and burning_fire == null:
		burning_fire = BurningFire.instantiate()
		burning_fire.name = "BurningFire"
		add_child(burning_fire)
		if active != null:
			var bounds: AABB = (global_transform.affine_inverse() * active.global_transform) * active.get_aabb()
			burning_fire.position = bounds.get_center()
			burning_fire.emission_box_extents = Vector3(maxf(0.05, bounds.size.x * 0.4), maxf(0.03, bounds.size.y * 0.3), maxf(0.05, bounds.size.z * 0.4))
	if burning_fire != null: burning_fire.set_active(is_burning())
	var player := get_tree().get_first_node_in_group("Player")
	if player != null:
		_set_selected(player.head.last_hovered_object if is_instance_valid(player.head.last_hovered_object) else null)

func is_burning() -> bool:
	return current_state == State.BURNT

## Only a stove supplies heat. Removing a container pauses both overcook clocks.
func apply_heat(seconds: float) -> void:
	var remaining := maxf(0.0, seconds)
	if can_be_cooked():
		var cooking_time := minf(remaining, maxf(0.0, cook_duration - cook_progress))
		add_cook_progress(cooking_time)
		remaining -= cooking_time
	if current_state != State.COOKED: return
	var grace_time := minf(remaining, maxf(0.0, burn_grace_seconds - burn_grace_elapsed))
	burn_grace_elapsed += grace_time
	remaining -= grace_time
	if burn_grace_elapsed < burn_grace_seconds: return
	burn_progress = minf(burn_progress + remaining, maxf(0.001, cook_duration))
	if burn_progress >= maxf(0.001, cook_duration): current_state = State.BURNT

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
