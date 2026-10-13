extends CanvasLayer

@export var below_target_color := Color(0.86, 0.16, 0.20)
@export var target_met_color := Color(0.22, 0.75, 0.38)
@export_range(0.1, 1.0) var countdown_pulse_seconds: float = 0.85
@onready var progress: ProgressBar = %ServiceProgress
@onready var marker: ColorRect = %TargetMarker
@onready var countdown: Control = %Countdown
var _fill: StyleBoxFlat
var _last_tick := ""
var _pulse: Tween

func _ready() -> void:
	_fill = progress.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	progress.add_theme_stylebox_override("fill", _fill)
	progress.resized.connect(_update_marker)
	countdown.resized.connect(func(): countdown.pivot_offset = countdown.size * 0.5)
	countdown.pivot_offset = countdown.size * 0.5
	countdown.hide()
	_process(0.0)

func _process(_delta: float) -> void:
	var config: Resource = GameManager.config
	%Top.visible = config != null
	if config == null:
		_clear_countdown()
		return
	progress.max_value = maxi(1, config.prisoner_count)
	progress.value = GameManager.served_count
	_fill.bg_color = target_met_color if GameManager.served_count >= config.required_successes else below_target_color
	%ServedCount.text = "%d / %d" % [GameManager.served_count, config.prisoner_count]
	%Day.text = "DAY %d" % GameManager.current_day
	%Target.text = "TARGET %d" % config.required_successes
	_update_marker()
	# Modal screens and transitions should not show a ticking number behind them.
	if get_tree().paused or SceneTransition.busy:
		_clear_countdown()
		return
	var seconds := 0
	var mode := ""
	if GameManager.state == GameManager.State.PREPARING:
		seconds = ceili(GameManager.preparation_remaining)
		mode = "KITCHEN OPENS"
	elif GameManager.state == GameManager.State.SERVING and GameManager.can_close_kitchen():
		seconds = ceili(GameManager.auto_close_remaining if GameManager.auto_close_remaining >= 0.0 else GameManager.auto_close_seconds)
		mode = "KITCHEN CLOSES"
	if seconds <= 0 or mode.is_empty():
		_clear_countdown()
		return
	var tick := "%s:%d" % [mode, seconds]
	if tick == _last_tick: return
	_last_tick = tick
	%Seconds.text = str(seconds)
	%CountdownCaption.text = "SECONDS / " + mode
	if _pulse: _pulse.kill()
	countdown.show()
	countdown.scale = Vector2.ONE * 1.2
	countdown.modulate.a = 1.0
	_pulse = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_pulse.tween_property(countdown, "scale", Vector2.ONE * 0.65, countdown_pulse_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse.tween_property(countdown, "modulate:a", 0.0, countdown_pulse_seconds * 0.75).set_delay(countdown_pulse_seconds * 0.25)

func _update_marker() -> void:
	if GameManager.config == null: return
	var ratio := clampf(float(GameManager.config.required_successes) / maxf(1.0, progress.max_value), 0.0, 1.0)
	# Keep the entire white tick visible even when the target is 0 or the maximum.
	marker.position.x = clampf(progress.size.x * ratio - marker.size.x * 0.5, 0.0, maxf(0.0, progress.size.x - marker.size.x))

func _clear_countdown() -> void:
	_last_tick = ""
	if _pulse:
		_pulse.kill()
		_pulse = null
	countdown.hide()
