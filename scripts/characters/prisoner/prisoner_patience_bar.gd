extends Node3D
## Camera-facing vertical bar. Geometry and independent material live in the scene.
@export var full_color: Color = Color(0.25, 0.85, 0.4, 1.0)
@export var middle_color: Color = Color(1.0, 0.8, 0.18, 1.0)
@export var empty_color: Color = Color(0.95, 0.2, 0.18, 1.0)
@onready var fill: MeshInstance3D = $Fill
@onready var _material: StandardMaterial3D = fill.material_override
@onready var _full_height: float = fill.mesh.size.y
@onready var _center_y: float = fill.position.y

func set_ratio(value: float) -> void:
	var ratio := clampf(value, 0.0, 1.0)
	fill.visible = ratio > 0.0
	fill.scale.y = maxf(ratio, 0.001)
	# Keep the bottom stationary as the top moves down.
	fill.position.y = _center_y - _full_height * (1.0 - ratio) * 0.5
	_material.albedo_color = middle_color.lerp(full_color, (ratio - 0.5) * 2.0) if ratio >= 0.5 else empty_color.lerp(middle_color, ratio * 2.0)

func _process(_delta: float) -> void:
	if not is_visible_in_tree(): return
	var camera := get_viewport().get_camera_3d()
	if camera != null: global_basis = camera.global_basis.orthonormalized()
