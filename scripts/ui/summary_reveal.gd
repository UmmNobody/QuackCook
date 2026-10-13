extends Node
## Shared staggered pop-in for summary headings, score rows and actions.
const ITEM_DELAY := 0.18
const POP_DURATION := 0.34
var _tween: Tween
var _items: Array[Control] = []
var _buttons: Dictionary = {}

func play(content: Control, initial_focus: Control) -> void:
	stop()
	for child in content.get_children():
		if child is Control and not child is Separator:
			_items.append(child)
			child.modulate.a = 0.0
			if child is BaseButton:
				_buttons[child] = child.disabled
				child.disabled = true
				child.release_focus()
	# Always process: the daily report is displayed while gameplay is paused.
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	for index in _items.size():
		var item := _items[index]
		var delay := 0.1 + index * ITEM_DELAY
		# Delay until containers have laid out the new text before centering the pop.
		_tween.tween_callback(_prepare_pop.bind(item)).set_delay(delay)
		_tween.tween_property(item, "modulate:a", 1.0, 0.12).set_delay(delay)
		_tween.tween_property(item, "scale", Vector2.ONE, POP_DURATION).from(Vector2.ONE * 0.72).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	_tween.chain().tween_callback(_finish.bind(initial_focus))

func _prepare_pop(item: Control) -> void:
	item.pivot_offset = item.size * 0.5
	item.scale = Vector2.ONE * 0.72

func _finish(initial_focus: Control) -> void:
	for button in _buttons:
		if is_instance_valid(button): button.disabled = _buttons[button]
	if is_instance_valid(initial_focus) and initial_focus.is_visible_in_tree():
		initial_focus.grab_focus()

func stop() -> void:
	if _tween:
		_tween.kill()
		_tween = null
	for item in _items:
		if is_instance_valid(item):
			item.modulate.a = 1.0
			item.scale = Vector2.ONE
	for button in _buttons:
		if is_instance_valid(button): button.disabled = _buttons[button]
	_items.clear()
	_buttons.clear()
