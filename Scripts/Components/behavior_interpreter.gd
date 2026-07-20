extends Node

var object_data
var behaviorData

func _ready() -> void:
	EmulatorManager.finished_loading_level.connect(scene_ready)

func scene_ready() -> void:
	object_data = get_parent().object_data

	if !EmulatorManager.project_json_parsed["Behaviours"].has(get_parent().id): return

	behaviorData = EmulatorManager.project_json_parsed["Behaviours"][get_parent().id]

	# running the roots only
	for behavior in behaviorData:
		var behavior_name = behavior.get("name", "no behavior name???")
		var is_root = behavior.get("root", 0)

		Console.print_line("'%s'" % behavior_name)

		if is_root == 1:
			var method_name = behavior_name.replace(" ", "_")

			if has_method(method_name):
				var result = call(method_name, behavior)
				if result is Dictionary:
					output_store[behavior["tag"]] = result
			else:
				Console.print_line("Warning: No method '%s' found" % method_name)

# ---------- BEHAVIOR DATA -------------------

var FRAME_EVENTS_TO_RUN = []

# stores each behavior's last-produced outputs: { behavior_tag: { output_name: value } }
var output_store: Dictionary = {}

# -------- HELPER BEHAVIOR FUNCTIONS -----------------

func _process(_delta: float) -> void:
	for frame_event in FRAME_EVENTS_TO_RUN:
		var get_next_behavior_id = frame_event["actions"]["outputs"] as Array

		for behavior in behaviorData:
			for id in get_next_behavior_id:
				if behavior["tag"] == id:

					var behavior_name = behavior.get("name", "no behavior name???")
					var method_name = behavior_name.replace(" ", "_")

					if has_method(method_name):
						var result = call(method_name, behavior)
						if result is Dictionary:
							output_store[behavior["tag"]] = result
					else:
						Console.print_line("Warning: No method '%s' found" % method_name)

func run_next_behavior(_behavior_data) -> void:
	var get_next_behavior_id = _behavior_data["actions"]["outputs"] as Array

	for behavior in behaviorData:
		for id in get_next_behavior_id:
			if behavior["tag"] == id:

				var behavior_name = behavior.get("name", "no behavior name???")
				var method_name = behavior_name.replace(" ", "_")

				if has_method(method_name):
					var result = call(method_name, behavior)
					if result is Dictionary:
						output_store[behavior["tag"]] = result
				else:
					Console.print_line("Warning: No method '%s' found" % method_name)

# Now reads stored output instead of re-calling the behavior.
func check_value_key(value_key_data):
	if value_key_data["valueKey"] == "$null":
		return value_key_data["value"]
	
	var behavior_tag = value_key_data["controlledBy"]
	var key = value_key_data["valueKey"]
	var source_outputs = output_store.get(behavior_tag, {})

	if source_outputs.has(key):
		return source_outputs[key]
	else:
		Console.print_line("Warning: no output '%s' from '%s' yet, using 0" % [key, behavior_tag])
		return 0.0

# -------- BEHAVIOR FUNCTIONS -----------------

func Frame_Event(_behavior_data):
	if !FRAME_EVENTS_TO_RUN.has(_behavior_data):
		FRAME_EVENTS_TO_RUN.append(_behavior_data)

	run_next_behavior(_behavior_data)

	return { "dt": get_physics_process_delta_time() }

func Move(_behavior_data) -> void:

	var what_to_move_id = _behavior_data["actions"]["objectA"]["value"]
	var node_to_move

	for node in get_tree().get_nodes_in_group("HyperpadObject"):
		if node.id == what_to_move_id:
			node_to_move = node

	var moveX = float(check_value_key(_behavior_data["actions"]["moveX"]))
	var moveY = float(check_value_key(_behavior_data["actions"]["moveY"]))

	var moveXRelative = float(check_value_key(_behavior_data["actions"]["moveX"]))
	var moveYRelative = float(check_value_key(_behavior_data["actions"]["moveY"]))

	node_to_move.global_position += Vector2(moveX * 25, -moveY * 25)

	run_next_behavior(_behavior_data)
