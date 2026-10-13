extends SceneTree

var game: Node
var wipe: Node
var settings: Node
var reports_opened := 0
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func settle(scene_name: String = "") -> void:
	for i in 600:
		await process_frame
		if not wipe.busy and not game._transition_pending and (scene_name.is_empty() or (current_scene != null and current_scene.name == scene_name)): return
	check(false, "Timed out waiting for " + scene_name)

func capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty(): return
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join(name + ".png"))

func run() -> void:
	game = root.get_node("GameManager")
	game.summary_opened.connect(func(_report): reports_opened += 1)
	wipe = root.get_node("SceneTransition")
	settings = root.get_node("AppSettings")
	wipe.duration = 0.04
	game.summary_delay_seconds = 0.02
	game.tutorial_seen = true
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await settle("MainMenu")
	check(current_scene.get_node("Home/BestDay").text.ends_with("00"), "Best starts at zero")
	if DisplayServer.get_name() != "headless":
		wipe.curtain.show()
		wipe.curtain.material.set_shader_parameter("factor", 0.5)
		await capture("transition")
		wipe.curtain.hide()
	current_scene.get_node("Home/Setting").pressed.emit()
	await settle("SettingsPage")
	var panel = current_scene.get_node("SettingsPanel")
	panel.get_node("%Mouse").value = 1.75
	panel.get_node("%SFX").value = 0.0
	panel.get_node("%Music").value = 0.4
	check(is_equal_approx(settings.mouse_sensitivity, 1.75), "Mouse slider applies multiplier")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "Zero SFX mutes only SFX")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Music remains audible")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.4), "Music slider applies bus gain")
	check(panel.get_node("%MouseValue").text == "1.75x" and panel.get_node("%MusicValue").text == "40%", "Slider values display correctly")
	panel.get_node("%SFX").value = 0.65
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "Raising SFX unmutes bus")
	await capture("settings")
	panel.get_node("%Back").pressed.emit()
	await settle("MainMenu")
	current_scene.get_node("Home/Credit").pressed.emit()
	await settle("Credits")
	check(current_scene.find_child("ContentPlaceholder", true, false) != null, "Credits has editable empty content")
	current_scene.get_node("%Back").pressed.emit()
	await settle("MainMenu")
	check(game.launch_from_menu(false), "New game accepted")
	await settle("IntroCutscene")
	current_scene.skip_button.pressed.emit()
	await settle("Main")
	check(game.current_day == 1 and game.run_totals.day == 1 and game.best_day == 1, "New game begins day 1 and tracks best")
	var player = current_scene.get_node("Actors/Player")
	var head = player.get_node("Head")
	var yaw: float = head.rotation.y
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	player._unhandled_input(motion)
	check(is_equal_approx(head.rotation.y - yaw, -10 * 0.005 * 1.75), "Gameplay uses chosen mouse sensitivity")
	game.toggle_pause_menu()
	var pause = current_scene.get_node("UI/PauseMenu")
	check(paused and pause.screen.visible, "Pause opens styled modal")
	await capture("pause")
	pause.get_node("%Settings").pressed.emit()
	check(paused and pause.get_node("%SettingsPanel").visible and not pause.get_node("%Home").visible, "Settings opens without unpausing")
	check(is_equal_approx(pause.get_node("%SettingsPanel").get_node("%Mouse").value, 1.75), "Pause settings shares menu values")
	pause.get_node("%SettingsPanel").get_node("%Back").pressed.emit()
	check(paused and pause.get_node("%Home").visible, "Settings back returns to paused menu")
	# The same shader must complete even while the gameplay tree is paused.
	check(await wipe.cover(), "Cover works while paused")
	check(wipe.busy and wipe.curtain.visible and wipe.curtain.material.get_shader_parameter("factor") == 1.0, "Covered endpoint is fully opaque")
	check(not await wipe.cover(), "Duplicate transition rejected")
	await wipe.reveal()
	check(paused and not wipe.busy and not wipe.curtain.visible, "Reveal does not release another system's pause")
	pause.get_node("%Resume").pressed.emit()
	check(not paused and player.can_control(), "Resume restores controls")
	player.invulnerability_remaining = 0.0
	player.take_damage(10000)
	check(game.run_totals.unconscious == 1, "Real player knockout updates total")
	# A small real service exercises serving, damage, and daily-report transitions.
	game.config.prisoner_count = 2
	game.config.required_successes = 1
	game.open_kitchen()
	var spawner = game.spawner
	spawner.spawning_paused = true
	var queue = root.get_node("QueueManager")
	var order: Array[int] = [FoodItem.Type.WATER]
	var actor = spawner.spawn_one(order)
	actor.service_completed.emit()
	actor.service_completed.emit()
	check(game.run_totals.served == 1 and game.served_count == 1, "Successful prisoner counts once")
	actor.take_damage(10000, player)
	check(game.run_totals.subdued == 1, "Real prisoner knockout counts once")
	game._record_subdued(actor.get_instance_id(), game._run_serial)
	check(game.run_totals.subdued == 1, "Duplicate knockout cannot increase count")
	for i in 3: await physics_frame
	var second = spawner.spawn_one(order)
	second.take_damage(10000, player)
	for i in 3: await physics_frame
	check(game.can_close_kitchen(), "Resolved service can close")
	var room_id: int = current_scene.get_instance_id()
	game.finish_service()
	for i in 600:
		if not game.summary_pending: break
		await process_frame
	check(paused and current_scene.get_node("UI/DaySummary").screen.visible and not wipe.busy, "Daily report transition completes while paused")
	check(game.last_summary.target_met and reports_opened == 1, "Successful day opens one daily report")
	game.confirm_summary()
	await settle("Main")
	check(game.current_day == 2 and current_scene.get_instance_id() == room_id and not paused, "Next day transitions without rebuilding kitchen")
	check(game.run_totals.served == 1 and game.run_totals.subdued == 2 and game.run_totals.unconscious == 1, "Totals persist across days")
	check(game.best_day == 2, "Best day increases")
	game.toggle_pause_menu()
	current_scene.get_node("UI/PauseMenu").exit_button.pressed.emit()
	await settle("MainMenu")
	check(game.checkpoint_day == 2 and not paused, "Save and menu preserves day and clears pause")
	check(current_scene.get_node("Home/BestDay").text.ends_with("02"), "Best day shown in menu")
	check(game.launch_from_menu(true), "Continue checkpoint accepted")
	await settle("Main")
	check(game.current_day == 2 and game.run_totals.served == 1 and game.run_totals.subdued == 2 and game.run_totals.unconscious == 1, "Continue restores run totals and day")
	check(current_scene.get_instance_id() != room_id, "Continue uses a fresh kitchen")
	# Resolve a failed service, then use the comic's actual Skip entry point.
	game.config.prisoner_count = 1
	game.config.required_successes = 1
	game.open_kitchen()
	spawner = game.spawner
	spawner.spawning_paused = true
	actor = spawner.spawn_one(order)
	actor.take_damage(10000)
	for i in 3: await physics_frame
	game.finish_service()
	for i in 600:
		if not game.summary_pending: break
		await process_frame
	check(not game.last_summary.target_met, "Failed daily quota recorded")
	await settle("GameOverCutscene")
	check(reports_opened == 1, "Failed day skips daily report without any confirmation")
	check(not paused and game.state == game.State.GAME_OVER, "Failure loads comic and unpauses")
	current_scene.skip_button.pressed.emit()
	await settle("RunSummary")
	check(current_scene.get_node("%Day").text == "2" and current_scene.get_node("%Served").text == "1" and current_scene.get_node("%Subdued").text == "3" and current_scene.get_node("%Unconscious").text == "1", "Final report shows actual accumulated totals")
	await capture("run_summary")
	current_scene.get_node("%Retry").pressed.emit()
	await settle("Main")
	check(game.current_day == 1 and game.run_totals.served == 0 and game.run_totals.subdued == 0 and game.run_totals.unconscious == 0, "Retry resets run totals")
	check(game.best_day == 2, "Retry keeps session best")
	game.return_to_menu()
	await settle("MainMenu")
	check(is_equal_approx(settings.mouse_sensitivity, 1.75), "Settings survive all scene changes")
	# Audio routing and lifecycle foundation, without requiring any sound assets.
	var audio = root.get_node("AudioManager")
	check(audio.music.bus == &"Music", "Persistent music routed to Music bus")
	var tone := AudioStreamWAV.new()
	tone.mix_rate = 44100
	tone.data = PackedByteArray()
	tone.data.resize(4410)
	audio.play_sfx(tone)
	check(audio.get_child_count() == 2 and audio.get_child(1).bus == &"SFX", "One-shot routed to SFX bus")
	audio.play_music(tone)
	check(audio.music.stream == tone, "Music accepts prepared stream")
	audio.stop_music()
	check(not audio.music.playing, "Music can stop")
	# Audio playback uses real time even with --fixed-fps; do not race its thread.
	var deadline := Time.get_ticks_msec() + 1000
	while audio.get_child_count() > 1 and Time.get_ticks_msec() < deadline:
		await process_frame
	check(audio.get_child_count() == 1, "Finished one-shot cleans itself up")
	print("Settings / summary / transition checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
