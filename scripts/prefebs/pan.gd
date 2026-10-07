extends Cookware
class_name Pan

func can_accept_food(food: FoodItem) -> bool:
	if current_food != null or food == null:
		return false
	return food.is_in_group("Fryable") and food.can_be_cooked()
