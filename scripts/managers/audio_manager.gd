extends Node
## Set imported music streams to loop in their import/resource settings.
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
