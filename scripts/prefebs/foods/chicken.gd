extends FoodItem

func cook() -> void:
	if  current_state == State.CUT:
		current_state = State.COOKED

func can_be_cooked() -> bool:
	return current_state == State.CUT and cook_progress < cook_duration

func cut():
	if current_state == State.RAW:
		current_state = State.CUT

func add_cook_progress(amount: float) -> void:
	if current_state == State.CUT:
		cook_progress += amount
		if cook_progress >= cook_duration:
			cook()
