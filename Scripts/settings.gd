extends Window

func _on_close_requested() -> void:
	hide()


func _on_apect_ratio_item_selected(index: int) -> void:
	match index:
		0:
			EmulatorManager.Aspect_Ratio = "4:3"
		1:
			EmulatorManager.Aspect_Ratio = "199:139"
