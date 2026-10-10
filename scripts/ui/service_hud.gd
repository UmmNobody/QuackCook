extends CanvasLayer

func _process(_delta: float) -> void:
	var status := "Kitchen ready"
	if GameManager.state == GameManager.State.PREPARING:
		status = "DAY %d   /   Prepare the kitchen\nKitchen opens in %d s — press the wall button to open now" % [GameManager.current_day, ceili(GameManager.preparation_remaining)]
	elif GameManager.state == GameManager.State.SERVING:
		var report := GameManager.get_service_summary()
		status = "DAY %d   /   Served %d of %d required\nArrived %d / %d" % [GameManager.current_day, report.served, report.required, report.spawned, report.total]
		if report.can_close: status += "   /   Ready to close"
	$Status.text = status
