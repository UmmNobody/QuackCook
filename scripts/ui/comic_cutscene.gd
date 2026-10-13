extends Control
## Pages and ordered panel textures are authored in the scene, not built at runtime.
signal finished
@export var design_size := Vector2(1920, 1080)
@export_range(0.1, 2.0, 0.05) var slide_seconds: float = 0.45
@export_range(0.0, 400.0, 1.0) var slide_distance: float = 100.0
@export_range(0.5, 30.0, 0.1) var panel_hold_seconds: float = 3.0
@export var auto_play: bool = false
@onready var board: Control = %ComicBoard
@onready var pages: Control = %Pages
@onready var auto_button: Button = %AutoPlay
@onready var skip_button: Button = %Skip
var panel_index: int = -1
var _panels: Array[Control] = []
var _panel_pages: Array[Control] = []
var _rest_positions: Array[Vector2] = []
var _tween: Tween
var _animating := false
var _ended := false
var _hold_elapsed := 0.0
var _input_guard := 0.2
var _sound_generation := 0
var _panel_voices: Array[Node] = []

func _ready() -> void:
	AudioManager.stop_music()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for page in pages.get_children():
		if not page is Control: continue
		page.hide()
		for panel in page.get_children():
			if not panel is TextureRect: continue
			_panels.append(panel)
			_panel_pages.append(page)
			_rest_positions.append(panel.position)
			panel.hide()
	auto_button.toggled.connect(_set_auto_play)
	skip_button.pressed.connect(finish)
	resized.connect(_fit_board)
	_fit_board()
	_set_auto_play(auto_play)
	# Start the first entrance after the scene wipe, so it is not hidden by black.
	while SceneTransition.busy:
		await get_tree().process_frame
	if _panels.is_empty():
		finish.call_deferred()
	else:
		_reveal(0)

func _fit_board() -> void:
	var fit := minf(size.x / maxf(1.0, design_size.x), size.y / maxf(1.0, design_size.y))
	board.scale = Vector2.ONE * fit
	board.position = (size - design_size * fit) * 0.5

func _set_auto_play(enabled: bool) -> void:
	auto_play = enabled
	_hold_elapsed = 0.0
	auto_button.set_pressed_no_signal(enabled)
	auto_button.text = "AUTO PLAY: ON" if enabled else "AUTO PLAY: OFF"
	auto_button.modulate = Color(1, 1, 1, 1.0 if enabled else 0.35)

func _reveal(index: int) -> void:
	panel_index = index
	for page in pages.get_children():
		if page is Control: page.visible = page == _panel_pages[index]
	var panel := _panels[index]
	panel.position = _rest_positions[index] + Vector2(0, slide_distance)
	panel.modulate.a = 0.0
	panel.show()
	_play_panel_sound(panel)
	_animating = true
	_hold_elapsed = 0.0
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(panel, "position", _rest_positions[index], slide_seconds)
	_tween.tween_property(panel, "modulate:a", 1.0, slide_seconds)
	_tween.finished.connect(_settle_reveal)

func _settle_reveal() -> void:
	if _ended or panel_index < 0: return
	_panels[panel_index].position = _rest_positions[panel_index]
	_panels[panel_index].modulate.a = 1.0
	_animating = false
	_hold_elapsed = 0.0

func advance() -> void:
	if _ended: return
	# A click during the entrance reveals this panel fully, never skips unread art.
	if _animating:
		if _tween: _tween.kill()
		_settle_reveal()
	elif panel_index + 1 < _panels.size():
		_reveal(panel_index + 1)
	else:
		finish()

func _process(delta: float) -> void:
	if SceneTransition.busy: return
	_input_guard = maxf(0.0, _input_guard - delta)
	if _ended or _animating or not auto_play or panel_index < 0: return
	_hold_elapsed += delta
	var hold := maxf(0.5, float(_panels[panel_index].get_meta("hold_seconds", panel_hold_seconds)))
	if _hold_elapsed >= hold: advance()

func _unhandled_input(event: InputEvent) -> void:
	if _ended or _input_guard > 0.0: return
	var click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var key: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_RIGHT]
	if click or key:
		get_viewport().set_input_as_handled()
		advance()

func finish() -> void:
	if _ended: return
	_ended = true
	_stop_panel_sound()
	if _tween: _tween.kill()
	auto_button.disabled = true
	skip_button.disabled = true
	finished.emit()

func _exit_tree() -> void:
	if _tween: _tween.kill()

func _stop_panel_sound() -> void:
	_sound_generation += 1
	for voice in _panel_voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	_panel_voices.clear()

func _play_panel_sound(panel: Control) -> void:
	_stop_panel_sound()
	var key := str(panel.get_meta("sound", ""))
	if not key.is_empty():
		_panel_voices.append(AudioManager.cue(key, self))
	var second := str(panel.get_meta("second_sound", ""))
	if second.is_empty(): return
	var generation := _sound_generation
	await get_tree().create_timer(float(panel.get_meta("second_sound_delay", 1.5)), false).timeout
	if _ended or generation != _sound_generation or not is_inside_tree(): return
	_panel_voices.append(AudioManager.cue(second, self))
