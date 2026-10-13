extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(n: int) -> void:
	for i in n: await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/yaima/Documents/test-codex-connect/.quackcook-game-hud/" + name + ".png")
func run() -> void:
	var game = root.get_node("GameManager")
	game.tutorial_seen = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(5)
	game.set_process(false)
	var hud = current_scene.get_node("UI/ServiceHUD")
	game.preparation_remaining = 30.0
	hud._last_tick = ""
	hud._process(0)
	check(hud.get_node("%Seconds").text == "30" and hud.countdown.visible, "Preparation shows 30")
	check(hud.countdown.scale.x > 1 and hud.countdown.modulate.a == 1, "New tick starts large and opaque")
	await capture("countdown")
	await frames(35)
	check(hud.countdown.scale.x < 1 and hud.countdown.modulate.a < 0.6, "Number shrinks and fades")
	game.preparation_remaining = 29
	hud._process(0)
	check(hud.get_node("%Seconds").text == "29" and hud.countdown.scale.x > 1, "Next second restarts pulse")
	paused = true
	hud._process(0)
	check(not hud.countdown.visible, "Paused menu hides countdown")
	paused = false
	game.state = game.State.SERVING
	game.served_count = 3
	hud._process(0)
	check(hud.progress.max_value == 6 and hud.progress.value == 3, "Bar maximum is arrivals, fill is successful service")
	check(hud._fill.bg_color == hud.below_target_color, "Below target is red")
	check(absf((hud.marker.position.x + hud.marker.size.x * 0.5) / hud.progress.size.x - 4.0 / 6.0) < 0.01, "Target tick sits at quota ratio")
	check(hud.get_node("%Day").text == "DAY 1", "Day is visible")
	check(not hud.countdown.visible, "Normal service has no countdown")
	var player = current_scene.get_node("Actors/Player")
	player.take_damage(35)
	check(player.health_bar.value == 65, "Styled health bar still follows damage")
	await capture("red_progress")
	game.served_count = 4
	hud._process(0)
	check(hud._fill.bg_color == hud.target_met_color and hud.progress.value == 4, "Meeting target changes green without filling to maximum")
	await capture("green_progress")
	game.config.prisoner_count = 10
	game.config.required_successes = 8
	game.current_day = 3
	hud._process(0)
	check(hud.progress.max_value == 10 and hud._fill.bg_color == hud.below_target_color and hud.get_node("%Day").text == "DAY 3", "New day updates maximum, quota, day, and color")
	game.spawned_count = 10
	game.auto_close_remaining = 10
	hud._process(0)
	check(hud.countdown.visible and hud.get_node("%Seconds").text == "10" and hud.get_node("%CountdownCaption").text.contains("CLOSES"), "Auto-close uses same countdown style")
	game.state = game.State.SUMMARY
	hud._process(0)
	check(not hud.countdown.visible, "Closing service cancels countdown")
	print("HUD checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
