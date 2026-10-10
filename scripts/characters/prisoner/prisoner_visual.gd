extends Node3D
## Owns presentation only. The prisoner/queue still own movement and decisions.

@export_range(1.0, 30.0) var turn_speed: float = 12.0
@export var tray_hand_offset: Vector3 = Vector3(0, 0.025, 0.04)

@export_group("Hit Feedback")
@export var hit_color: Color = Color(1.0, 0.6, 0.6)
@export_range(0.0, 1.0) var hit_color_strength: float = 0.7
@export_range(0.0, 0.2) var hit_squash_amount: float = 0.08

var hit_materials: Array[BaseMaterial3D] = []
var base_colors: Array[Color] = []
var flash_tween: Tween
var squash_tween: Tween
var hit_flash: float = 0.0
@onready var model: Node3D = $Model
@onready var base_model_scale: Vector3 = $Model.scale

@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer
@onready var skeleton: Skeleton3D = $Model/ROOT/Armature/Skeleton3D
var target_yaw: float = 0.0
var left_hand: int
var right_hand: int
var head_style: StringName = &""

# Empty name is the sixth option: no hair, hat or blindfold.
const HEAD_STYLES: Array[StringName] = [&"Blindfold", &"Hair_Black", &"Hair_Brown", &"Hair_Gold", &"Hat_Prisoner", &""]

const LOOPING: Array[StringName] = [&"P1_Idle", &"P1_Walk_Waddle_Blockout", &"P1_Tray_Idle", &"P1_Tray_Walk", &"P1_Combat_Idle", &"P1_Combat_Walk"]

func _ready() -> void:
	# GLB libraries are shared resources. Make loop settings local to this instance.
	for library_name in animation_player.get_animation_library_list():
		var library: AnimationLibrary = animation_player.get_animation_library(library_name).duplicate(true)
		animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, library)
	for clip in animation_player.get_animation_list():
		animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	left_hand = skeleton.find_bone("hand.L")
	right_hand = skeleton.find_bone("hand.R")
	# Local material copies keep one prisoner's flash from tinting every instance.
	for mesh in skeleton.get_children():
		if not mesh is MeshInstance3D or mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var original = mesh.get_active_material(surface)
			if original is BaseMaterial3D:
				var material: BaseMaterial3D = original.duplicate()
				mesh.set_surface_override_material(surface, material)
				hit_materials.append(material)
				base_colors.append(material.albedo_color)
	# Choose once per prisoner. Hide every other option, including the default hat.
	head_style = HEAD_STYLES.pick_random()
	for part in HEAD_STYLES:
		if not part.is_empty(): skeleton.get_node(NodePath(part)).visible = part == head_style
	set_combat_hands(false)
	play(&"P1_Idle")
	animation_player.advance(0)

func play_hit_feedback(allow_squash: bool = true) -> void:
	if flash_tween != null and flash_tween.is_valid(): flash_tween.kill()
	_set_hit_flash(1.0)
	flash_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	flash_tween.tween_method(_set_hit_flash, 1.0, 0.0, 0.10)
	flash_tween.tween_method(_set_hit_flash, 0.0, 0.8, 0.05)
	flash_tween.tween_method(_set_hit_flash, 0.8, 0.0, 0.16)
	# Never leave a scaled Skeleton under the physics ragdoll on a lethal hit.
	if squash_tween != null and squash_tween.is_valid(): squash_tween.kill()
	model.scale = base_model_scale
	if not allow_squash: return
	squash_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var squash := Vector3(1.0 + hit_squash_amount * 0.6, 1.0 - hit_squash_amount, 1.0 + hit_squash_amount * 0.6)
	squash_tween.tween_property(model, "scale", base_model_scale * squash, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	squash_tween.tween_property(model, "scale", base_model_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _set_hit_flash(amount: float) -> void:
	hit_flash = amount
	for i in hit_materials.size():
		hit_materials[i].albedo_color = base_colors[i].lerp(hit_color, amount * hit_color_strength)

func clip_duration(clip: StringName) -> float:
	return animation_player.get_animation(clip).length

func play(clip: StringName, speed: float = 1.0, restart: bool = false) -> void:
	if not restart and animation_player.assigned_animation == clip: return
	animation_player.play(clip, 0.12, speed)

func set_combat_hands(enabled: bool) -> void:
	for side in ["L", "R"]:
		skeleton.get_node("Hand_Fist_" + side).visible = enabled
		skeleton.get_node("Hand_Hold_" + side).visible = not enabled

func face_direction(direction: Vector3) -> void:
	direction.y = 0
	if direction.length_squared() < 0.0001: return
	var local_direction: Vector3 = get_parent().global_basis.inverse() * direction
	target_yaw = atan2(local_direction.x, local_direction.z) # GLB faces +Z.

func advance(delta: float, tray_point: Node3D) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
	animation_player.advance(delta)
	sync_tray(tray_point)

func sync_tray(tray_point: Node3D) -> void:
	var left: Vector3 = skeleton.get_bone_global_pose(left_hand).origin
	var right: Vector3 = skeleton.get_bone_global_pose(right_hand).origin
	# Follow both hands rather than the imported HandSocket nodes (which are static).
	var across: Vector3 = (left - right).normalized()
	var forward: Vector3 = across.cross(Vector3.UP).normalized()
	var up: Vector3 = forward.cross(across).normalized()
	var grip_basis := Basis(across, up, forward)
	tray_point.global_transform = skeleton.global_transform * Transform3D(grip_basis, (left + right) * 0.5 + grip_basis * tray_hand_offset)
