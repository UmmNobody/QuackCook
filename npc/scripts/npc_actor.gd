class_name QuackNpc
extends CharacterBody3D
## เจ้าของพฤติกรรม NPC: การเดิน โหมดมือ เครื่องแต่งกาย และจังหวะปล่อยถาด
## ไม่แก้ผู้เล่น/อาหารของทีม: ส่ง signal ให้ระบบเกมนำไปเชื่อมต่อแทน

signal animation_completed(clip_name: String)
signal arrived(npc: QuackNpc)
signal tray_released(tray: QuackServingTray)
signal tray_filled(tray: QuackServingTray)
signal attack_contact(attacker: QuackNpc, target: Node3D, attack_name: String)

enum Role { PRISONER, POLICE }
enum Mode { EMPTY, CARRY, COMBAT }
@export var role: Role = Role.PRISONER
## -1 = สุ่มครั้งเดียวตอนสร้าง; 0 = โล้น, 1/2/3 = ผม, 4 = ผ้าปิดตา, 5 = หมวก
@export_range(-1, 5) var appearance: int = -1
@export_enum("Police_Dance_01", "Police_Dance_02") var police_dance: String = "Police_Dance_01"
## เปิดเมื่อฉากเกมมี NavigationRegion3D ที่ bake แล้ว; ฉากทดสอบพื้นโล่งใช้การเดินตรง
@export var use_navigation: bool = false
@export var auto_return_to_idle: bool = true
@export var attack_distance: float = 1.05
@export var walk_punch_enabled: bool = true

const PRISONER_MODEL = preload("res://npc/assets/prisoner.glb")
const POLICE_MODEL = preload("res://npc/assets/police.glb")
const TRAY_SCENE = preload("res://npc/scenes/serving_tray.tscn")
const RELEASE_TIME = 17.0 / 24.0 # Blender frame 18 เริ่มนับคลิปที่เวลา 0
const ATTACKS = ["P1_Punch_Combo", "P1_Boxing_Flurry", "P1_Kick_Front_R"]
const NORMAL_CLIP_SPEED = 1.75 # เร็วขึ้น 75%; ท่า Walk ทุกแบบและ Boxing Flurry ใช้ความเร็วเดิม
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var navigation: NavigationAgent3D
var hold_point: Marker3D
var held_tray: QuackServingTray
var mode: Mode = Mode.EMPTY
var clip: String = ""
var clock: float = 0.0
var playing: bool = true
var playback_speed: float = 1.0
var metadata: Dictionary
var animations: Dictionary = {}
var grip_offset: Transform3D
var destination: Vector3
var walking: bool = false
var fight_target: Node3D
var attack_index: int = 0
var hand_mode: int = 0

func _ready() -> void:
	add_to_group("QuackNpc")
	# ใช้ collision layer/mask ของ scene (ค่าเริ่มต้น 1) จึงชนพื้น ผู้เล่น และ NPC อื่นได้
	# Model เป็นลูกใน .tscn เพื่อให้ทีมเห็นรูปร่างและจัดตำแหน่งใน Editor ได้ก่อนกดเล่น
	model = get_node_or_null("Model")
	if not model:
		model = (PRISONER_MODEL if role == Role.PRISONER else POLICE_MODEL).instantiate()
		add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	# คุมเวลาใน physics tick เพื่อให้ event จับ/โยนตรงกับ pose ที่คำนวณ
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for item in JSON.parse_string(FileAccess.get_file_as_string("res://npc/assets/animation_manifest.json")):
		if player.has_animation(item.action): animations[item.action] = item
	metadata = JSON.parse_string(FileAccess.get_file_as_string("res://npc/assets/rig_metadata.json"))
	var g: Array = metadata.grip_offset_columns
	grip_offset = Transform3D(Basis(_vec(g[0]), _vec(g[1]), _vec(g[2])), _vec(g[3]))
	hold_point = Marker3D.new()
	hold_point.name = "TrayHoldPoint"
	add_child(hold_point)
	navigation = NavigationAgent3D.new()
	navigation.name = "NavigationAgent3D"
	navigation.path_desired_distance = 0.15
	navigation.target_desired_distance = 0.15
	add_child(navigation)
	if role == Role.PRISONER:
		set_appearance(randi_range(0, 5) if appearance < 0 else appearance)
		play_clip("P1_Idle")
	else: play_clip(police_dance)

