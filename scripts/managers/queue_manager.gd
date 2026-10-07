extends Node
## Scene markers are ordered from the entry to the exit. Only this autoload
## assigns occupancy; physics and animation remain the prisoner's responsibility.

signal queue_changed
signal event_reported(message: String)
signal attack_contact(prisoner: Node3D, target: Node3D)

enum SlotType { WAITING, TRAY_PICKUP, SERVING }

var layout_owner: Node
var slots: Array[Marker3D] = []
var slot_types: Array[SlotType] = []
var wells: Array[Node] = []
var occupants: Array = []
var reservations: Array = []
var actors: Dictionary = {}
var departing: Dictionary = {}
var waiting_count: int = 0
var tray_pickup_index: int = -1
var service_start_index: int = 0
var max_active_prisoners: int = 12
var exit_point: Marker3D
var escape_route: Array[Marker3D] = []
var player_target: Node3D
var next_ticket: int = 1

func register_layout(owner_node: Node, waiting: Array[Marker3D], tray_pickup: Marker3D, service: Array[Marker3D], food_wells: Array[Node], end_point: Marker3D, escape: Array[Marker3D], target: Node3D, max_alive: int) -> bool:
	if waiting.is_empty() or not is_instance_valid(tray_pickup) or service.size() != food_wells.size() or service.size() != 4:
		push_error("Queue requires waiting markers, one tray pickup marker, and four service markers/wells.")
		return false
	if is_instance_valid(layout_owner) and layout_owner != owner_node:
		push_error("A queue layout is already registered.")
		return false
	unregister_layout(layout_owner)
	layout_owner = owner_node
	slots.append_array(waiting)
	slots.append(tray_pickup)
	slots.append_array(service)
	waiting_count = waiting.size()
	tray_pickup_index = waiting_count
	service_start_index = waiting_count + 1
	for _marker in waiting: slot_types.append(SlotType.WAITING)
	slot_types.append(SlotType.TRAY_PICKUP)
	for _marker in service: slot_types.append(SlotType.SERVING)
	wells.assign(food_wells)
	exit_point = end_point
	escape_route.assign(escape)
	player_target = target
	max_active_prisoners = maxi(1, max_alive)
	occupants.resize(slots.size())
	reservations.resize(slots.size())
	occupants.fill(null)
	reservations.fill(null)
	owner_node.tree_exiting.connect(unregister_layout.bind(owner_node), CONNECT_ONE_SHOT)
	for i in wells.size():
		wells[i].get_node("ServeButton").serve_handler = request_serve.bind(i)
	queue_changed.emit()
	return true

func unregister_layout(owner_node: Node) -> void:
	if owner_node != layout_owner: return
	for well in wells:
		if is_instance_valid(well): well.get_node("ServeButton").serve_handler = Callable()
	slots.clear()
	slot_types.clear()
	wells.clear()
	occupants.clear()
	reservations.clear()
	actors.clear()
	departing.clear()
	escape_route.clear()
	exit_point = null
	player_target = null
	layout_owner = null
	waiting_count = 0
	tray_pickup_index = -1
	service_start_index = 0
	next_ticket = 1

func reset_queue() -> void:
	for tray in get_tree().get_nodes_in_group("DiscardedPrisonerTrays"):
		if is_instance_valid(layout_owner) and layout_owner.is_ancestor_of(tray): tray.queue_free()
	for actor in actors.values():
		if is_instance_valid(actor): actor.queue_free()
	actors.clear()
	departing.clear()
	occupants.fill(null)
	reservations.fill(null)
	next_ticket = 1
	queue_changed.emit()

func capacity() -> int:
	return slots.size()

func active_count() -> int:
	return actors.size()

func queued_count() -> int:
	var total: int = 0
	for actor in actors.values():
		if is_instance_valid(actor) and not actor.is_departing(): total += 1
	return total

func can_spawn() -> bool:
	return is_instance_valid(layout_owner) and not slots.is_empty() and actors.size() < max_active_prisoners and occupants[0] == null and reservations[0] == null

func admit(actor: Node3D) -> bool:
	if not can_spawn() or not actor.is_inside_tree(): return false
	var id: int = actor.get_instance_id()
	actors[id] = actor
	actor.ticket = next_ticket
	next_ticket += 1
	actor.global_position = slots[0].global_position
	actor.slot_index = 0
	actor.target_index = -1
	occupants[0] = actor
	actor.set_waiting(false, false)
	actor.tree_exiting.connect(_forget_actor.bind(id), CONNECT_ONE_SHOT)
	event_reported.emit("#%d joined: %s" % [actor.ticket, actor.order_text()])
	queue_changed.emit()
	return true

