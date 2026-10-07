extends FoodItem

func cook() -> void:
	if  current_state == State.RAW:
		current_state = State.COOKED

func can_be_cooked() -> bool:
	return current_state == State.RAW and cook_progress < cook_duration

func cut():
	pass

func add_cook_progress(amount: float) -> void:
	if current_state == State.RAW:
		cook_progress += amount
		if cook_progress >= cook_duration:
			cook()
