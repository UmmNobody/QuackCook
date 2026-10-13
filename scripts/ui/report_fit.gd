@tool
extends Control
@export var design_size := Vector2(820, 640)

func _ready() -> void:
	resized.connect(_fit)
	$Panel.minimum_size_changed.connect(_fit)
	_fit.call_deferred()

func _fit() -> void:
	var panel: Control = $Panel
	var extent := design_size.max(panel.get_combined_minimum_size())
	panel.size = extent
	var ratio := maxf(0.1, minf((size.x - 40.0) / extent.x, (size.y - 40.0) / extent.y))
	ratio = minf(ratio, 1.35)
	panel.scale = Vector2.ONE * ratio
	panel.position = (size - extent * ratio) * 0.5
