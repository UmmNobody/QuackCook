extends "res://scripts/ui/comic_cutscene.gd"

func _ready() -> void:
	finished.connect(GameManager.finish_intro_cutscene.bind(self))
	super._ready()
