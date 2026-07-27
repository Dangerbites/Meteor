extends Node

var started_touching_to_trigger : Dictionary = {}

# Separate from started_touching_to_trigger: this fires every frame
# while held down, not once on initial click - keyed the same way
# (interpreter node -> Array of behavior_datas) so multiple While
# Touching behaviors on the same object all get registered correctly.
var while_touching_to_trigger : Dictionary = {}

var hovering : bool = false
var pressing : bool = false

func set_touch_behavior(_behavior_data, _node : Node) -> void:
	if not started_touching_to_trigger.has(_node):
		started_touching_to_trigger[_node] = []

	var existing_entries: Array = started_touching_to_trigger[_node]
	var behavior_tag = _behavior_data.get("tag", null)

	for existing in existing_entries:
		if existing.get("tag", null) == behavior_tag:
			return

	existing_entries.append(_behavior_data)

func set_while_touching_behavior(_behavior_data, _node : Node) -> void:
	if not while_touching_to_trigger.has(_node):
		while_touching_to_trigger[_node] = []

	var existing_entries: Array = while_touching_to_trigger[_node]
	var behavior_tag = _behavior_data.get("tag", null)

	for existing in existing_entries:
		if existing.get("tag", null) == behavior_tag:
			return

	existing_entries.append(_behavior_data)

func _ready() -> void:
	get_parent().input_pickable = true
	get_parent().mouse_entered.connect(mouse_enter)
	get_parent().mouse_exited.connect(mouse_exit)

func mouse_enter():
	hovering = true

func mouse_exit():
	hovering = false
	# If the pointer leaves the object while still held, stop treating it
	# as "being touched" - otherwise While Touching would keep firing for
	# an object the pointer isn't over anymore.
	pressing = false

func _input(_event: InputEvent) -> void:
	if hovering:
		if Input.is_action_just_pressed("left_click"):
			pressing = true

			for key in started_touching_to_trigger:
				for behavior_data in started_touching_to_trigger[key]:
					key.run_next_behavior(behavior_data)

	if Input.is_action_just_released("left_click"):
		pressing = false

func _process(_delta: float) -> void:
	if not pressing:
		return

	var parent = get_parent() as Node2D

	for key in while_touching_to_trigger:
		for behavior_data in while_touching_to_trigger[key]:
			var mouse_pos = parent.get_global_mouse_position()
			var screen_height = get_viewport().get_visible_rect().size.y

			# Flip to Y-up, origin bottom-left: Godot's global_mouse_position
			# is Y-down from the top-left. screen_height - mouse_pos.y puts
			# (0,0) at the bottom and makes +Y point up, matching
			# hyperPad/cocos2d's own convention (same flip already confirmed
			# correct in Move_To_Object's relativeAnchor handling).
			var flipped_y = screen_height - mouse_pos.y

			key.output_store[behavior_data["tag"]] = {
				"x": mouse_pos.x,
				"y": flipped_y,
				"dt": _delta,
			}
			key.run_next_behavior(behavior_data)
