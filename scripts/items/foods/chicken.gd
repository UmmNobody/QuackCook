extends FoodItem

func cook() -> void:
	if  current_state == State.CUT:
		current_state = State.COOKED

func can_be_cooked() -> bool:
	return current_state == State.CUT and cook_progress < cook_duration

func cut():
	if current_state != State.RAW:
		return
	current_state = State.CUT
	# Knife collisions run during physics queries; add the second body afterwards.
	_spawn_cut_piece.call_deferred(get_parent(), global_transform)

func _spawn_cut_piece(spawn_parent: Node, cut_transform: Transform3D) -> void:
	if not is_instance_valid(spawn_parent) or not spawn_parent.is_inside_tree():
		return
	var piece := (load("res://scenes/items/foods/chicken.tscn") as PackedScene).instantiate() as FoodItem
	piece.current_state = State.CUT
	piece.cook_duration = cook_duration
	piece.burn_grace_seconds = burn_grace_seconds
	spawn_parent.add_child(piece)
	# Leave enough room for both collision shapes, so the pieces do not overlap.
	cut_transform.origin += cut_transform.basis.x.normalized() * 0.7
	piece.global_transform = cut_transform

func add_cook_progress(amount: float) -> void:
	if current_state == State.CUT:
		cook_progress += amount
		if cook_progress >= cook_duration:
			cook()