func _forget_actor(id: int) -> void:
	var actor = actors.get(id)
	if actor == null: return
	for i in slots.size():
		if occupants[i] == actor: occupants[i] = null
		if reservations[i] == actor: reservations[i] = null
	departing.erase(id)
	actors.erase(id)
	queue_changed.emit()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(layout_owner): return
	# A departing capsule still blocks its old slot until its body clears the lane.
	for id in departing.keys():
		var actor = actors.get(id)
		var index: int = departing[id]
		if not is_instance_valid(actor): continue
		var offset: Vector3 = actor.global_position - slots[index].global_position
		offset.y = 0
		if offset.length() >= 0.85:
			if occupants[index] == actor: occupants[index] = null
			departing.erase(id)
			actor.slot_index = -1
			queue_changed.emit()
	# Front to back: followers only get the next slot after its old owner arrives.
	for i in range(slots.size() - 1, -1, -1):
		var actor = occupants[i]
		if not is_instance_valid(actor) or actor.is_departing() or actor.is_moving(): continue
		if _must_wait(actor, i): continue
		if i == slots.size() - 1:
			departing[actor.get_instance_id()] = i
			actor.begin_exit(exit_point.global_position)
		elif occupants[i + 1] == null and reservations[i + 1] == null:
			reservations[i + 1] = actor
			actor.move_to_slot(i + 1, slots[i + 1].global_position)

func arrived(actor: Node3D, destination: int) -> void:
	if destination < 0 or destination >= slots.size() or reservations[destination] != actor: return
	var old_index: int = actor.slot_index
	if old_index >= 0 and occupants[old_index] == actor: occupants[old_index] = null
	reservations[destination] = null
	occupants[destination] = actor
	actor.slot_index = destination
	actor.target_index = -1
	_must_wait(actor, destination)
	queue_changed.emit()

func _must_wait(actor: Node3D, index: int) -> bool:
	if slot_types[index] == SlotType.TRAY_PICKUP:
		actor.face_towards(slots[index].global_position + slots[index].global_basis.z)
		actor.wait_at_tray_pickup()
		return not actor.tray_pickup_complete()
	var in_service: bool = slot_types[index] == SlotType.SERVING
	if in_service: actor.face_towards(wells[index - service_start_index].global_position)
	var wants_here: bool = in_service and actor.needs_food(wells[index - service_start_index].accepted_type)
	actor.set_waiting(in_service, wants_here)
	return wants_here

func occupant_at_station(station_index: int) -> Node3D:
	if station_index < 0 or station_index >= wells.size(): return null
	var actor = occupants[service_start_index + station_index]
	if not is_instance_valid(actor) or actor.is_moving() or actor.is_departing(): return null
	return actor

func request_serve(station_index: int) -> bool:
	var actor = occupant_at_station(station_index)
	if actor == null:
		event_reported.emit("Nobody is standing at this station.")
		return false
	if not actor.has_serving_tray():
		event_reported.emit("This prisoner has no serving tray.")
		return false
	var well = wells[station_index]
	if not well.serve_one():
		event_reported.emit("This well is empty.")
		return false
	var wanted_food: bool = actor.needs_food(well.accepted_type)
	# Wrong servings are visible too, but do not fulfill a requested food.
	actor.receive_food(well.accepted_type)
	if wanted_food:
		event_reported.emit("#%d received %s" % [actor.ticket, actor.food_name(well.accepted_type)])
	else:
		make_angry(actor, "Wrong food")
	queue_changed.emit()
	return true

func make_angry(actor: Node3D, reason: String) -> void:
	if actor.is_departing(): return
	for i in reservations.size():
		if reservations[i] == actor: reservations[i] = null
	if actor.slot_index >= 0: departing[actor.get_instance_id()] = actor.slot_index
	var route: Array[Vector3] = []
	# Step away from the table first, then follow the scene's route around its end.
	var side_offset: Vector3 = -layout_owner.global_basis.z.normalized() * 1.5
	route.append(actor.global_position + side_offset)
	for marker in escape_route: route.append(marker.global_position)
	actor.begin_anger(route, player_target, reason)
	event_reported.emit("#%d ANGRY: %s" % [actor.ticket, reason])
	queue_changed.emit()
