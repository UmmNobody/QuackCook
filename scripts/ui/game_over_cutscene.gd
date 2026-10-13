extends "res://scripts/ui/comic_cutscene.gd"

func _ready() -> void:
	finished.connect(func(): GameManager.show_run_summary(self))
	super._ready()
