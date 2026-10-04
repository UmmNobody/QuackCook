extends Node3D
## ฉากตรวจงาน NPC เท่านั้น เปิดฉากนี้แล้วกด F6 ได้โดยไม่เปลี่ยน main scene ของทีม
## UI ใช้ภาษาอังกฤษเพื่อไม่ต้องเพิ่มไฟล์ฟอนต์ไทยขนาดใหญ่; โค้ดและคู่มืออธิบายภาษาไทย

const NPC_WORLD = preload("res://npc/scenes/npc_world.tscn")
const PRISONER = preload("res://npc/scenes/prisoner.tscn")
const CLIPS = ["P1_Idle", "P1_Walk_Waddle_Blockout", "P1_Tray_Pickup", "P1_Tray_Idle", "P1_Tray_Walk", "P1_Tray_Throw", "P1_Combat_Enter", "P1_Combat_Idle", "P1_Combat_Walk", "P1_Combat_Walk_Punch", "P1_Punch_Combo", "P1_Boxing_Flurry", "P1_Kick_Front_R"]
var actors: Node3D
var prisoner: QuackNpc
var camera: Camera3D
var info: Label
var event_info: Label
var timeline: HSlider
var updating: bool = false
var yaw: float = 0.15
var pitch: float = 0.27
var distance: float = 8.7
var sequence: bool = false
var sequence_index: int = 0
var sequence_time: float = 0.0
var paused: bool = false
var scrubbed: bool = false
var preview_tray: QuackServingTray
var spawned: Array[QuackNpc] = []

func _ready() -> void:
	get_window().title = "QuackCook NPC Lab v1.2"
	# คืนเมาส์ให้ UI เฉพาะฉากทดสอบ ไม่เรียกสคริปต์ Player ของทีม
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_stage()
	actors = NPC_WORLD.instantiate()
	add_child(actors)
	prisoner = actors.get_node("Prisoner")
	prisoner.attack_contact.connect(func(_a, _t, name_key): event_info.text = "Attack contact: " + name_key)
	prisoner.tray_released.connect(func(_tray): event_info.text = "Same tray released / Godot physics")
	_build_ui()
	# โชว์ชุดศีรษะครบทุกแบบโดยใช้ scene ต้นแบบเดียวกัน
	for i in 6:
		var npc: QuackNpc = PRISONER.instantiate()
		npc.appearance = i
		npc.position = Vector3(-3.2 + 1.28 * i, 0, -4.2)
		add_child(npc)
		spawned.append(npc)
		var title = Label3D.new()
		title.text = ["Bald", "Gold", "Black", "Brown", "Blindfold", "Hat"][i]
		title.position.y = 1.9
		title.font_size = 32
		title.pixel_size = 0.006
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		npc.add_child(title)

func _build_stage() -> void:
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("1b2534")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c5d9ed")
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	add_child(light)
	var floor_body = StaticBody3D.new()
	add_child(floor_body)
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(24, 0.1, 24)
	mesh.mesh = box
	mesh.position.y = -0.05
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("48566a")
	mesh.material_override = material
	floor_body.add_child(mesh)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	collision.position.y = -0.05
	floor_body.add_child(collision)
	camera = Camera3D.new()
	camera.fov = 48
	camera.current = true
	add_child(camera)

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 31
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Control, text: String, size: int = 15) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _build_ui() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	var panel = PanelContainer.new()
	panel.position = Vector2(14, 14)
	panel.custom_minimum_size.x = 325
	panel.size = Vector2(325, maxf(320, get_viewport().get_visible_rect().size.y - 28))
	canvas.add_child(panel)
	# หน้าต่างโปรเจกต์หลักอาจเตี้ยกว่าฉากทดสอบเดิม จึงให้แผงปุ่มเลื่อนได้
	get_viewport().size_changed.connect(func(): panel.size.y = maxf(320, get_viewport().get_visible_rect().size.y - 28))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margins = MarginContainer.new()
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]: margins.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margins)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margins.add_child(column)
	_label(column, "QUACK COOK / NPC LAB", 23)
	_label(column, "1 prisoner template / 2 police dances")
	var list = OptionButton.new()
	for name_key in CLIPS: list.add_item(name_key)
	list.item_selected.connect(func(index): _preview(CLIPS[index]))
	column.add_child(list)
	var appearance_list = OptionButton.new()
	for text in ["Bald", "Hair: Gold", "Hair: Black", "Hair: Brown", "Blindfold", "Prisoner hat"]: appearance_list.add_item(text)
	appearance_list.select(prisoner.appearance)
	appearance_list.item_selected.connect(func(index): prisoner.set_appearance(index))
	column.add_child(appearance_list)
	_button(column, "Random appearance", func(): prisoner.set_appearance(randi_range(0, 5)))
	_button(column, "Play full sequence", _start_sequence)
	_button(column, "Receive tray", func(): _clear(); prisoner.pickup_tray())
	_button(column, "Throw tray > fight mode", _throw_into_fight)
	_button(column, "Walk to marker", func(): sequence = false; prisoner.walk_to(Vector3(0, 0, 2.4)))
	_button(column, "Police: swap both dances", _swap_dances)
	_button(column, "Show 4 empty slot markers", _show_slots)
	var row = HBoxContainer.new()
	column.add_child(row)
	_button(row, "Pause / Resume", _pause)
	_button(row, "Reset", _clear)
	_label(column, "Pose timeline (release uses physics)")
	timeline = HSlider.new()
	timeline.step = 1.0 / 24.0
	timeline.value_changed.connect(_scrub)
	column.add_child(timeline)
	info = _label(column, "")
	event_info = _label(column, "")
	_label(column, "Right drag: orbit / wheel: zoom\nSpace: pause / R: reset\nRear row: 6 appearance options\nPolice dances play at left and right", 14)

