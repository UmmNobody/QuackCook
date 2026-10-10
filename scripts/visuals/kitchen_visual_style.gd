extends Node3D
## Visual-only preset. Does not change gameplay, collision, or imported assets.
@export var enabled: bool = true
@export_range(0.0, 1.0) var ambient_strength: float = 0.50
@export_range(0.0, 3.0) var ceiling_strength: float = 0.70
@export var shadow_color: Color = Color("dce7ee")
@export var warm_light_color: Color = Color("fffdf7")
@export var subtle_prop_outlines: bool = true
const TOON = preload("res://shaders/kitchen_zip_toon.gdshader")
var _materials: Dictionary = {}
var _outline_materials: Dictionary = {}
var _scope: Node
var _styled_count: int = 0

func _ready() -> void:
	if enabled:
		call_deferred("apply_style")

func apply_style() -> void:
	_scope = get_parent()
	configure_lighting()
	for node in _scope.find_children("*", "MeshInstance3D", true, false):
		style_mesh(node)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	print("KITCHEN_STYLE_READY meshes=", _styled_count, " ceiling_lights=6 shadowed_ceiling_lights=2")

func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D:
		call_deferred("_style_added_mesh", weakref(node))

func _style_added_mesh(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if is_instance_valid(node) and is_instance_valid(_scope) and _scope.is_ancestor_of(node):
		style_mesh(node)

func style_mesh(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null or str(mesh.name).to_lower().contains("outline") or mesh.has_meta("kitchen_styled"):
		return
	for surface in range(mesh.mesh.get_surface_count()):
		var source = mesh.get_active_material(surface)
		if not source is StandardMaterial3D:
			continue
		# Preserve glass, emissive lamps, unshaded UI meshes and special effects.
		if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.emission_enabled or source.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
			continue
		var key: int = source.get_instance_id()
		if not _materials.has(key):
			var material = ShaderMaterial.new()
			material.resource_name = "SoftToon_" + source.resource_name
			material.shader = TOON
			material.set_shader_parameter("pattern_texture", load("res://assets/textures/kitchen_daylight/pattern_14.png"))
			material.set_shader_parameter("floor_pattern", load("res://assets/textures/kitchen_daylight/pattern_14.png"))
			material.set_shader_parameter("albedo_color", source.albedo_color)
			material.set_shader_parameter("use_texture", source.albedo_texture != null)
			if source.albedo_texture != null:
				material.set_shader_parameter("albedo_texture", source.albedo_texture)
			material.set_shader_parameter("uv_scale", source.uv1_scale)
			material.set_shader_parameter("uv_offset", source.uv1_offset)
			material.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
			material.set_shader_parameter("vertex_is_srgb", source.vertex_color_is_srgb)
			var architectural: bool = source.resource_name.begins_with("Material_3") or source.resource_name.begins_with("Material_5") or source.resource_name.contains("Wall") or source.resource_name.contains("Floor") or source.resource_name.contains("Roof")
			material.set_shader_parameter("specular", 0.0 if architectural else 0.06)
			if source.normal_enabled and source.normal_texture != null:
				material.set_shader_parameter("normal_texture", source.normal_texture)
				material.set_shader_parameter("normal_strength", source.normal_scale)
			material.set_shader_parameter("use_rim", false)
			material.set_shader_parameter("use_pattern", false)
			material.set_shader_parameter("steps", 3.0)
			material.set_shader_parameter("step_smoothness", 0.22)
			material.set_shader_parameter("shadow_tint", Color("afb9d1"))
			material.set_shader_parameter("shadow_tint_amount", 0.25)
			material.next_pass = source.next_pass
			_materials[key] = material
		var styled: ShaderMaterial = _materials[key]
		# Focus outlines use separate OutlineMesh/material_overlay and remain untouched.
		var label = str(mesh.get_path()).to_lower()
		var is_prop = label.contains("jar_") or label.contains("ketchup") or label.contains("/items/") or label.contains("prisoner")
		var ancestor = mesh.get_parent()
		while ancestor != null and ancestor != _scope:
			if ancestor is FoodItem:
				is_prop = true
				break
			ancestor = ancestor.get_parent()
		if subtle_prop_outlines and is_prop and source.next_pass == null:
			var outline_key = str(key) + "_" + str(mesh.global_basis.get_scale())
			if not _outline_materials.has(outline_key):
				var copy: ShaderMaterial = styled.duplicate()
				var outline = StandardMaterial3D.new()
				outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				outline.cull_mode = BaseMaterial3D.CULL_FRONT
				outline.albedo_color = Color("30343f")
				outline.grow = true
				outline.grow_amount = 0.008 / maxf(mesh.global_basis.get_scale().abs().x, 0.05)
				copy.next_pass = outline
				_outline_materials[outline_key] = copy
			styled = _outline_materials[outline_key]
		# A material_override takes precedence over per-surface overrides.
		if mesh.material_override != null:
			mesh.material_override = styled
			break
		mesh.set_surface_override_material(surface, styled)
	mesh.set_meta("kitchen_styled", true)
	_styled_count += 1

func configure_lighting() -> void:
	var world_nodes = _scope.find_children("*", "WorldEnvironment", true, false)
	var world: WorldEnvironment
	if world_nodes.is_empty():
		world = WorldEnvironment.new()
		add_child(world)
	else:
		world = world_nodes[0]
	var env = world.environment.duplicate() if world.environment != null else Environment.new()
	env.sky = load("res://resources/visuals/kitchen_daylight_sky.tres")
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = shadow_color
	env.ambient_light_energy = ambient_strength
	env.ambient_light_sky_contribution = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.0
	world.environment = env
	for sun in _scope.find_children("*", "DirectionalLight3D", true, false):
		sun.light_color = warm_light_color
		sun.light_energy = 0.85
		sun.rotation_degrees = Vector3(-48, -35, 0)
		sun.shadow_enabled = true
		sun.shadow_bias = 0.3
		sun.shadow_normal_bias = 2.0
	if get_node_or_null("CeilingRig") != null:
		return
	var rig = Node3D.new()
	rig.name = "CeilingRig"
	add_child(rig)
	# Lights follow the imported model transform, including its 0.4 import scale.
	var fixture_meshes = _scope.find_children("Ceiling_Light_Housing*", "MeshInstance3D", true, false)
	for index in range(fixture_meshes.size()):
		var fixture: MeshInstance3D = fixture_meshes[index]
		var lamp = SpotLight3D.new()
		lamp.name = "Ceiling_%02d" % (index + 1)
		rig.add_child(lamp)
		lamp.global_position = fixture.global_transform * fixture.mesh.get_aabb().get_center() + Vector3(0, -0.16, 0)
		lamp.rotation_degrees.x = -90
		lamp.light_color = warm_light_color
		lamp.light_energy = ceiling_strength
		lamp.light_specular = 0.2
		lamp.spot_range = 10.0
		lamp.spot_angle = 72.0
		lamp.spot_attenuation = 0.6
		lamp.spot_angle_attenuation = 0.35
		lamp.shadow_enabled = index in [1, 4]
		lamp.shadow_bias = 0.3
		lamp.shadow_normal_bias = 1.5


