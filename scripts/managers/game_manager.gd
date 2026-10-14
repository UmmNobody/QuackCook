extends Node
## Endless day loop. The kitchen stays loaded between days; only a failed run changes scene.

signal session_changed
signal preparation_started(seconds: float)
signal service_started(total: int)
signal all_prisoners_spawned
signal service_finished(summary: Dictionary)
signal summary_opened(summary: Dictionary)
signal day_started(day: int)
signal pause_menu_changed(open: bool)
signal tutorial_changed(open: bool)

enum State { IDLE, PREPARING, SERVING, SUMMARY, GAME_OVER }
const WaveConfig = preload("res://scripts/resources/service_wave_config.gd")
const Progression = preload("res://scripts/resources/day_progression.gd")
const INTRO_SCENE := "res://scenes/cutscenes/intro_cutscene.tscn"
const LOADING_SCENE := "res://scenes/ui/loading_scene.tscn"
var _intro_active := false
var best_day: int = 0
var run_totals: Dictionary = {"day": 0, "served": 0, "subdued": 0, "unconscious": 0}
var _resume_totals := false
var _subdued_ids: Dictionary = {}
var _run_serial: int = 0

@export_file("*.tscn") var game_over_scene_path: String = "res://scenes/cutscenes/game_over_cutscene.tscn"
@export_range(0.0, 10.0) var summary_delay_seconds: float = 3.0
@export_range(0.0, 60.0) var auto_close_seconds: float = 10.0
## Negative means no closing countdown is active.
var auto_close_remaining: float = -1.0
var summary_pending: bool = false
var current_day: int = 0
var last_summary: Dictionary = {}
var run_active: bool = false
var _first_day: Resource
var _progression: Resource
var _owns_pause: bool = false
var _changing_to_game_over: bool = false
var _transition_pending: bool = false
## Session-only checkpoint. Never written to disk; a new process starts at zero.
var checkpoint_day: int = 0
var pause_menu_open: bool = false
## Once per application session, like the in-memory day checkpoint.
var tutorial_seen: bool = false
var tutorial_open: bool = false
var _pending_start_day: int = 1

var state: State = State.IDLE
var layout: Node3D
var spawner: Node
var config: Resource
var preparation_remaining: float = 0.0
var spawned_count: int = 0
var served_count: int = 0
var failed_count: int = 0
var _outcomes: Dictionary = {}
var _generation: int = 0

func register_kitchen(owner_node: Node3D, wave_spawner: Node) -> bool:
	if is_instance_valid(layout) or QueueManager.layout_owner != owner_node or not is_instance_valid(wave_spawner): return false
	AudioManager.stop_music()
	layout = owner_node
	spawner = wave_spawner
	spawner.prisoner_spawned.connect(_on_prisoner_spawned)
	spawner.wave_spawn_finished.connect(_on_all_spawned)
	layout.tree_exiting.connect(unregister_kitchen.bind(owner_node), CONNECT_ONE_SHOT)
	session_changed.emit()
	return true

func unregister_kitchen(owner_node: Node) -> void:
	if owner_node != layout: return
	_generation += 1
	summary_pending = false
	auto_close_remaining = -1.0
	if is_instance_valid(spawner):
		spawner.cancel_wave()
		if spawner.prisoner_spawned.is_connected(_on_prisoner_spawned): spawner.prisoner_spawned.disconnect(_on_prisoner_spawned)
		if spawner.wave_spawn_finished.is_connected(_on_all_spawned): spawner.wave_spawn_finished.disconnect(_on_all_spawned)
	layout = null
	spawner = null
	config = null
	state = State.GAME_OVER if _changing_to_game_over else State.IDLE
	_resume_world()
	run_active = false
	_first_day = null
	_progression = null
	if not _changing_to_game_over:
		current_day = 0
		last_summary.clear()
	preparation_remaining = 0.0
	spawned_count = 0
	served_count = 0
	failed_count = 0
	_outcomes.clear()
	session_changed.emit()

func start_registered_run(first_day: Resource, difficulty: Resource = null) -> bool:
	var day := _pending_start_day
	_pending_start_day = 1
	_transition_pending = false
	var started := start_run(first_day, difficulty, day)
	if started:
		var player := get_tree().get_first_node_in_group("Player")
		if player != null and not player.unconscious_started.is_connected(_record_player_ko):
			player.unconscious_started.connect(_record_player_ko)
		if not tutorial_seen: open_tutorial()
	return started

