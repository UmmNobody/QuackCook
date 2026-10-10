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

@export_file("*.tscn") var game_over_scene_path: String = "res://scenes/ui/game_over.tscn"
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
	if started and not tutorial_seen: open_tutorial()
	return started

func start_run(first_day: Resource, difficulty: Resource = null, starting_day: int = 1) -> bool:
	if state != State.IDLE or run_active or not first_day is WaveConfig or not first_day.is_valid(): return false
	if difficulty != null and not difficulty is Progression: return false
	_first_day = first_day.duplicate()
	_progression = difficulty.duplicate() if difficulty != null else Progression.new()
	current_day = maxi(1, starting_day)
	run_active = true
	last_summary.clear()
	if not start_service(_progression.settings_for_day(_first_day, current_day)):
		run_active = false
		current_day = 0
		return false
	checkpoint_day = current_day
	day_started.emit(current_day)
	return true

func start_service(settings: Resource) -> bool:
	if state != State.IDLE or not is_instance_valid(layout) or not is_instance_valid(spawner): return false
	if QueueManager.layout_owner != layout or spawner.wave_active or QueueManager.queued_count() > 0 or _has_angry_prisoners(): return false
	if not settings is WaveConfig or not settings.is_valid(): return false
	# Snapshot the input so later Inspector changes cannot alter an active session.
	config = settings.duplicate()
	_generation += 1
	_outcomes.clear()
	spawned_count = 0
	served_count = 0
	failed_count = 0
	spawner.minimum_foods = config.minimum_foods
	spawner.maximum_foods = config.maximum_foods
	spawner.patience_seconds = config.patience_seconds
	spawner.spawn_interval = config.spawn_interval
	spawner.use_example_orders = false
	spawner.spawning_paused = false
	preparation_remaining = config.preparation_seconds
	state = State.PREPARING
	preparation_started.emit(preparation_remaining)
	if preparation_remaining <= 0.0: _begin_service()
	session_changed.emit()
	return true

func _process(delta: float) -> void:
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
	actor.tree_exited.connect(_record_failure.bind(id, _generation), CONNECT_ONE_SHOT)
	session_changed.emit()

func _record_success(id: int, generation: int) -> void:
	if generation != _generation or _outcomes.get(id) != "pending": return
	_outcomes[id] = "served"
	served_count += 1
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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		summary_opened.emit(last_summary.duplicate(true))
	service_finished.emit(summary)
	session_changed.emit()
	return summary

func next_day() -> bool:
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
	day_started.emit(current_day)
	return true

func confirm_summary() -> void:
	if state != State.SUMMARY or _transition_pending or pause_menu_open: return
	if last_summary.get("target_met", false):
		next_day()
	else:
		_transition_pending = true
		_enter_game_over.call_deferred()

func _enter_game_over() -> void:
	_changing_to_game_over = true
	var error := get_tree().change_scene_to_file(game_over_scene_path)
	if error != OK:
		_changing_to_game_over = false
		_transition_pending = false
		push_error("Could not load Game Over scene: " + error_string(error))
		return
	state = State.GAME_OVER
	_resume_world()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_transition_pending = false

func restart_run() -> void:
	if state != State.GAME_OVER or _transition_pending: return
	_transition_pending = true
	_restart_run.call_deferred()

func _restart_run() -> void:
	_load_kitchen(1)

func has_checkpoint() -> bool:
	return checkpoint_day > 0

func launch_from_menu(continue_previous: bool = false) -> bool:
	if is_instance_valid(layout) or _transition_pending or state not in [State.IDLE, State.GAME_OVER]: return false
	if continue_previous and not has_checkpoint(): return false
	_transition_pending = true
	_load_kitchen.call_deferred(checkpoint_day if continue_previous else 1)
	return true

func _load_kitchen(day: int) -> void:
	_pending_start_day = maxi(1, day)
	var error := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if error != OK:
		_pending_start_day = 1
		_transition_pending = false
		push_error("Could not restart kitchen: " + error_string(error))
		return
	_changing_to_game_over = false
	state = State.IDLE
	current_day = 0
	last_summary.clear()
	run_active = false
	_resume_world()
	# Keep the transition guarded until kitchen_queue consumes the pending day.

func toggle_pause_menu() -> void:
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
	if _transition_pending: return false
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
	var error := get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		_transition_pending = false
		push_error("Could not open main menu: " + error_string(error))
		return
	_changing_to_game_over = false
	state = State.IDLE
	current_day = 0
	run_active = false
	last_summary.clear()
	_resume_world()
	_transition_pending = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
