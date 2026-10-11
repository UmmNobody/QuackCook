extends Resource
## Input for one service session. Future day progression supplies a new resource.

@export_range(1, 10000) var prisoner_count: int = 6
@export_range(0, 10000) var required_successes: int = 4
@export_range(1, 4) var minimum_foods: int = 1
@export_range(1, 4) var maximum_foods: int = 2
@export_range(1.0, 300.0) var patience_seconds: float = 45.0
@export_range(0.1, 30.0) var spawn_interval_min: float = 1.0
@export_range(0.1, 30.0) var spawn_interval_max: float = 3.0
@export_range(0.0, 120.0) var preparation_seconds: float = 30.0

func is_valid() -> bool:
	return prisoner_count > 0 and required_successes >= 0 and required_successes <= prisoner_count and minimum_foods >= 1 and maximum_foods <= 4 and minimum_foods <= maximum_foods and is_finite(patience_seconds) and patience_seconds >= 1.0 and is_finite(spawn_interval_min) and spawn_interval_min > 0.0 and is_finite(spawn_interval_max) and spawn_interval_max >= spawn_interval_min and is_finite(preparation_seconds) and preparation_seconds >= 0.0
