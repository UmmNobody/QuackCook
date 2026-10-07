extends Node3D
## F6 laboratory for the queue. The main kitchen scene is independent of this lab.

@export var start_in_overview: bool = true
@export_range(0, 100) var test_starting_stock: int = 4
@export_range(1, 1000) var test_wave_size: int = 6
@export var start_test_wave_on_ready: bool = true
var wells: Array[Node] = []
var overview: bool = true
var last_event: String = "Serve #1 Chicken, then watch #2 wait behind at Chicken."
var hit_count: int = 0
var hud: Label
var controls: Label

func _ready() -> void:
	var waiting: Array[Marker3D] = []
	var service: Array[Marker3D] = []
	var escape: Array[Marker3D] = []
	# Child order in the scene tree is the direction of travel, not alphabetical order.
	for marker in $WaitingSlots.get_children():
		if marker is Marker3D: waiting.append(marker)
	for marker in $ServingTable/ServiceSlots.get_children():
		if marker is Marker3D: service.append(marker)
	for marker in $EscapeRoute.get_children():
		if marker is Marker3D: escape.append(marker)
	for well_name in ["ChickenWell", "VegetableWell", "RiceWell", "WaterWell"]:
		wells.append($ServingTable.get_node(well_name))
	if not QueueManager.register_layout(self, waiting, $TrayPickupPoint, service, wells, $ExitPoint, escape, $Player, $Spawner.max_active_prisoners): return
	for well in wells: well.current_servings = mini(test_starting_stock, well.capacity)
	$Spawner.actor_parent = $Prisoners
	$Spawner.wave_spawn_finished.connect(_on_wave_spawn_finished)
	$Spawner.wave_completed.connect(_on_wave_completed)
	QueueManager.event_reported.connect(_on_event)
	QueueManager.attack_contact.connect(_on_attack)
	_build_hud()
	set_overview(start_in_overview)
	if start_test_wave_on_ready: _start_test_wave()

func _on_wave_spawn_finished(total: int) -> void:
	last_event = "All %d prisoners spawned. Waiting for them to leave." % total

func _on_wave_completed(total: int) -> void:
	last_event = "Wave cleared: %d prisoners. Press N for another wave." % total

func _on_event(message: String) -> void:
	last_event = message

func _on_attack(_actor: Node3D, _target: Node3D) -> void:
	hit_count += 1
	last_event = "Prototype attack contact! Total hits: %d" % hit_count

func _build_hud() -> void:
	var panel = PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size.x = 430
	$HUD.add_child(panel)
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column = VBoxContainer.new()
	margin.add_child(column)
	var title = Label.new()
	title.text = "QUACK COOK  /  QUEUE TEST"
	title.add_theme_font_size_override("font_size", 21)
	column.add_child(title)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 15)
	column.add_child(hud)
	var grid = GridContainer.new()
	grid.columns = 4
	column.add_child(grid)
	var names: Array[String] = ["1 Chicken", "2 Veg", "3 Rice", "4 Water"]
	for i in 4:
		var button = Button.new()
		button.text = names[i]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(QueueManager.request_serve.bind(i))
		grid.add_child(button)
	var actions = HBoxContainer.new()
	column.add_child(actions)
	for action in [["N Wave", _start_test_wave], ["F Refill", refill_wells], ["P Pause", toggle_pause], ["R Reset", reset_lab]]:
		var button = Button.new()
		button.text = action[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(action[1])
		actions.add_child(button)
	controls = Label.new()
	controls.text = "V: overview / FPS    WASD + mouse: FPS\nLeft click: aim at SERVE    Esc: exit\nNeeds: C chicken / V veg / R rice / W water"
	controls.add_theme_font_size_override("font_size", 14)
	column.add_child(controls)
	var crosshair = Label.new()
	crosshair.name = "Crosshair"
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(5, 12)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(crosshair)

func _process(_delta: float) -> void:
	if not is_instance_valid(hud): return
	var stock: PackedStringArray = []
	for well in wells: stock.append(str(well.current_servings))
	var status: String = "IDLE"
	if $Spawner.wave_active:
		status = "CLEARING" if $Spawner.remaining_to_spawn() == 0 else ("PAUSED" if $Spawner.spawning_paused else "SPAWNING")
	hud.text = "Queue %d/%d   Alive %d/%d\nWave: %d/%d spawned | %d pending | %s\nStock: %s    Hits: %d\n%s" % [QueueManager.queued_count(), QueueManager.capacity(), QueueManager.active_count(), $Spawner.max_active_prisoners, $Spawner.wave_spawned, $Spawner.wave_total, $Spawner.remaining_to_spawn(), status, " / ".join(stock), hit_count, last_event]

func set_overview(enabled: bool) -> void:
	overview = enabled
	$OverviewCamera.current = enabled
	$Player/Head/Camera3D.current = not enabled
	$Player.set_physics_process(not enabled)
	$Player.set_process_unhandled_input(not enabled)
	$Player/Head.set_process(not enabled)
	$Player/Head.set_process_unhandled_input(not enabled)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if enabled else Input.MOUSE_MODE_CAPTURED
	if enabled: $Player/Head.object_focused.emit(null)
	$HUD/Crosshair.visible = not enabled

func _start_test_wave() -> void:
	if not $Spawner.start_wave(test_wave_size):
		last_event = "Previous wave is still active, or queue setup is unavailable."
		return
	last_event = "Wave started: %d prisoners." % test_wave_size
	# Immediate first prisoner for the lab; the rest follow Spawn Interval.
	$Spawner.spawn_one()

func refill_wells() -> void:
	for well in wells: well.current_servings = well.capacity
	last_event = "Test refill: all wells full."

func toggle_pause() -> void:
	$Spawner.spawning_paused = not $Spawner.spawning_paused

func reset_lab() -> void:
	$Spawner.cancel_wave()
	QueueManager.reset_queue()
	hit_count = 0
	refill_wells()
	_start_test_wave()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_1: QueueManager.request_serve(0)
		KEY_2: QueueManager.request_serve(1)
		KEY_3: QueueManager.request_serve(2)
		KEY_4: QueueManager.request_serve(3)
		KEY_N: _start_test_wave()
		KEY_F: refill_wells()
		KEY_P: toggle_pause()
		KEY_R: reset_lab()
		KEY_V: set_overview(not overview)
		KEY_ESCAPE: get_tree().quit()
