extends CanvasLayer

@export var below_target_color := Color(0.86, 0.16, 0.20)
@export var target_met_color := Color(0.22, 0.75, 0.38)
@onready var progress: ProgressBar = %ServiceProgress
@onready var marker: ColorRect = %TargetMarker
@onready var countdown: Control = %Countdown
var _fill: StyleBoxFlat
var _last_tick := ""
var _player_head: Node3D
@export_range(0.1, 2.0) var progress_animation_seconds := 0.55
var _progress_tween: Tween
var _progress_day := -1
var _progress_target := -1.0

func _ready() -> void:
	_fill = progress.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	progress.add_theme_stylebox_override("fill", _fill)
	progress.resized.connect(_update_marker)
	countdown.hide()
	progress.step = 0.0
	_process(0.0)

func _process(_delta: float) -> void:
	_update_cursor()
	var config: Resource = GameManager.config
	%Top.visible = config != null
	if config == null:
		_clear_countdown()
		if _progress_tween: _progress_tween.kill()
		_progress_day = -1
		return
	_update_service_progress(maxi(1, config.prisoner_count), GameManager.served_count)
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
	%CountdownCaption.tooltip_text = mode
	countdown.show()

func _update_marker() -> void:
	if GameManager.config == null: return
	var ratio := clampf(float(GameManager.config.required_successes) / maxf(1.0, progress.max_value), 0.0, 1.0)
	# Keep the entire white tick visible even when the target is 0 or the maximum.
	marker.position.x = clampf(progress.size.x * ratio - marker.size.x * 0.5, 0.0, maxf(0.0, progress.size.x - marker.size.x))

func _clear_countdown() -> void:
	_last_tick = ""
	countdown.hide()

func _update_cursor() -> void:
	%Crosshair.hide()
	%FocusCursor.hide()
	if get_tree().paused or SceneTransition.busy or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if not is_instance_valid(_player_head):
		var player := get_tree().get_first_node_in_group("Player")
		if player == null:
			return
		_player_head = player.get_node_or_null("Head")
	if not is_instance_valid(_player_head) or not _player_head.interaction_allowed():
		return
	%Crosshair.show()
	# A freed hover reference cannot be assigned to a typed Node variable.
	if not is_instance_valid(_player_head.last_hovered_object):
		return
	var target: Node = _player_head.last_hovered_object
	if not is_instance_valid(target) or target.is_queued_for_deletion() or target == _player_head.carried_object:
		return
	var can_pick_up := target.is_in_group("Pickable") and not is_instance_valid(_player_head.carried_object)
	if can_pick_up and target.has_method("can_pick_up"):
		can_pick_up = target.can_pick_up()
	var can_interact := target.is_in_group("Interactable") and (target.has_method("interact_with") or (not is_instance_valid(_player_head.carried_object) and target.has_method("_interact")))
	%FocusCursor.visible = can_pick_up or can_interact
	%Crosshair.visible = not %FocusCursor.visible

func _update_service_progress(maximum: int, served: int) -> void:
	var target := clampf(float(served), 0.0, float(maximum))
	# A new day starts cleanly, without animating backwards from yesterday's score.
	if _progress_day != GameManager.current_day or progress.max_value != maximum:
		if _progress_tween: _progress_tween.kill()
		_progress_day = GameManager.current_day
		progress.max_value = maximum
		progress.value = target
		_progress_target = target
		return
	if is_equal_approx(target, _progress_target):
		return
	_progress_target = target
	if _progress_tween: _progress_tween.kill()
	_progress_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_progress_tween.tween_property(progress, "value", target, progress_animation_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
