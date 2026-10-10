extends Node3D
## Scene wiring only. Day/session policy belongs to the GameManager autoload.

@export var serving_table_path: NodePath = ^"../../Kitchen/Stations/ServingTable"
@export var player_path: NodePath = ^"../../Actors/Player"
@export var auto_start_run: bool = true
@export var first_day: Resource
@export var difficulty: Resource

func _ready() -> void:
	var waiting: Array[Marker3D] = []
	var serving: Array[Marker3D] = []
	var escape: Array[Marker3D] = []
	var wells: Array[Node] = []
	for marker in $WaitingSlots.get_children():
		if marker is Marker3D: waiting.append(marker)
	for marker in $ServiceSlots.get_children():
		if marker is Marker3D: serving.append(marker)
	for marker in $EscapeRoute.get_children():
		if marker is Marker3D: escape.append(marker)
	var table := get_node(serving_table_path)
	for well in ["ChickenWell", "VegetableWell", "RiceWell", "WaterWell"]: wells.append(table.get_node(well))
	$Spawner.actor_parent = $Prisoners
	if not QueueManager.register_layout(self, waiting, $TrayPickupPoint, serving, wells, $ExitPoint, escape, get_node(player_path), $Spawner.max_active_prisoners): return
	if not GameManager.register_kitchen(self, $Spawner): return
	if auto_start_run: GameManager.start_registered_run.call_deferred(first_day, difficulty)
