extends SceneTree
var checks := 0
var failures := 0
var stage: Node3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func solid(size: Vector3, point: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	stage.add_child(body)
	body.position = point
	return body
func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	solid(Vector3(40, 1, 40), Vector3(0,-0.5,0))
	for path in ["foods/chicken", "foods/carrot", "foods/cabbage", "foods/rice", "foods/bottle", "cookware/pan", "cookware/pot", "cookware/tray", "tools/knife"]:
		var prisoner = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
		stage.add_child(prisoner)
		prisoner.position = Vector3(0,0.05,1.7)
		var item = load("res://scenes/items/" + path + ".tscn").instantiate()
		stage.add_child(item)
		item.position = Vector3(0,0.1,0)
		await frames(45)
		var start: Vector3 = item.position
		prisoner.move_to_slot(-1, Vector3(0,0,-5))
		await frames(220)
		check(prisoner.position.z < -2, path + " does not block prisoner (z=%.2f)" % prisoner.position.z)
		check(item.position.distance_to(start) > 0.15, path + " is physically moved")
		check(prisoner.health == prisoner.max_health, "Pushing " + path + " does not deal damage")
		item.queue_free()
		prisoner.queue_free()
		await frames(4)
	# Frozen cookware must remain anchored, and a stationary queue member must
	# not shove objects just because they touch its capsule.
	var prisoner = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	stage.add_child(prisoner)
	prisoner.position = Vector3(0,0.05,1.7)
	var pot = load("res://scenes/items/cookware/pot.tscn").instantiate()
	stage.add_child(pot)
	pot.position = Vector3(0,0.1,0)
	pot.freeze = true
	var original: Vector3 = pot.position
	prisoner.state = prisoner.State.ANGRY_EXIT
	prisoner.escape_points = [Vector3(0,0,-5)] as Array[Vector3]
	await frames(160)
	check(pot.position == original, "Frozen/held/station cookware is not pushed")
	pot.queue_free()
	var wall := solid(Vector3(4,4,0.3), Vector3(0,2,-1))
	await frames(140)
	check(prisoner.position.z > -0.6, "Walls still stop the prisoner")
	wall.queue_free()
	prisoner.queue_free()
	await frames(3)
	var waiting = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	waiting.position = Vector3(0,0.05,0)
	stage.add_child(waiting)
	var follower = load("res://scenes/characters/prisoner/prisoner.tscn").instantiate()
	follower.position = Vector3(0,0.05,2)
	stage.add_child(follower)
	# QueueManager assigns the free slot behind the waiting prisoner, never a
	# destination beyond an occupied slot. Match that contract in this fixture.
	follower.move_to_slot(-1, Vector3(0,0,0.9))
	await frames(180)
	check(absf(waiting.position.z) < 0.03, "A follower moving into the next queue slot leaves the waiting prisoner in place")
	check(absf(follower.position.z - 0.9) < 0.03, "Follower stops at its assigned queue slot")
	stage.queue_free()
	await frames(3)
	print("Prisoner push checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
