extends Resource
## Difficulty relative to the first day's settings. Counts grow; foods/patience have bounds.

@export_range(0, 100) var extra_prisoners_per_day: int = 2
@export_range(0, 100) var extra_successes_per_day: int = 2
@export_range(1, 100) var days_per_maximum_food_increase: int = 2
@export_range(1, 100) var days_per_minimum_food_increase: int = 4
@export_range(1, 4) var minimum_foods_cap: int = 2
@export_range(0.0, 20.0) var patience_reduction_per_day: float = 2.0
@export_range(1.0, 300.0) var patience_floor: float = 30.0

func settings_for_day(first_day: Resource, day: int) -> Resource:
	var settings: Resource = first_day.duplicate()
	var steps := maxi(0, day - 1)
	settings.prisoner_count = first_day.prisoner_count + steps * maxi(0, extra_prisoners_per_day)
	settings.required_successes = mini(settings.prisoner_count, first_day.required_successes + steps * maxi(0, extra_successes_per_day))
	settings.maximum_foods = mini(4, first_day.maximum_foods + floori(float(steps) / maxi(1, days_per_maximum_food_increase)))
	var cap := maxi(first_day.minimum_foods, clampi(minimum_foods_cap, 1, 4))
	settings.minimum_foods = mini(settings.maximum_foods, mini(cap, first_day.minimum_foods + floori(float(steps) / maxi(1, days_per_minimum_food_increase))))
	# A deliberately easier custom first day must never get harder by gaining patience.
	settings.patience_seconds = maxf(minf(first_day.patience_seconds, maxf(1.0, patience_floor)), first_day.patience_seconds - steps * maxf(0.0, patience_reduction_per_day))
	return settings
