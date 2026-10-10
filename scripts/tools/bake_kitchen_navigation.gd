extends SceneTree
## Run with --headless --path <project> --script res://scripts/tools/bake_kitchen_navigation.gd
## Rebuild after moving the kitchen's static geometry. Does not change the scene.

func _initialize() -> void: bake.call_deferred()

func bake() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(scene)
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.agent_height = 1.5
	mesh.agent_radius = 0.45
	mesh.agent_max_climb = 0.2
	mesh.cell_size = 0.15
	mesh.cell_height = 0.1
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, data, scene)
	NavigationServer3D.bake_from_source_geometry_data(mesh, data)
	if mesh.get_polygon_count() == 0:
		push_error("Kitchen navigation bake produced no walkable polygons.")
		quit(1)
		return
	var error := ResourceSaver.save(mesh, "res://resources/navigation/kitchen_navigation.tres")
	print("Kitchen navigation: %d polygons; save result %d" % [mesh.get_polygon_count(), error])
	quit(0 if error == OK else 1)
