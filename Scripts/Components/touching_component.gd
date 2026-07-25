extends Node

# Was: Dictionary keyed by interpreter node -> single behavior_data.
# That meant a second Started_Touching behavior targeting the same object
# would silently overwrite the first one's entry, since both share the same
# interpreter instance as the key. Now each key maps to an Array of
# behavior_datas, so every Started_Touching behavior registered against
# this component gets triggered on click, not just the last one to run.
var started_touching_to_trigger : Dictionary = {}

var hovering : bool = false

func set_touch_behavior(_behavior_data, _node : Node) -> void:
	if not started_touching_to_trigger.has(_node):
		started_touching_to_trigger[_node] = []
	started_touching_to_trigger[_node].append(_behavior_data)

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
			#print("Touched ", get_parent().name)

			for key in started_touching_to_trigger:
				for behavior_data in started_touching_to_trigger[key]:
					key.run_next_behavior(behavior_data)