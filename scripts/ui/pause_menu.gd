extends CanvasLayer

@onready var screen: Control = %Screen
@onready var checkpoint_label: Label = %Checkpoint
@onready var exit_button: Button = %Exit

func _ready() -> void:
	screen.hide()
	exit_button.pressed.connect(GameManager.return_to_menu)
	GameManager.pause_menu_changed.connect(_on_pause_changed)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quit") and not event.is_echo():
		GameManager.toggle_pause_menu()
		get_viewport().set_input_as_handled()

func _on_pause_changed(open: bool) -> void:
	if not is_inside_tree(): return
	screen.visible = open
	if open:
		checkpoint_label.text = "Continue from day %d while the game stays open.\nThe kitchen will start fresh." % GameManager.checkpoint_day if GameManager.has_checkpoint() else "This run has ended. A new game starts on day 1."
		exit_button.grab_focus()
	else:
		exit_button.release_focus()
		if GameManager.state == GameManager.State.SUMMARY:
			var report := get_parent().get_node_or_null("DaySummary")
			if report != null: report.continue_button.grab_focus()
