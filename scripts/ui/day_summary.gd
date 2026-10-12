extends CanvasLayer

@export var success_color: Color = Color("f0f0f0")
@export var failure_color: Color = Color("ff5050")
@onready var screen: Control = %Summary
@onready var day_label: Label = %Day
@onready var title_label: Label = %Title
@onready var served_label: Label = %Served
@onready var missed_label: Label = %Missed
@onready var target_label: Label = %Target
@onready var result_label: Label = %Result
@onready var continue_button: Button = %Continue

func _ready() -> void:
	screen.hide()
	continue_button.pressed.connect(GameManager.confirm_summary)
	GameManager.summary_opened.connect(_show_summary)
	GameManager.day_started.connect(_on_day_started)

func _show_summary(summary: Dictionary) -> void:
	day_label.text = "DAY %02d  /  DAILY REPORT" % summary.day
	served_label.text = str(summary.served)
	missed_label.text = str(summary.not_served)
	target_label.text = "%d / %d" % [summary.served, summary.required]
	result_label.text = "Target reached" if summary.target_met else "Target not reached"
	result_label.add_theme_color_override("font_color", success_color if summary.target_met else failure_color)
	continue_button.text = "Start day %d" % (summary.day + 1) if summary.target_met else "Continue to Game Over"
	screen.show()
	continue_button.grab_focus()

func _on_day_started(_day: int) -> void:
	screen.hide()
