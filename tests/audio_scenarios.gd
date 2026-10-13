extends SceneTree
var checks := 0
var failures := 0
var audio: Node
var heard: Array[String] = []
var pitches: Array[float] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(n: int) -> void:
	for i in n: await process_frame
func run() -> void:
	audio = root.get_node("AudioManager")
	audio.cue_played.connect(func(key: String, voice: Node):
		heard.append(key)
		pitches.append(voice.pitch_scale))
	for key in audio.SOUNDS:
		check(audio.SOUNDS[key].get_length() > 0, "Imported playable sound " + key)
	audio.play_menu_music()
	check(audio.music.playing and audio.music.stream.loop and audio.music.bus == &"Music", "Menu music loops on Music bus")
	var same_stream = audio.music.stream
	audio.play_menu_music()
	check(audio.music.stream == same_stream, "Menu music resource is reused")
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var button := Button.new()
	stage.add_child(button)
	button.mouse_entered.emit()
	check(heard.back() == "ui_hover", "Any dynamically added button has hover audio")
	var count := heard.size()
	button.disabled = true
	button.mouse_entered.emit()
	check(heard.size() == count, "Disabled buttons do not sound")
	var settings = load("res://scenes/ui/settings_panel.tscn").instantiate()
	stage.add_child(settings)
	heard.clear()
	settings.get_node("%SFX").value = 0.6
	check(heard.is_empty(), "Moving SFX slider does not spam preview")
	settings.get_node("%SFX").drag_ended.emit(true)
	check(heard == ["quack1"], "Slider release previews once")
	root.get_node("AppSettings").set_sfx_volume(0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "All cues honor SFX mute")
	root.get_node("AppSettings").set_sfx_volume(1)
	settings.queue_free()
	# Cutscene metadata, delayed pair, cancellation and owned voices.
	var comic = load("res://scenes/cutscenes/intro_cutscene.tscn").instantiate()
	stage.add_child(comic)
	check(not audio.music.playing, "Entering cutscene stops menu music")
	var expected := ["noti", "door1", "gun", "handcuff", "judge", "quack_angry", "shirt", "shirt"]
	for i in expected.size():
		check(comic._panels[i].get_meta("sound") == expected[i], "Intro panel %d cue" % (i + 1))
	heard.clear()
	comic._reveal(4)
	check(heard == ["judge"], "Judge starts first")
	await frames(60)
	check(not heard.has("quack_double"), "Second cue waits at least one second")
	await frames(40)
	check(heard.count("quack_double") == 1, "Second cue plays once after 1.5 seconds")
	comic._reveal(4)
	heard.clear()
	comic._reveal(5)
	await frames(100)
	check(not heard.has("quack_double"), "Advancing cancels delayed cue from old panel")
	comic._reveal(4)
	heard.clear()
	comic.finish()
	await frames(100)
	check(heard.is_empty() and comic._panel_voices.is_empty(), "Skip cancels voices and pending cue")
	comic.queue_free()
	await frames(2)
	comic = load("res://scenes/cutscenes/game_over_cutscene.tscn").instantiate()
	stage.add_child(comic)
	expected = ["door1", "quack1", "handcuff", "", "electricity", "dink"]
	for i in expected.size():
		check(comic._panels[i].get_meta("sound") == expected[i], "Game Over panel %d cue" % (i + 1))
	heard.clear()
	comic._reveal(3)
	check(heard.is_empty(), "Game Over panel 4 stays silent")
	comic.queue_free()
	await frames(2)
	var final_report = load("res://scenes/ui/run_summary.tscn").instantiate()
	heard.clear()
	stage.add_child(final_report)
	check(heard.count("gameover") == 1, "Final report plays gameover once")
	final_report.queue_free()
	await frames(2)
	var daily = load("res://scenes/ui/day_summary.tscn").instantiate()
	heard.clear()
	stage.add_child(daily)
	check(not heard.has("gameover"), "Daily report never plays gameover")
	daily.queue_free()
	var stove = load("res://scenes/props/stations/stove.tscn").instantiate()
	stage.add_child(stove)
	stove.set_physics_process(false)
	var pan = load("res://scenes/items/cookware/pan.tscn").instantiate()
	stage.add_child(pan)
	pan.freeze = true
	var food = load("res://scenes/items/foods/chicken.tscn").instantiate()
	stage.add_child(food)
	food.freeze = true
	food.cut()
	stove.place_cookware(pan)
	pan.add_food(food)
	stove._setup_cooking_ui()
	check(stove._cooking_sound == "frying" and stove.cooking_audio.playing, "Frying begins on pan with food")
	check(stove.cooking_audio.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stove.cooking_audio.stream.loop_end > 0, "Cooking loop covers whole sample")
	food.apply_heat(food.cook_duration * 2 + food.burn_grace_seconds + 0.1)
	stove._setup_cooking_ui()
	check(stove._cooking_sound == "burning" and stove.cooking_audio.stream == audio.loop_stream("burning"), "Burning replaces frying on same voice")
	check(stove.find_children("*", "AudioStreamPlayer3D", true, false).size() == 1, "Only one loop voice per stove")
	pan.remove_from_stove()
	stove._setup_cooking_ui()
	check(not stove.cooking_audio.playing, "Removing pan stops loop")
	var player = load("res://scenes/characters/player/player.tscn").instantiate()
	player.position = Vector3(10, 2, 0)
	stage.add_child(player)
	player.set_physics_process(false)
	heard.clear()
	player.take_damage(1)
	check(heard.size() == 1 and heard[0] in ["quack1", "quack2"], "Accepted player hit quacks")
	player.take_damage(1)
	check(heard.size() == 1, "Invulnerable hit is silent")
	player.dash_ground_only = false
	player.try_dash(Vector3.FORWARD)
	check(heard.back() == "dash", "Accepted dash plays sound")
	var actor = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	actor.position = Vector3(-10, 2, 0)
	stage.add_child(actor)
	actor.set_physics_process(false)
	heard.clear()
	actor.take_damage(1)
	check(heard.size() == 1 and heard[0] in ["quack1", "quack2"], "Prisoner hit quacks")
	actor.queue_free()
	actor = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	stage.add_child(actor)
	actor.set_physics_process(false)
	actor.give_serving_tray()
	heard.clear()
	actor.begin_anger([] as Array[Vector3], player, "Patience exhausted")
	check(not heard.has("quack_angry"), "Angry quack waits for actual tray throw")
	actor._throw_serving_tray()
	check(heard.count("quack_angry") == 1, "Tray throw quacks exactly once")
	actor._throw_serving_tray()
	check(heard.count("quack_angry") == 1, "No second quack without a tray")
	# HUD emits one varied tick per displayed second, not once per frame.
	var game = root.get_node("GameManager")
	game.set_process(false)
	game.config = load("res://scripts/resources/service_wave_config.gd").new()
	game.state = game.State.PREPARING
	game.preparation_remaining = 30
	var hud = load("res://scenes/ui/service_hud.tscn").instantiate()
	stage.add_child(hud)
	heard.clear()
	pitches.clear()
	for seconds in range(29, 19, -1):
		game.preparation_remaining = seconds
		hud._process(0)
		hud._process(0)
	check(heard.count("clock-ticking") == 10, "Exactly one clock tick per second")
	check(pitches.max() > pitches.min() and pitches.min() >= 0.94 and pitches.max() <= 1.06, "Clock pitch varies within subtle bounds")
	game.config = null
	game.state = game.State.IDLE
	hud.queue_free()
	var table = load("res://scenes/props/stations/serving_table.tscn").instantiate()
	stage.add_child(table)
	var well = table.get_node("ChickenWell")
	var cooked = load("res://scenes/items/foods/chicken.tscn").instantiate()
	stage.add_child(cooked)
	cooked.freeze = true
	cooked.cut()
	cooked.apply_heat(cooked.cook_duration)
	pan.current_food = cooked
	heard.clear()
	well.interact_with(pan, player.head)
	check(heard == ["put_item"] and well.current_servings > 0, "Accepted refill plays put_item")
	well.interact_with(pan, player.head)
	check(heard.size() == 1, "Rejected refill is silent")
	player.head.pick_up(pan)
	heard.clear()
	player.head.throw_object(5.0)
	check(heard == ["throw_item"], "Throwing an actual held prop sounds once")
	stage.queue_free()
	await frames(3)
	# A real kitchen exercises accepted lever actions and shutter state changes.
	var room = load("res://scenes/main.tscn").instantiate()
	room.get_node("Queue/QueueLayout").auto_start_run = false
	root.add_child(room)
	current_scene = room
	await frames(3)
	var config = load("res://scripts/resources/service_wave_config.gd").new()
	config.prisoner_count = 1
	config.required_successes = 0
	config.preparation_seconds = 30
	game.start_service(config)
	var lever = room.get_node("Kitchen/Interactables/CloseKitchenButton")
	heard.clear()
	lever.interact_with(null, null)
	check(heard.count("lever1") == 1 and heard.count("slidingdoor") == 1, "Opening lever and moving shutter each sound once")
	lever.interact_with(null, null)
	check(heard.count("lever2") == 0, "Blocked close has no lever sound")
	game.spawner.spawning_paused = true
	var last = game.spawner.spawn_one()
	last.take_damage(10000)
	await frames(3)
	heard.clear()
	lever.interact_with(null, null)
	check(heard.count("lever2") == 1 and heard.count("slidingdoor") == 1, "Closing lever and shutter each sound once")
	room.queue_free()
	await frames(3)
	print("Audio checks: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)
