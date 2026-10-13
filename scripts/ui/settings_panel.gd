extends Control
signal back_requested
@export var show_menu_background := true

func _ready() -> void:
	$Background.visible = show_menu_background
	%Mouse.value_changed.connect(AppSettings.set_mouse_sensitivity)
	%SFX.value_changed.connect(AppSettings.set_sfx_volume)
	%Music.value_changed.connect(AppSettings.set_music_volume)
	%Back.pressed.connect(func(): back_requested.emit())
	AppSettings.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	%Mouse.set_value_no_signal(AppSettings.mouse_sensitivity)
	%SFX.set_value_no_signal(AppSettings.sfx_volume)
	%Music.set_value_no_signal(AppSettings.music_volume)
	%MouseValue.text = "%.2fx" % AppSettings.mouse_sensitivity
	%SFXValue.text = "%d%%" % roundi(AppSettings.sfx_volume * 100.0)
	%MusicValue.text = "%d%%" % roundi(AppSettings.music_volume * 100.0)

func focus_first() -> void:
	%Mouse.grab_focus()
