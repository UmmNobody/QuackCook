extends Control

func _ready() -> void:
	AudioManager.play_menu_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var settings := get_node_or_null("SettingsPanel")
	if settings != null:
		settings.back_requested.connect(_back)
		settings.focus_first()
	else:
		%Back.pressed.connect(_back)
		%Back.grab_focus()

func _back() -> void:
	GameManager.open_menu_page("main_menu")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit") and not event.is_echo():
		_back()
		get_viewport().set_input_as_handled()
