extends Cookware
class_name Pot

func can_accept_food(food: FoodItem) -> bool:
	if current_food != null or food == null:
		return false
	# เช็กกลุ่ม Boilable แทน Fryable
	return food.is_in_group("Boilable") and food.can_be_cooked()
