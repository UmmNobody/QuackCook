extends Control

const SummaryReveal = preload("res://scripts/ui/summary_reveal.gd")
var _reveal := SummaryReveal.new()

func _ready() -> void:
	add_child(_reveal)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var summary: Dictionary = GameManager.last_summary
	%FinalDay.text = str(summary.get("day", GameManager.current_day))
	%Served.text = str(summary.get("served", 0))
	%Required.text = str(summary.get("required", 0))
	%Retry.pressed.connect(GameManager.restart_run)
	%Quit.pressed.connect(GameManager.return_to_menu)
	_reveal.play($Center/Panel/Margin/Content, %Retry)
