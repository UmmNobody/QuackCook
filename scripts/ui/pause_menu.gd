extends CanvasLayer
@onready var screen: Control = %Screen
@onready var checkpoint_label: Label = %Checkpoint
@onready var exit_button: Button = %Exit

func _ready() -> void:
	screen.hide()
	exit_button.pressed.connect(GameManager.return_to_menu)
	%Resume.pressed.connect(GameManager.toggle_pause_menu)
	%Settings.pressed.connect(_open_settings)
	%SettingsPanel.back_requested.connect(_close_settings)
	GameManager.pause_menu_changed.connect(_on_pause_changed)

func _input(event: InputEvent) -> void:
	if SceneTransition.busy: return
	if event.is_action_pressed("quit") and not event.is_echo():
		if screen.visible and %SettingsPanel.visible:
			_close_settings()
		else:
			GameManager.toggle_pause_menu()
		get_viewport().set_input_as_handled()

func _open_settings() -> void:
	%Home.hide()
	%SettingsPanel.show()
	%SettingsPanel.focus_first()

func _close_settings() -> void:
	%SettingsPanel.hide()
	%Home.show()
	%Settings.grab_focus()

func _on_pause_changed(open: bool) -> void:
	if not is_inside_tree(): return
	screen.visible = open
	%SettingsPanel.hide()
	%Home.show()
	if open:
		checkpoint_label.text = "DAY %d / SESSION CHECKPOINT\nContinue with a fresh kitchen." % GameManager.checkpoint_day if GameManager.has_checkpoint() else "This run has ended."
		%Resume.grab_focus()
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus != null and screen.is_ancestor_of(focus): focus.release_focus()
		if GameManager.state == GameManager.State.SUMMARY:
			var report := get_parent().get_node_or_null("DaySummary")
			if report != null: report.continue_button.grab_focus()
