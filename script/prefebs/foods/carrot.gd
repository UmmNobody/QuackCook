extends FoodItem

func cook() -> void:
	pass

func can_be_cooked() -> bool:
	return false

func cut():
	if current_state == State.RAW:
		current_state = State.CUT

func add_cook_progress(amount: float) -> void:
	pass
