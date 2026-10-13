extends Control

const SummaryReveal = preload("res://scripts/ui/summary_reveal.gd")
var _reveal := SummaryReveal.new()

func _ready() -> void:
	AudioManager.cue("gameover", self)
	add_child(_reveal)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var totals: Dictionary = GameManager.run_totals
	%Day.text = str(totals.get("day", 0))
	%Served.text = str(totals.get("served", 0))
	%Subdued.text = str(totals.get("subdued", 0))
	%Unconscious.text = str(totals.get("unconscious", 0))
	%Retry.pressed.connect(GameManager.restart_run)
	%MainMenu.pressed.connect(GameManager.return_to_menu)
	_reveal.play($Center/Panel/Margin/Content, %Retry)