func start_run(first_day: Resource, difficulty: Resource = null, starting_day: int = 1) -> bool:
	if state != State.IDLE or run_active or not first_day is WaveConfig or not first_day.is_valid(): return false
	if difficulty != null and not difficulty is Progression: return false
	_first_day = first_day.duplicate()
	_progression = difficulty.duplicate() if difficulty != null else Progression.new()
	if not _resume_totals:
		_run_serial += 1
		run_totals = {"day": 0, "served": 0, "subdued": 0, "unconscious": 0}
		_subdued_ids.clear()
	_resume_totals = false
	current_day = maxi(1, starting_day)
	run_active = true
	last_summary.clear()
	if not start_service(_progression.settings_for_day(_first_day, current_day)):
		run_active = false
		current_day = 0
		return false
	checkpoint_day = current_day
	_record_day()
	day_started.emit(current_day)
	return true

func start_service(settings: Resource) -> bool:
	if state != State.IDLE or not is_instance_valid(layout) or not is_instance_valid(spawner): return false
	if QueueManager.layout_owner != layout or spawner.wave_active or QueueManager.queued_count() > 0 or _has_angry_prisoners(): return false
	if not settings is WaveConfig or not settings.is_valid(): return false
	# Snapshot the input so later Inspector changes cannot alter an active session.
	config = settings.duplicate()
	auto_close_remaining = -1.0
	_generation += 1
	_outcomes.clear()
	spawned_count = 0
	served_count = 0
	failed_count = 0
	spawner.minimum_foods = config.minimum_foods
	spawner.maximum_foods = config.maximum_foods
	spawner.patience_seconds = config.patience_seconds
	spawner.spawn_interval_min = config.spawn_interval_min
	spawner.spawn_interval_max = config.spawn_interval_max
	spawner.use_example_orders = false
	spawner.spawning_paused = false
	preparation_remaining = config.preparation_seconds
	state = State.PREPARING
	preparation_started.emit(preparation_remaining)
	if preparation_remaining <= 0.0: _begin_service()
	session_changed.emit()
	return true

func _process(delta: float) -> void:
	if get_tree().paused or _transition_pending or SceneTransition.busy: return
	if state == State.SERVING:
		if not can_close_kitchen():
			if auto_close_remaining >= 0.0:
				auto_close_remaining = -1.0
				session_changed.emit()
			return
		if auto_close_remaining < 0.0:
			auto_close_remaining = auto_close_seconds
		else:
			auto_close_remaining = maxf(0.0, auto_close_remaining - delta)
		if auto_close_remaining <= 0.0:
			finish_service()
		else:
			session_changed.emit()
		return
	if state != State.PREPARING: return
	preparation_remaining = maxf(0.0, preparation_remaining - delta)
	if preparation_remaining <= 0.0: _begin_service()
	session_changed.emit()

## Manual opening uses the same transition as the preparation timer.
func can_open_kitchen() -> bool:
	return state == State.PREPARING and not get_tree().paused and not _transition_pending and is_instance_valid(spawner) and config != null

func open_kitchen() -> bool:
	if not can_open_kitchen(): return false
	_begin_service()
	session_changed.emit()
	return state == State.SERVING

func _begin_service() -> void:
	# A late timer tick or repeated button activation cannot start another wave.
	if state != State.PREPARING: return
	preparation_remaining = 0.0
	if not is_instance_valid(spawner) or not spawner.start_wave(config.prisoner_count):
		state = State.IDLE
		push_error("Unable to start the registered kitchen's service wave.")
		return
	state = State.SERVING
	service_started.emit(config.prisoner_count)

func _on_prisoner_spawned(actor: Node3D) -> void:
	if state != State.SERVING: return
	spawned_count += 1
	var id := actor.get_instance_id()
	_outcomes[id] = "pending"
	actor.service_completed.connect(_record_success.bind(id, _generation), CONNECT_ONE_SHOT)
	actor.anger_started.connect(_record_failure.bind(id, _generation), CONNECT_ONE_SHOT)
	actor.incapacitated.connect(_record_failure.bind(id, _generation), CONNECT_ONE_SHOT)
	actor.incapacitated.connect(_record_subdued.bind(id, _run_serial), CONNECT_ONE_SHOT)
	actor.tree_exited.connect(_record_failure.bind(id, _generation), CONNECT_ONE_SHOT)
	session_changed.emit()

