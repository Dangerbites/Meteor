extends Node

# ----------- TWEEN DATA -----------------------------------------------------------

# Best-effort mapping — verify against real hyperPad output before shipping.
# cocos2d-style ease actions are typically ordered: Linear, then
# Sine/Quad/Cubic/Quart/Quint/Expo/Circ/Elastic/Back/Bounce, each with
# In/Out/InOut variants.
const EASE_MAP = {
	0:  [Tween.TRANS_LINEAR,  Tween.EASE_IN_OUT],
	1:  [Tween.TRANS_QUAD,    Tween.EASE_IN],
	2:  [Tween.TRANS_QUAD,    Tween.EASE_OUT],
	3:  [Tween.TRANS_QUAD,    Tween.EASE_IN_OUT],
	4:  [Tween.TRANS_CUBIC,   Tween.EASE_IN],
	5:  [Tween.TRANS_CUBIC,   Tween.EASE_OUT],
	6:  [Tween.TRANS_CUBIC,   Tween.EASE_IN_OUT],
	7:  [Tween.TRANS_EXPO,    Tween.EASE_IN],
	8:  [Tween.TRANS_EXPO,    Tween.EASE_OUT],
	9:  [Tween.TRANS_EXPO,    Tween.EASE_IN_OUT],
	10: [Tween.TRANS_SINE,    Tween.EASE_IN],
	11: [Tween.TRANS_SINE,    Tween.EASE_OUT],
	12: [Tween.TRANS_SINE,    Tween.EASE_IN_OUT],
	13: [Tween.TRANS_BACK,    Tween.EASE_IN],
	14: [Tween.TRANS_BACK,    Tween.EASE_OUT],
	15: [Tween.TRANS_BACK,    Tween.EASE_IN_OUT],
	16: [Tween.TRANS_BOUNCE,  Tween.EASE_IN],
	17: [Tween.TRANS_BOUNCE,  Tween.EASE_OUT],
	18: [Tween.TRANS_BOUNCE,  Tween.EASE_IN_OUT],
	19: [Tween.TRANS_ELASTIC, Tween.EASE_IN],
	20: [Tween.TRANS_ELASTIC, Tween.EASE_OUT],
	21: [Tween.TRANS_ELASTIC, Tween.EASE_IN_OUT],
}

func _get_ease(ease_action: int) -> Array:
	return EASE_MAP.get(ease_action, [Tween.TRANS_LINEAR, Tween.EASE_IN_OUT])

# ------------------------------------------------------------------------------

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
				Console.print_line("scene_ready | Warning: No method '%s' found" % method_name)

# ---------- BEHAVIOR DATA -------------------

var FRAME_EVENTS_TO_RUN = []

var TIMERS_TO_EXECUTE = []
var TIMER_ELAPSED : float = 0.0
var timer_elapsed: Dictionary = {} # { behavior_tag: float }

# stores each behavior's last-produced outputs: { behavior_tag: { output_name: value } }
var output_store: Dictionary = {}

# -------- HELPER BEHAVIOR FUNCTIONS -----------------

func get_node_from_UUID(UUID : String):
	for node in get_tree().get_nodes_in_group("HyperpadObject"):
		if node.id == UUID:
			return node
	
	return null

func _behavior_repeats(behavior: Dictionary) -> bool:
	# adjust this to whatever field actually marks a one-shot vs repeating timer
	# e.g. if your hyperPad data has a "repeat" or "loop" input on Timer behaviors
	return check_value_key(behavior["actions"].get("repeat", {"valueKey": "$null", "value": true}))

func remove_timer(behavior: Dictionary) -> void:
	var tag = behavior["tag"]
	TIMERS_TO_EXECUTE.erase(behavior)
	timer_elapsed.erase(tag) # 

func _process(_delta: float) -> void:

	# TIMER BHEAVIRO
	var timers_to_remove: Array = []

	for behavior in TIMERS_TO_EXECUTE:
		var tag = behavior["tag"]
		var wait_time = float(check_value_key(behavior["actions"]["waitTime"]))

		if wait_time == 0:
			run_next_behavior(behavior)
			#print(wait_time)

		if wait_time <= 0.0:
			continue # avoid div-by-zero / instant-fire garbage

		timer_elapsed[tag] = timer_elapsed.get(tag, 0.0) + _delta

		if timer_elapsed[tag] >= wait_time:
			timer_elapsed[tag] -= wait_time
			run_next_behavior(behavior)
			print(wait_time)

			if not _behavior_repeats(behavior):
				timers_to_remove.append(behavior)

	for behavior in timers_to_remove:
		remove_timer(behavior)


	# FRAME EVENT BEHAVIOR
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
						Console.print_line("FRAME_EVENTS_TO_RUN | Warning: No method '%s' found" % method_name)

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
					Console.print_line("run_next_behavior | Warning: No method '%s' found" % method_name)

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
		Console.print_line("check_value_key | Warning: no output '%s' from '%s' yet, using 0" % [key, behavior_tag])
		return 0.0

