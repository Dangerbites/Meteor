extends Node

var started_touching_to_trigger = {}

var hovering : bool = false

func set_touch_behavior(_behavior_data, _node : Node):
	started_touching_to_trigger[_node] = _behavior_data

func _ready() -> void:
	get_parent().input_pickable = true
	get_parent().mouse_entered.connect(mouse_enter)
	get_parent().mouse_exited.connect(mouse_exit)

func mouse_enter():
	hovering = true

func mouse_exit():
	hovering = false

func _input(_event: InputEvent) -> void:
	if hovering:
		if Input.is_action_just_pressed("left_click"):
			print("Touched ",get_parent().name)
			#print(started_touching_to_trigger)
			#print(get_parent().get_groups())

			for key in started_touching_to_trigger:
				key.run_next_behavior(started_touching_to_trigger[key])