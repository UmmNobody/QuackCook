extends Node
## Preferences are session-only, just like the game's checkpoint.
signal changed

const FREE_MOUSE_CURSOR = preload("res://assets/textures/ui/cursor_freemouse.png")
const CLICK_CURSOR = preload("res://assets/textures/ui/cursor_click.png")
const CURSOR_HOTSPOT = Vector2(12, 4)
var _cursor_pressed := false
var mouse_sensitivity: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0

func _ready() -> void:
	_set_cursor_pressed(false)
	_apply_volume("SFX", sfx_volume)
	_apply_volume("Music", music_volume)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		_set_cursor_pressed(event.pressed)

func _process(_delta: float) -> void:
	# Also recover if the button was released outside the window or in another scene.
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if pressed != _cursor_pressed:
			_set_cursor_pressed(pressed)

func _set_cursor_pressed(pressed: bool) -> void:
	_cursor_pressed = pressed
	var image: Texture2D = CLICK_CURSOR if pressed else FREE_MOUSE_CURSOR
	# Buttons use the pointing-hand shape; update both shapes together.
	Input.set_custom_mouse_cursor(image, Input.CURSOR_ARROW, CURSOR_HOTSPOT)
	Input.set_custom_mouse_cursor(image, Input.CURSOR_POINTING_HAND, CURSOR_HOTSPOT)

func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, 0.2, 3.0)
	changed.emit()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volume("SFX", sfx_volume)
	changed.emit()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume("Music", music_volume)
	changed.emit()

func _apply_volume(bus: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0: return
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