func _vec(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

## สลับ node visibility เฉพาะตัวนี้ ไม่แก้ material หรือ mesh resource ที่แชร์กัน
func set_appearance(index: int) -> void:
	appearance = clampi(index, 0, 5)
	for i in range(1, metadata.appearances.size()):
		var accessory = model.find_child(metadata.appearances[i], true, false)
		if accessory: accessory.visible = i == appearance

func play_clip(name_key: String) -> void:
	if not animations.has(name_key): return
	clip = name_key
	playback_speed = 1.0 if "Walk" in clip or clip == "P1_Boxing_Flurry" else NORMAL_CLIP_SPEED
	clock = 0.0
	playing = true
	mode = int(animations[clip].mode) as Mode
	player.stop()
	skeleton.reset_bone_poses()
	player.play(clip)
	apply_pose(0.0)

## ใช้ได้ทั้งการเล่นจริงและเครื่องมือเลื่อนเฟรม; ไม่ยิง event ระหว่างตรวจ pose
func apply_pose(time: float) -> void:
	player.seek(time, true, true)
	var frame = time * 24.0 + 1.0
	hand_mode = int(animations[clip].mode)
	if clip == "P1_Tray_Pickup" and frame < 4.999: hand_mode = 0
	if clip == "P1_Tray_Throw" and frame >= 39.999: hand_mode = 0
	if clip == "P1_Combat_Enter" and frame < 2.999: hand_mode = 0
	for side in ["L", "R"]:
		model.find_child("Hand_Hold_" + side, true, false).visible = hand_mode == 1
		model.find_child("Hand_Fist_" + side, true, false).visible = hand_mode == 2
	_update_hold_point()

func _update_hold_point() -> void:
	# ใช้ hand.L ที่มีอยู่แล้ว + offset จาก Blender จึงไม่มี tray bone ในโมเดล
	hold_point.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand.L")) * grip_offset
	if is_instance_valid(held_tray):
		if clip != "P1_Tray_Pickup" or clock >= RELEASE_TIME:
			held_tray.global_transform = hold_point.global_transform

## เกมเรียกเพื่อให้ NPC เดินไปยังจุดคิว/เคาน์เตอร์/ทางออก
func walk_to(point: Vector3) -> void:
	if role != Role.PRISONER: return
	destination = point
	navigation.target_position = point
	walking = true
	play_clip("P1_Tray_Walk" if is_instance_valid(held_tray) else ("P1_Combat_Walk" if mode == Mode.COMBAT else "P1_Walk_Waddle_Blockout"))

func stop_walking() -> void:
	walking = false
	velocity.x = 0
	velocity.z = 0

## existing_tray ช่วยรับถาด instance จริงจากระบบเกมได้; null = สร้างถาด NPC ใหม่
func pickup_tray(existing_tray: QuackServingTray = null) -> void:
	if role != Role.PRISONER or is_instance_valid(held_tray): return
	if is_instance_valid(existing_tray) and is_instance_valid(existing_tray.holder) and existing_tray.holder != self: return
	stop_walking()
	held_tray = existing_tray
	if not is_instance_valid(held_tray):
		held_tray = TRAY_SCENE.instantiate()
		get_parent().add_child(held_tray)
		held_tray.global_transform = global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.64, 0.98))
	held_tray.equip(self)
	held_tray.contents_changed.connect(_contents_changed)
	play_clip("P1_Tray_Pickup")

func _contents_changed(count: int) -> void:
	if count == 4 and is_instance_valid(held_tray): tray_filled.emit(held_tray)

func receive_food(food: Node3D, slot: int = -1) -> bool:
	return is_instance_valid(held_tray) and held_tray.insert_item(food, slot)

## จุดเชื่อมเหตุการณ์โกรธ/เริ่มสู้; ถ้ามีถาดจะโยนก่อนแล้วค่อยตั้งการ์ด
func begin_combat(target: Node3D = null) -> void:
	if role != Role.PRISONER: return
	fight_target = target
	stop_walking()
	play_clip("P1_Tray_Throw" if is_instance_valid(held_tray) else "P1_Combat_Enter")

func end_combat() -> void:
	fight_target = null
	stop_walking()
	play_clip("P1_Idle")

func request_attack(attack_name: String) -> void:
	if role != Role.PRISONER or attack_name not in ATTACKS: return
	stop_walking()
	play_clip(attack_name)

func _release_tray() -> void:
	if not is_instance_valid(held_tray): return
	# ประเมิน frame ปล่อยที่แน่นอน แม้ tick นี้จะกระโดดข้ามเวลา event
	player.seek(RELEASE_TIME, true, true)
	_update_hold_point()
	var tray = held_tray
	held_tray = null
	tray.contents_changed.disconnect(_contents_changed)
	tray.throw_from(hold_point.global_transform, global_basis * Vector3(1.6, 1.7, 2.3))
	tray_released.emit(tray)