func _record_success(id: int, generation: int) -> void:
	if generation != _generation or _outcomes.get(id) != "pending": return
	_outcomes[id] = "served"
	served_count += 1
	if run_active: run_totals.served += 1
	session_changed.emit()

func _record_failure(id: int, generation: int) -> void:
	if generation != _generation or _outcomes.get(id) != "pending": return
	_outcomes[id] = "failed"
	failed_count += 1
	session_changed.emit()

func _on_all_spawned(_total: int) -> void:
	all_prisoners_spawned.emit()
	session_changed.emit()

func _has_angry_prisoners() -> bool:
	for actor in QueueManager.actors.values():
		if is_instance_valid(actor) and not actor.is_incapacitated() and not actor.anger_reason.is_empty(): return true
	return false

func can_close_kitchen() -> bool:
	return not pause_menu_open and not tutorial_open and state == State.SERVING and config != null and spawned_count == config.prisoner_count and QueueManager.queued_count() == 0 and not _has_angry_prisoners()

func close_block_reason() -> String:
	if state == State.PREPARING: return "The kitchen has not opened yet"
	if state != State.SERVING: return "No service in progress"
	if spawned_count < config.prisoner_count: return "Wait for all prisoners to arrive"
	if QueueManager.queued_count() > 0: return "There are prisoners in the queue"
	if _has_angry_prisoners(): return "Deal with the angry prisoners first"
	return "Close kitchen and review today"

func get_service_summary() -> Dictionary:
	if config == null: return {}
	return {"day": current_day, "total": config.prisoner_count, "spawned": spawned_count, "served": served_count, "failed": failed_count, "not_served": config.prisoner_count - served_count, "required": config.required_successes, "target_met": served_count >= config.required_successes, "can_close": can_close_kitchen()}

## Shared close entry point. Standalone service tests remain available without starting a run.
func finish_service() -> Dictionary:
	if not can_close_kitchen(): return {}
	var summary := get_service_summary()
	auto_close_remaining = -1.0
	_generation += 1
	spawner.cancel_wave() # Release old corpse tracking without deleting the bodies.
	state = State.SUMMARY if run_active else State.IDLE
	if run_active:
		last_summary = summary.duplicate(true)
		checkpoint_day = current_day + 1 if summary.target_met else 0
		var player := get_tree().get_first_node_in_group("Player")
		if player != null: player.get_node("Head").cancel_interaction()
		_owns_pause = true
		get_tree().paused = true
		summary_pending = true
		_open_summary_after_delay(_generation)
	service_finished.emit(summary)
	session_changed.emit()
	return summary

func _open_summary_after_delay(generation: int) -> void:
	# The world is paused, but the shutter/lever can finish their closing animation.
	if summary_delay_seconds > 0.0:
		await get_tree().create_timer(summary_delay_seconds, true).timeout
	if generation != _generation or not summary_pending or state != State.SUMMARY or not is_instance_valid(layout) or _transition_pending: return
	# Failed days go straight to the comic; only successful days show a report.
	if not last_summary.get("target_met", false):
		summary_pending = false
		_transition_pending = true
		_enter_game_over.call_deferred()
		return
	if not await SceneTransition.cover(): return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	summary_opened.emit(last_summary.duplicate(true))
	await SceneTransition.reveal()
	summary_pending = false

func next_day() -> bool:
	if summary_pending: return false
	if state != State.SUMMARY or not run_active or not last_summary.get("target_met", false) or _transition_pending or pause_menu_open: return false
	var next_settings: Resource = _progression.settings_for_day(_first_day, current_day + 1)
	state = State.IDLE
	current_day += 1
	if not start_service(next_settings):
		current_day -= 1
		state = State.SUMMARY
		return false
	_resume_world()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	checkpoint_day = current_day
	_record_day()
	day_started.emit(current_day)
	return true