func get_action_field(actions: Dictionary, key: String, default_value = 0):
	if not actions.has(key):
		return default_value
	return check_value_key(actions[key])

# Returns an array of Node2D objects to act upon.
# If the behaviour has a "groups" array, collect every node from those groups.
# Otherwise, fall back to the single object specified by the "objectA" action field.
func get_target_nodes(_behavior_data: Dictionary, object_key: String = "objectA") -> Array[Node2D]:
	var actions = _behavior_data["actions"]
	var targets: Array[Node2D] = []

	# Group mode
	if _behavior_data.has("groups") and not _behavior_data["groups"].is_empty():
		var tags_array = _behavior_data["groups"]
		for tag in tags_array:
			for node in get_tree().get_nodes_in_group(tag):
				if node is Node2D:
					targets.append(node)
	else:
		# Single object mode
		var object_id = check_value_key(actions[object_key])
		var node = get_node_from_UUID(object_id)
		if node != null:
			targets.append(node)

	return targets

# -------- BEHAVIOR FUNCTIONS ------------------------------------------------------------------------------------------

func Timer(_behavior_data):
	if !TIMERS_TO_EXECUTE.has(_behavior_data):
		TIMERS_TO_EXECUTE.append(_behavior_data)

	run_next_behavior(_behavior_data)

func Frame_Event(_behavior_data):
	if !FRAME_EVENTS_TO_RUN.has(_behavior_data):
		FRAME_EVENTS_TO_RUN.append(_behavior_data)

	run_next_behavior(_behavior_data)

	return { "dt": get_physics_process_delta_time() }

var _active_move_tweens: Dictionary = {}   # { node_instance_id: Tween }
func Move(_behavior_data) -> void:
	var actions = _behavior_data["actions"]
	var target_nodes = get_target_nodes(_behavior_data)

	if target_nodes.is_empty():
		Console.print_line("Move: no valid target(s) found")
		run_next_behavior(_behavior_data)
		return

	var move_x = float(get_action_field(actions, "moveX", 0))
	var move_y = float(get_action_field(actions, "moveY", 0))
	var duration = float(get_action_field(actions, "duration", 0))
	var ease_action = int(get_action_field(actions, "easeAction", 0))
	var interrupt = bool(get_action_field(actions, "interruptMove", true))

	var offset = Vector2(move_x * 30, -move_y * 30)

	# We'll create a tween for each node and collect their finished signals
	var all_tweens: Array[Tween] = []

	for node in target_nodes:
		var target_position = node.global_position + offset
		var node_key = node.get_instance_id()

		# Handle existing tween (interrupt / wait)
		if _active_move_tweens.has(node_key):
			var existing: Tween = _active_move_tweens[node_key]
			if is_instance_valid(existing) and existing.is_valid():
				if interrupt:
					existing.kill()
				else:
					await existing.finished

		if duration <= 0.0:
			node.global_position = target_position
			continue

		var tween = create_tween()
		_active_move_tweens[node_key] = tween

		var ease_pair = _get_ease(ease_action)
		tween.set_trans(ease_pair[0])
		tween.set_ease(ease_pair[1])

		tween.tween_property(node, "global_position", target_position, duration)

		# Store tween to wait for later
		all_tweens.append(tween)

	# Wait for all tweens to finish before continuing
	for tween in all_tweens:
		await tween.finished

	# Cleanup – remove finished tweens from the dictionary
	for node in target_nodes:
		var node_key = node.get_instance_id()
		if _active_move_tweens.get(node_key) in all_tweens:
			_active_move_tweens.erase(node_key)

	run_next_behavior(_behavior_data)

func Wait(_behavior_data) -> void:
	var wait_amount = float(check_value_key(_behavior_data["actions"]["waitTime"]))
	await get_tree().create_timer(wait_amount).timeout
	run_next_behavior(_behavior_data)

func Started_Touching(_behavior_data):
	var actions = _behavior_data["actions"]

	if _behavior_data["groups"] == []: # not looking for tags
		var object_id = check_value_key(actions["objectA"])
		var object_to_touch = get_node_from_UUID(object_id) as RigidBody2D
		var touch_component = object_to_touch.get_node("touchingComponent")

		if touch_component == null:
			Console.print_line("Started_Touching: no touchingComponent on %s" % object_id)
			return

		touch_component.set_touch_behavior(_behavior_data, self)
	else: # looking for tags
		var tags_array = _behavior_data["groups"]
		for tag in tags_array:
			for node in get_tree().get_nodes_in_group(tag):
				var touch_component = node.get_node("touchingComponent")
				touch_component.set_touch_behavior(_behavior_data, self)
