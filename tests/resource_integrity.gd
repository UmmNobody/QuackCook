extends SceneTree
## Load every production scene/resource/script after moving files or fresh import.
var checked := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func scan(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		if file.get_extension() not in ["tscn", "tres", "gd", "gdshader"]: continue
		var full := path.path_join(file)
		checked += 1
		var resource := load(full)
		if resource == null or (resource is Script and not resource.can_instantiate()):
			failures += 1
			printerr("FAIL: Resource load " + full)
	for folder in DirAccess.get_directories_at(path):
		if folder.begins_with(".") or folder in ["docs", "tests"]: continue
		scan(path.path_join(folder))
func run() -> void:
	scan("res://")
	print("Resource integrity: %d checked, %d failed" % [checked, failures])
	quit(1 if failures else 0)