func _events_between(previous: float, current: float) -> void:
	if clip == "P1_Tray_Throw" and previous < RELEASE_TIME and current >= RELEASE_TIME: _release_tray()
	var contacts: Array = []
	match clip:
		"P1_Punch_Combo": contacts = [8, 23]
		"P1_Boxing_Flurry": contacts = [23, 29, 35, 42, 48, 64, 70, 76]
		"P1_Kick_Front_R": contacts = [14]
		"P1_Combat_Walk_Punch": contacts = [12, 36]
	for frame in contacts:
		var time = (float(frame) - 1.0) / 24.0
		if previous < time and current >= time:
			# ส่งคำขอโจมตีเท่านั้น ทีมเกมเป็นผู้ตรวจ hitbox และหัก HP
			attack_contact.emit(self, fight_target if is_instance_valid(fight_target) else null, clip)

func _finish_clip(finished: String) -> void:
	animation_completed.emit(finished)
	if clip != finished: return # เคารพกรณีระบบเกมเลือกท่าใหม่จาก signal แล้ว
	if not auto_return_to_idle: return
	match finished:
		"P1_Tray_Pickup": play_clip("P1_Tray_Idle")
		"P1_Tray_Throw": play_clip("P1_Combat_Enter")
		"P1_Combat_Enter", "P1_Punch_Combo", "P1_Boxing_Flurry", "P1_Kick_Front_R": play_clip("P1_Combat_Idle")

func _physics_process(delta: float) -> void:
	if not player: return
	if playing:
		var length = player.get_animation(clip).length
		var previous = clock
		clock += delta * playback_speed
		_events_between(previous, minf(clock, length))
		if animations[clip].loop and clock >= length:
			clock = fmod(clock, length)
			_events_between(-0.00001, clock)
		apply_pose(minf(clock, length))
		if not animations[clip].loop and clock >= length:
			clock = length
			playing = false
			_finish_clip(clip)
	if not is_on_floor(): velocity.y += get_gravity().y * delta
	if role == Role.PRISONER and playing:
		_update_combat()
		_move_toward_destination()
	else:
		velocity.x = 0
		velocity.z = 0
	move_and_slide()
	_update_hold_point()

func _update_combat() -> void:
	if not is_instance_valid(fight_target) or mode != Mode.COMBAT or clip == "P1_Combat_Enter" or clip in ATTACKS: return
	var gap = global_position.distance_to(fight_target.global_position)
	if gap > attack_distance:
		destination = fight_target.global_position
		navigation.target_position = destination
		walking = true
		var next_clip = "P1_Combat_Walk_Punch" if walk_punch_enabled else "P1_Combat_Walk"
		if clip != next_clip: play_clip(next_clip)
	else:
		request_attack(ATTACKS[attack_index % ATTACKS.size()])
		attack_index += 1

func _move_toward_destination() -> void:
	velocity.x = 0
	velocity.z = 0
	if not walking or not "Walk" in clip: return
	var target = destination
	if use_navigation:
		# ไม่เดินสุ่มผ่านฉาก หาก navmesh ยังไม่พร้อม
		if NavigationServer3D.map_get_iteration_id(navigation.get_navigation_map()) == 0: return
		target = navigation.get_next_path_position()
	var offset = target - global_position
	offset.y = 0
	var distance = Vector2(destination.x - global_position.x, destination.z - global_position.z).length()
	if distance < 0.15:
		stop_walking()
		play_clip("P1_Tray_Idle" if is_instance_valid(held_tray) else ("P1_Combat_Idle" if mode == Mode.COMBAT else "P1_Idle"))
		arrived.emit(self)
		return
	if offset.length() < 0.001: return
	var direction = offset.normalized()
	rotation.y = atan2(direction.x, direction.z) # โมเดล export หันหน้า +Z
	var speed = 0.38 if clip == "P1_Walk_Waddle_Blockout" else (0.283 if clip == "P1_Combat_Walk_Punch" else 0.333)
	velocity.x = direction.x * speed * playback_speed
	velocity.z = direction.z * speed * playback_speed

func _exit_tree() -> void:
	# ถาดที่ถืออยู่หายพร้อม NPC; ถาดที่โยนแล้วเป็นของฉากและอยู่ต่อได้
	if is_instance_valid(held_tray): held_tray.queue_free()
