extends Control
## Lightweight scene: never preload the kitchen here, or the loading UI cannot draw first.
signal load_completed(scene: PackedScene)

@export_file("*.tscn") var target_scene: String = "res://scenes/main.tscn"
## Useful for testing the web loading path in the editor.
@export var force_incremental_loading: bool = false
@onready var progress_bar: ProgressBar = %Progress
@onready var status_label: Label = %Status
@onready var percent_label: Label = %Percent
@onready var back_button: Button = %Back

var started := false
var failed := false
var _held_resources: Array[Resource] = []
var _load_order: Array[String] = []
var _visited: Dictionary = {}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	back_button.pressed.connect(func(): GameManager.cancel_kitchen_loading(self))

func start_loading() -> void:
	if started: return
	started = true
	# Two frames ensure the visible screen is presented before any blocking work.
	await _present()
	if not ResourceLoader.exists(target_scene, "PackedScene"):
		show_error("The kitchen could not be found. Please return to the menu.")
		return
	var packed: PackedScene
	if force_incremental_loading or (OS.has_feature("web") and not OS.has_feature("threads")):
		packed = await _load_incrementally()
	else:
		packed = await _load_in_background()
	if packed == null:
		if not failed: show_error("The kitchen could not be loaded. Please return to the menu and try again.")
		return
	_set_progress(1.0)
	status_label.text = "Opening the kitchen..."
	await _present()
	load_completed.emit(packed)
	GameManager.complete_kitchen_load(self, packed)

func _present() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _load_in_background() -> PackedScene:
	var error := ResourceLoader.load_threaded_request(target_scene, "PackedScene", false)
	if error != OK:
		show_error("Could not start loading. Please return to the menu and try again.")
		return null
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(target_scene, progress)
		if not progress.is_empty(): _set_progress(float(progress[0]))
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				return ResourceLoader.load_threaded_get(target_scene) as PackedScene
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				return null
		await get_tree().process_frame
	return null

func _load_incrementally() -> PackedScene:
	status_label.text = "Preparing the kitchen..."
	await _collect_dependencies(target_scene)
	if failed: return null
	status_label.text = "Loading the kitchen..."
	# Leaf resources first; keep strong references so the cache survives between frames.
	# A single large resource and PackedScene instantiation can still take a long frame.
	var loaded: Resource
	for index in _load_order.size():
		loaded = ResourceLoader.load(_load_order[index])
		if loaded == null:
			show_error("A kitchen resource could not be loaded. Please return to the menu.")
			return null
		_held_resources.append(loaded)
		_set_progress(float(index + 1) / float(_load_order.size()))
		await _present()
	return loaded as PackedScene

func _collect_dependencies(path: String) -> void:
	if _visited.has(path) or failed: return
	_visited[path] = true
	if not ResourceLoader.exists(path):
		show_error("A kitchen resource is missing. Please return to the menu.")
		push_error("Loading screen: missing resource " + path)
		return
	# Cached resources already retain their own dependencies.
	if not ResourceLoader.has_cached(path):
		for dependency in ResourceLoader.get_dependencies(path):
			var dependency_path: String = dependency.get_slice("::", 2) if dependency.contains("::") else dependency
			var uid_text: String = dependency.get_slice("::", 0)
			if uid_text.begins_with("uid://"):
				var uid := ResourceUID.text_to_id(uid_text)
				if ResourceUID.has_id(uid): dependency_path = ResourceUID.get_id_path(uid)
			await _collect_dependencies(dependency_path)
	_load_order.append(path)
	# Yield while discovering the graph too, without parsing .tscn text (works in exports).
	if _visited.size() % 16 == 0: await _present()

func _set_progress(ratio: float) -> void:
	progress_bar.value = maxf(progress_bar.value, clampf(ratio, 0.0, 1.0) * 100.0)
	percent_label.text = "%d%%" % int(progress_bar.value)

func show_error(message: String) -> void:
	failed = true
	status_label.text = message
	percent_label.text = "Loading failed"
	back_button.show()
	back_button.grab_focus()
