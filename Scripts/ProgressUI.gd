extends CanvasLayer

func set_progress(info : String, value : float):
	$ProgressBar.value = value
	$RichTextLabel.text = info
	
	if value >= 100:
		hide()
	else:
		show()
