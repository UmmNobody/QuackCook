extends Node
const SOUNDS := {
	"burning": preload("res://assets/audio/sfx/kitchen/burning.wav"),
	"frying": preload("res://assets/audio/sfx/kitchen/frying.wav"),
	"put_item": preload("res://assets/audio/sfx/kitchen/put_item.wav"),
	"lever1": preload("res://assets/audio/sfx/kitchen/lever1.wav"),
	"lever2": preload("res://assets/audio/sfx/kitchen/lever2.wav"),
	"dash": preload("res://assets/audio/sfx/player/dash.wav"),
	"throw_item": preload("res://assets/audio/sfx/player/throw_item.wav"),
	"door_slam": preload("res://assets/audio/sfx/doors/door_slam.wav"),
	"slidingdoor": preload("res://assets/audio/sfx/doors/slidingdoor.wav"),
	"clock-ticking": preload("res://assets/audio/sfx/ui/clock-ticking.wav"),
	"ui_hover": preload("res://assets/audio/sfx/ui/ui_hover.wav"),
	"gameover": preload("res://assets/audio/sfx/ui/gameover.ogg"),
	"quack1": preload("res://assets/audio/sfx/prisoners/quack1.wav"),
	"quack2": preload("res://assets/audio/sfx/prisoners/quack2.wav"),
	"quack_angry": preload("res://assets/audio/sfx/prisoners/quack_angry.wav"),
	"quack_double": preload("res://assets/audio/sfx/prisoners/quack_double.wav"),
	"noti": preload("res://assets/audio/sfx/cutscenes/noti.wav"),
	"door1": preload("res://assets/audio/sfx/cutscenes/door1.wav"),
	"gun": preload("res://assets/audio/sfx/cutscenes/gun.wav"),
	"handcuff": preload("res://assets/audio/sfx/cutscenes/handcuff.wav"),
	"judge": preload("res://assets/audio/sfx/cutscenes/judge.wav"),
	"shirt": preload("res://assets/audio/sfx/cutscenes/shirt.wav"),
	"electricity": preload("res://assets/audio/sfx/cutscenes/electricity.wav"),
	"dink": preload("res://assets/audio/sfx/cutscenes/dink.wav"),
	"main_menu": preload("res://assets/audio/music/main_menu.ogg"),
}

var _loop_streams: Dictionary = {}
var _menu_music: AudioStream
signal cue_played(key: String, voice: Node)
@onready var music: AudioStreamPlayer = $Music

func play_music(stream: AudioStream) -> void:
	if stream == null:
		music.stop()
		return
	if music.stream == stream and music.playing: return
	music.stream = stream
	music.play()

func stop_music() -> void:
	music.stop()

func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null: return
	var voice := AudioStreamPlayer.new()
	voice.bus = &"SFX"
	voice.stream = stream
	voice.volume_db = volume_db
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

func play_sfx_3d(stream: AudioStream, source: Node3D, volume_db: float = 0.0) -> void:
	if stream == null or not is_instance_valid(source): return
	var voice := AudioStreamPlayer3D.new()
	voice.bus = &"SFX"
	voice.stream = stream
	voice.volume_db = volume_db
	source.add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

func _ready() -> void:
	get_tree().node_added.connect(_watch_button)
	for button in get_tree().root.find_children("*", "BaseButton", true, false):
		_watch_button(button)

func _watch_button(node: Node) -> void:
	if node is BaseButton:
		var callback := _button_hover.bind(node)
		if not node.mouse_entered.is_connected(callback): node.mouse_entered.connect(callback)

func _button_hover(button: BaseButton) -> void:
	if not button.disabled and button.is_visible_in_tree() and not SceneTransition.busy:
		cue("ui_hover", button)

## Owned one-shots stop when their scene/source leaves the tree.
func cue(key: String, owner_node: Node = null, spatial: bool = false, pitch: float = 1.0, volume_db: float = 0.0) -> Node:
	if not SOUNDS.has(key): return null
	var owner := owner_node if is_instance_valid(owner_node) else self
	var voice: Node = AudioStreamPlayer3D.new() if spatial and owner is Node3D else AudioStreamPlayer.new()
	voice.name = "Sound_" + key.replace("-", "_")
	voice.stream = SOUNDS[key]
	voice.bus = &"SFX"
	voice.pitch_scale = pitch
	voice.volume_db = volume_db
	if voice is AudioStreamPlayer3D: voice.max_distance = 22.0
	owner.add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
	cue_played.emit(key, voice)
	return voice

func hurt(owner_node: Node, spatial: bool = true) -> void:
	cue("quack1" if randf() < 0.5 else "quack2", owner_node, spatial)

func loop_stream(key: String) -> AudioStream:
	if _loop_streams.has(key): return _loop_streams[key]
	var stream: AudioStream = SOUNDS[key].duplicate()
	if stream is AudioStreamWAV:
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	_loop_streams[key] = stream
	return stream

func play_menu_music() -> void:
	if _menu_music == null: _menu_music = loop_stream("main_menu")
	play_music(_menu_music)
