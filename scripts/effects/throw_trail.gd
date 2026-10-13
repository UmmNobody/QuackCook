extends MeshInstance3D
## World-space ribbon: old samples stay behind rather than rotating with the item.
@export_range(0.05, 1.0, 0.01) var lifetime: float = 0.22
@export_range(0.01, 0.5, 0.01) var width: float = 0.08
@export var minimum_speed: float = 1.0
@export var teleport_distance: float = 4.0
var target: Node3D
var points: Array[Vector3] = []
var ages: Array[float] = []
var _previous := Vector3.ZERO
var _ribbon := ImmediateMesh.new()

func _ready() -> void:
	mesh = _ribbon
	stop()

func start(body: Node3D) -> void:
	stop()
	target = body
	global_transform = Transform3D.IDENTITY
	_previous = body.global_position
	points.append(_previous)
	ages.append(0.0)
	set_physics_process(true)

func stop() -> void:
	target = null
	points.clear()
	ages.clear()
	_ribbon.clear_surfaces()
	visible = false
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		stop()
		return
	for i in ages.size(): ages[i] += delta
	while not ages.is_empty() and ages[0] >= lifetime:
		ages.pop_front()
		points.pop_front()
	var position_now := target.global_position
	var distance := position_now.distance_to(_previous)
	if distance > teleport_distance:
		points.clear()
		ages.clear()
	elif distance >= maxf(0.005, minimum_speed * delta):
		points.append(position_now)
		ages.append(0.0)
	_previous = position_now
	_draw_ribbon()

func _draw_ribbon() -> void:
	_ribbon.clear_surfaces()
	visible = points.size() >= 2
	var camera := get_viewport().get_camera_3d()
	if not visible or camera == null: return
	_ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var direction := (points[i + 1] - points[i]).normalized()
		var view := (camera.global_position - points[i]).normalized()
		var side := direction.cross(view).normalized()
		if side.length_squared() < 0.01: side = camera.global_basis.x
		var a := clampf(1.0 - ages[i] / lifetime, 0.0, 1.0)
		var b := clampf(1.0 - ages[i + 1] / lifetime, 0.0, 1.0)
		var left_a := points[i] - side * width * a * 0.5
		var right_a := points[i] + side * width * a * 0.5
		var left_b := points[i + 1] - side * width * b * 0.5
		var right_b := points[i + 1] + side * width * b * 0.5
		_vertex(left_a, a)
		_vertex(right_a, a)
		_vertex(left_b, b)
		_vertex(right_a, a)
		_vertex(right_b, b)
		_vertex(left_b, b)
	_ribbon.surface_end()

func _vertex(point: Vector3, opacity: float) -> void:
	_ribbon.surface_set_color(Color(1, 1, 1, opacity * 0.85))
	_ribbon.surface_add_vertex(point)