func confirm_summary() -> void:
	if SceneTransition.busy or summary_pending: return
	if state != State.SUMMARY or _transition_pending or pause_menu_open: return
	if last_summary.get("target_met", false):
		_advance_day_with_transition()
	else:
		_transition_pending = true
		_enter_game_over.call_deferred()

func _enter_game_over() -> void:
	if not await SceneTransition.cover():
		_transition_pending = false
		return
	_changing_to_game_over = true
	var error := get_tree().change_scene_to_file(game_over_scene_path)
	if error != OK:
		_changing_to_game_over = false
		_transition_pending = false
		push_error("Could not load Game Over scene: " + error_string(error))
		await SceneTransition.reveal()
		return
	state = State.GAME_OVER
	_resume_world()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await SceneTransition.reveal()
	_transition_pending = false

func restart_run() -> void:
	if state != State.GAME_OVER or _transition_pending or SceneTransition.busy: return
	_transition_pending = true
	_restart_run.call_deferred()

func _restart_run() -> void:
	_resume_totals = false
	_load_kitchen(1)

func has_checkpoint() -> bool:
	return checkpoint_day > 0

func launch_from_menu(continue_previous: bool = false) -> bool:
	if is_instance_valid(layout) or SceneTransition.busy or _transition_pending or _intro_active or state not in [State.IDLE, State.GAME_OVER]: return false
	if continue_previous and not has_checkpoint(): return false
	_transition_pending = true
	_resume_totals = continue_previous
	if continue_previous:
		_load_kitchen.call_deferred(checkpoint_day)
	else:
		_open_intro_cutscene.call_deferred()
	return true

func _open_intro_cutscene() -> void:
	if not await SceneTransition.cover():
		_transition_pending = false
		return
	var error := get_tree().change_scene_to_file(INTRO_SCENE)
	_transition_pending = false
	if error != OK:
		push_error("Could not open intro cutscene: " + error_string(error))
		await SceneTransition.reveal()
		return
	_intro_active = true
	_changing_to_game_over = false
	state = State.IDLE
	_resume_world()
	await SceneTransition.reveal()

func finish_intro_cutscene(owner_node: Node) -> bool:
	if _transition_pending or is_instance_valid(layout): return false
	if get_tree().current_scene != owner_node or owner_node.scene_file_path != INTRO_SCENE: return false
	_transition_pending = true
	_intro_active = false
	_load_kitchen.call_deferred(1)
	return true

func _load_kitchen(day: int) -> void:
	if not await SceneTransition.cover():
		_transition_pending = false
		return
	_pending_start_day = maxi(1, day)
	var error := get_tree().change_scene_to_file(LOADING_SCENE)
	if error != OK:
		_pending_start_day = 1
		_transition_pending = false
		push_error("Could not open loading screen: " + error_string(error))
		await SceneTransition.reveal()
		return
	_changing_to_game_over = false
	state = State.IDLE
	current_day = 0
	last_summary.clear()
	run_active = false
	_resume_world()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.stop_music()
	await SceneTransition.reveal()
	var loading := get_tree().current_scene
	if loading != null and loading.scene_file_path == LOADING_SCENE:
		loading.start_loading()
	# Keep the transition guarded until kitchen_queue consumes the pending day.

## The loader keeps resources alive until the PackedScene has entered the tree.
func complete_kitchen_load(owner_node: Node, packed: PackedScene) -> void:
	if not _transition_pending or get_tree().current_scene != owner_node or owner_node.scene_file_path != LOADING_SCENE: return
	if packed == null or not await SceneTransition.cover(): return
	var error := get_tree().change_scene_to_packed(packed)
	if error != OK:
		owner_node.show_error("Could not open the kitchen. Please return to the menu and try again.")
		await SceneTransition.reveal()
		return
	# Set state before the kitchen's deferred start_registered_run executes.
	state = State.IDLE
	await SceneTransition.reveal()

func cancel_kitchen_loading(owner_node: Node) -> void:
	if SceneTransition.busy or get_tree().current_scene != owner_node or owner_node.scene_file_path != LOADING_SCENE: return
	_pending_start_day = 1
	_intro_active = false
	_return_to_menu.call_deferred()