func _preview(name_key: String) -> void:
	_clear()
	prisoner.auto_return_to_idle = false
	if name_key.begins_with("P1_Tray_"):
		prisoner.pickup_tray()
		preview_tray = prisoner.held_tray
	prisoner.play_clip(name_key)

func _clear() -> void:
	sequence = false
	paused = false
	scrubbed = false
	preview_tray = null
	prisoner.end_combat()
	prisoner.position = Vector3.ZERO
	prisoner.rotation = Vector3.ZERO
	prisoner.velocity = Vector3.ZERO
	if is_instance_valid(prisoner.held_tray): prisoner.held_tray.queue_free()
	prisoner.held_tray = null
	# ถาดเป็นลูกของ actor group เพราะต้องอยู่ต่อหลังหลุดจากมือ
	for child in actors.get_children():
		if child is QuackServingTray: child.queue_free()
	prisoner.auto_return_to_idle = true
	if event_info: event_info.text = ""

func _start_sequence() -> void:
	_clear()
	sequence = true
	sequence_index = 0
	sequence_time = 0
	prisoner.auto_return_to_idle = false
	prisoner.play_clip(CLIPS[0])

func _swap_dances() -> void:
	for path in ["PoliceDance01", "PoliceDance02"]:
		var npc: QuackNpc = actors.get_node(path)
		npc.play_clip("Police_Dance_02" if npc.clip == "Police_Dance_01" else "Police_Dance_01")

func _show_slots() -> void:
	if not is_instance_valid(prisoner.held_tray):
		event_info.text = "Receive a tray first."
		return
	# Marker เป็นจุดอ้างอิง ไม่มีอาหารจำลอง และไม่กินช่องข้อมูลอาหารจริง
	for i in 4:
		var slot = prisoner.held_tray.slots[i]
		if slot.get_node_or_null("DebugLabel"): continue
		var label = Label3D.new()
		label.name = "DebugLabel"
		label.text = str(i + 1)
		label.position.y = 0.07
		label.pixel_size = 0.0018
		label.font_size = 32
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		slot.add_child(label)

func _pause() -> void:
	if (scrubbed and prisoner.clip == "P1_Tray_Throw") or (not prisoner.animations[prisoner.clip].loop and prisoner.clock >= prisoner.player.get_animation(prisoner.clip).length):
		_preview(prisoner.clip)
		return
	scrubbed = false
	paused = not paused
	prisoner.playing = not paused
	for child in actors.get_children():
		if child is QuackServingTray and child.thrown: child.freeze = paused

func _throw_into_fight() -> void:
	# ปุ่มโยนต้องเริ่มเล่นเสมอ แม้ก่อนหน้าผู้ใช้จะกด Pause หรือเลื่อน Timeline
	sequence = false
	paused = false
	scrubbed = false
	prisoner.auto_return_to_idle = true
	prisoner.begin_combat()

func _scrub(value: float) -> void:
	if updating: return
	sequence = false
	paused = true
	scrubbed = true
	prisoner.playing = false
	if prisoner.clip == "P1_Tray_Throw":
		if is_instance_valid(prisoner.held_tray): preview_tray = prisoner.held_tray
		# เลื่อนกลับก่อนปล่อย: จับถาดชิ้นเดิมคืนเพื่อดู pose ได้ทั้งสองทิศทาง
		if value < QuackNpc.RELEASE_TIME and not is_instance_valid(prisoner.held_tray) and is_instance_valid(preview_tray):
			prisoner.pickup_tray(preview_tray)
			prisoner.play_clip("P1_Tray_Throw")
			prisoner.playing = false
		# การ seek ข้าม frame 18 ต้องปล่อยด้วย มิฉะนั้นถาดจะ freeze ค้างและตามมือในท่าจบ
		if value >= QuackNpc.RELEASE_TIME and is_instance_valid(prisoner.held_tray):
			prisoner._release_tray()
	prisoner.clock = value
	prisoner.apply_pose(value)
	event_info.text = "Tray released: physics active." if prisoner.clip == "P1_Tray_Throw" and value >= QuackNpc.RELEASE_TIME else "Pose paused. Resume or select a clip."

func _process(delta: float) -> void:
	if not prisoner: return
	if sequence and not paused:
		# นับเป็นเวลาในคลิปเช่นเดียวกับ NPC เพื่อไม่ค้างรอเมื่อเล่นเร็วขึ้น
		sequence_time += delta * prisoner.playback_speed
		var length = prisoner.player.get_animation(prisoner.clip).length
		if sequence_time >= length * (2.0 if prisoner.animations[prisoner.clip].loop else 1.0):
			sequence_index += 1
			sequence_time = 0
			if sequence_index >= CLIPS.size():
				sequence = false
				prisoner.play_clip("P1_Combat_Idle")
			else:
				if CLIPS[sequence_index] == "P1_Tray_Pickup": prisoner.pickup_tray()
				prisoner.play_clip(CLIPS[sequence_index])
	updating = true
	timeline.max_value = prisoner.player.get_animation(prisoner.clip).length
	timeline.value = prisoner.clock
	updating = false
	info.text = "%s\nFrame %d / %d | Hands: %d | %.1fx" % [prisoner.clip, roundi(prisoner.clock * 24 + 1), prisoner.animations[prisoner.clip].export_end, prisoner.hand_mode, prisoner.playback_speed]
	var target = Vector3(0, 0.9, -0.8)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)
	camera.h_offset = -1.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.005, -0.1, 1.2)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(3, distance - 0.5)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(16, distance + 0.5)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: _pause()
		if event.keycode == KEY_R: _clear()
