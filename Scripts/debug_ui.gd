extends CanvasLayer

var SHOW_DEBUG : bool = false

func _ready() -> void:
	if SHOW_DEBUG:
		show()
	else:
		hide()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("show_debug"):
		SHOW_DEBUG = !SHOW_DEBUG
		
		if SHOW_DEBUG:
			show()
		else:
			hide()

	if SHOW_DEBUG == false: return

	%FPS_label.text = "FPS: %s" % [Engine.get_frames_per_second()]