func toggle_pause_menu() -> void:
	if SceneTransition.busy or summary_pending: return
	# Esc dismisses the topmost modal; it must not also open settings.
	if tutorial_open:
		close_tutorial()
		return
	if not is_instance_valid(layout) or not run_active or _transition_pending or state not in [State.PREPARING, State.SERVING, State.SUMMARY]: return
	pause_menu_open = not pause_menu_open
	if pause_menu_open:
		var player := get_tree().get_first_node_in_group("Player")
		if player != null: player.get_node("Head").cancel_interaction()
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		# Closing settings over a report must not resume the simulation behind it.
		get_tree().paused = _owns_pause
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _owns_pause else Input.MOUSE_MODE_CAPTURED
	pause_menu_changed.emit(pause_menu_open)

func return_to_menu() -> bool:
	if SceneTransition.busy or _transition_pending: return false
	if not is_instance_valid(layout) and state != State.GAME_OVER: return false
	if run_active:
		if state == State.SUMMARY:
			checkpoint_day = current_day + 1 if last_summary.get("target_met", false) else 0
		else:
			checkpoint_day = current_day
	_transition_pending = true
	_return_to_menu.call_deferred()
	return true

func _return_to_menu() -> void:
	if not await SceneTransition.cover():
		_transition_pending = false
		return
	var error := get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		_transition_pending = false
		push_error("Could not open main menu: " + error_string(error))
		await SceneTransition.reveal()
		return
	_changing_to_game_over = false
	state = State.IDLE
	current_day = 0
	run_active = false
	last_summary.clear()
	_resume_world()
	_transition_pending = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await SceneTransition.reveal()

func _resume_world() -> void:
	if _owns_pause or pause_menu_open or tutorial_open:
		get_tree().paused = false
		_owns_pause = false
	if tutorial_open:
		tutorial_open = false
		tutorial_changed.emit(false)
	if pause_menu_open:
		pause_menu_open = false
		pause_menu_changed.emit(false)

func open_tutorial() -> bool:
	if tutorial_open or get_tree().paused or _transition_pending or not is_instance_valid(layout): return false
	if not run_active or state not in [State.PREPARING, State.SERVING]: return false
	# Do not pause without an installed view to let the player close it.
	if not tutorial_changed.has_connections(): return false
	var player := get_tree().get_first_node_in_group("Player")
	if player != null:
		if player.is_incapacitated(): return false
		player.get_node("Head").cancel_interaction()
	tutorial_seen = true
	tutorial_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tutorial_changed.emit(true)
	return true

func close_tutorial() -> void:
	if not tutorial_open: return
	tutorial_open = false
	get_tree().paused = _owns_pause or pause_menu_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
	tutorial_changed.emit(false)

func _record_day() -> void:
	run_totals.day = maxi(int(run_totals.day), current_day)
	best_day = maxi(best_day, current_day)

func _record_subdued(id: int, serial: int) -> void:
	if not run_active or serial != _run_serial or _subdued_ids.has(id): return
	_subdued_ids[id] = true
	run_totals.subdued += 1

func _record_player_ko() -> void:
	if run_active: run_totals.unconscious += 1

func _advance_day_with_transition() -> void:
	if not await SceneTransition.cover(): return
	next_day()
	await SceneTransition.reveal()

## Only the current Game Over comic can finish into the final report.
func show_run_summary(owner_node: Node) -> void:
	if _transition_pending or state != State.GAME_OVER or get_tree().current_scene != owner_node: return
	_transition_pending = true
	_show_run_summary.call_deferred()

func _show_run_summary() -> void:
	if not await SceneTransition.cover():
		_transition_pending = false
		return
	var error := get_tree().change_scene_to_file("res://scenes/ui/run_summary.tscn")
	if error != OK: push_error("Could not open final report: " + error_string(error))
	await SceneTransition.reveal()
	_transition_pending = false

func open_menu_page(page: String) -> void:
	if SceneTransition.busy or _transition_pending or is_instance_valid(layout) or _intro_active: return
	if page not in ["settings_page", "credits", "main_menu"]: return
	_transition_pending = true
	_change_menu_page.call_deferred(page)

func _change_menu_page(page: String) -> void:
	if not await SceneTransition.cover():
		_transition_pending = false
		return
	var error := get_tree().change_scene_to_file("res://scenes/ui/%s.tscn" % page)
	if error != OK: push_error("Could not open menu page: " + error_string(error))
	await SceneTransition.reveal()
	_transition_pending = false
