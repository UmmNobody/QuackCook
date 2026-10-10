extends Control
## Layout and styling live in main_menu.tscn and menu_theme.tres.
@onready var home: Control = %Home
@onready var confirmation: Control = %Confirmation
@onready var start_button: Button = %Start
@onready var continue_button: Button = %Continue
@onready var new_button: Button = %NewGame
@onready var cancel_button: Button = %Cancel
@onready var prompt: Label = %Prompt

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start_button.pressed.connect(_start_pressed)
	continue_button.pressed.connect(_launch.bind(true))
	new_button.pressed.connect(_launch.bind(false))
	cancel_button.pressed.connect(_cancel)
	start_button.grab_focus()

func _start_pressed() -> void:
	if GameManager.has_checkpoint():
		home.hide()
		prompt.text = "Continue day %d?" % GameManager.checkpoint_day
		continue_button.text = "Continue day %d" % GameManager.checkpoint_day
		confirmation.show()
		continue_button.grab_focus()
	else:
		_launch(false)

func _launch(resume_previous: bool) -> void:
	GameManager.launch_from_menu(resume_previous)

func _cancel() -> void:
	confirmation.hide()
	home.show()
	start_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit") and confirmation.visible:
		_cancel()
		get_viewport().set_input_as_handled()
