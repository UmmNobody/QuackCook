extends Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var summary: Dictionary = GameManager.last_summary
	%FinalDay.text = str(summary.get("day", GameManager.current_day))
	%Served.text = str(summary.get("served", 0))
	%Required.text = str(summary.get("required", 0))
	%Retry.pressed.connect(GameManager.restart_run)
	%Quit.pressed.connect(GameManager.return_to_menu)
	%Retry.grab_focus()
