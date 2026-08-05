extends Node


# profiling for performance issues
var _prof_run_next_calls := 0
var _prof_run_next_time_us := 0
var _prof_get_target_calls := 0
var _prof_get_target_time_us := 0
var _prof_get_uuid_calls := 0
var _prof_get_uuid_scan_fallbacks := 0
var _prof_timer_us
var _prof_report_interval := 1.0
var _prof_elapsed := 0.0

func _profiled_run_next_behavior(_behavior_data) -> void:
	var t0 = Time.get_ticks_usec()
	run_next_behavior(_behavior_data)
	_prof_run_next_time_us += Time.get_ticks_usec() - t0
	_prof_run_next_calls += 1

# DEBUG
static var behavior_status := {}   # { tag: "idle" | "running" | "done" | "error" }

func _set_behavior_status(tag: String, status: String) -> void:
	behavior_status[tag] = status

# ----------- TWEEN DATA -----------------------------------------------------------

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

# tag -> behavior dict, built once per scene_ready() instead of every
# run_next_behavior/_run_single_output/run_behavior_from_uuid call doing
# a linear scan through behaviorData - critical for objects with 300+
# behaviors, which turned every dispatch into an O(n) scan.
var _behavior_by_tag: Dictionary = {}

func _ready() -> void:
	EmulatorManager.finished_loading_level.connect(scene_ready)

func scene_ready() -> void:
	object_data = get_parent().object_data

	if !EmulatorManager.project_json_parsed["Behaviours"].has(get_parent().id): return

	behaviorData = EmulatorManager.project_json_parsed["Behaviours"][get_parent().id]

	_behavior_by_tag.clear()
	for behavior in behaviorData:
		_behavior_by_tag[behavior["tag"]] = behavior

	for behavior in behaviorData:
		var behavior_name = behavior.get("name", "no behavior name???")
		var is_root = behavior.get("root", 0)

		if is_root == 1:
			var method_name = behavior_name.replace(" ", "_").replace(".", "_")

			if has_method(method_name):
				GlobalBehaviorData.BehaviorStates[behavior["tag"]] = behavior["actions"]["active"]

				var result = call(method_name, behavior)
				if result is Dictionary:
					output_store[behavior["tag"]] = result
			else:
				Console.print_line("scene_ready | Warning: No method '%s' found" % method_name)

# ---------- BEHAVIOR DATA -------------------

var FRAME_EVENTS_TO_RUN = []

var TIMERS_TO_EXECUTE = []
var TIMER_ELAPSED : float = 0.0
var timer_elapsed: Dictionary = {}

var output_store: Dictionary = {}

# -------- HELPER BEHAVIOR FUNCTIONS -----------------

func run_behavior_from_uuid(UUID: String, chain_outputs: bool = false):
	if behaviorData == null:
		return null

	var behavior = _behavior_by_tag.get(UUID)
	if behavior == null:
		return null

	_set_behavior_status(UUID, "running")
	var behavior_name = behavior.get("name", "no behavior name???")
	var method_name = behavior_name.replace(" ", "_").replace(".", "_")

	if has_method(method_name):
		var result = call(method_name, behavior)
		if result is Dictionary:
			output_store[UUID] = result
		_set_behavior_status(UUID, "done")

		if chain_outputs:
			run_next_behavior(behavior)

		return result
	else:
		Console.print_line("run_behavior_from_uuid | Warning: No method '%s' found" % method_name)
		return null

func get_node_from_UUID(UUID : String):
	GlobalBehaviorData.prof_get_uuid_calls += 1

	if not is_inside_tree():
		return null

	var self_object = get_parent()
	if self_object != null and "id" in self_object and self_object.id == UUID:
		return self_object

	var cached = GlobalBehaviorData.uuid_registry.get(UUID)
	if cached != null and is_instance_valid(cached):
		return cached

	GlobalBehaviorData.prof_get_uuid_scan_fallbacks += 1
	for node in get_tree().get_nodes_in_group("HyperpadObject"):
		if node.id == UUID:
			GlobalBehaviorData.register_uuid(UUID, node)
			return node
	return null

func _behavior_repeats(behavior: Dictionary) -> bool:
	var actions: Dictionary = behavior.get("actions", {})
	return check_value_key(actions.get("repeat", {"valueKey": "$null", "value": true}))

func remove_timer(behavior: Dictionary) -> void:
	var tag = behavior["tag"]
	TIMERS_TO_EXECUTE.erase(behavior)
	timer_elapsed.erase(tag)

func _process(_delta: float) -> void:
	var timers_to_remove: Array = []

	for behavior in TIMERS_TO_EXECUTE:
		var tag = behavior["tag"]
		var wait_time = float(check_value_key(behavior["actions"]["waitTime"]))

		if wait_time == 0:
			run_next_behavior(behavior)

		if wait_time <= 0.0:
			continue

		timer_elapsed[tag] = timer_elapsed.get(tag, 0.0) + _delta

		if timer_elapsed[tag] >= wait_time:
			timer_elapsed[tag] -= wait_time
			run_next_behavior(behavior)

			if not _behavior_repeats(behavior):
				timers_to_remove.append(behavior)

	for behavior in timers_to_remove:
		remove_timer(behavior)

	for frame_event in FRAME_EVENTS_TO_RUN:
		var get_next_behavior_id: Array = frame_event.get("actions", {}).get("outputs", [])

		for id in get_next_behavior_id:
			var behavior = _behavior_by_tag.get(id)
			if behavior == null:
				continue

			var behavior_name = behavior.get("name", "no behavior name???")
			var method_name = behavior_name.replace(" ", "_").replace(".", "_")

			if has_method(method_name):
				var result = call(method_name, behavior)
				if result is Dictionary:
					output_store[behavior["tag"]] = result
			else:
				Console.print_line("FRAME_EVENTS_TO_RUN | Warning: No method '%s' found" % method_name)

func run_next_behavior(_behavior_data) -> void:
	var _t0 = Time.get_ticks_usec()
	GlobalBehaviorData.prof_run_next_calls += 1

	var get_next_behavior_id: Array = _behavior_data.get("actions", {}).get("outputs", [])

	for id in get_next_behavior_id:
		var behavior = _behavior_by_tag.get(id)
		if behavior == null:
			continue

		_set_behavior_status(id, "running")
		var behavior_name = behavior.get("name", "no behavior name???")
		var method_name = behavior_name.replace(" ", "_").replace(".", "_")

		if has_method(method_name):
			GlobalBehaviorData.prof_record_call(behavior_name, behavior.get("tag", "no tag"))
			var result = call(method_name, behavior)
			if result is Dictionary:
				output_store[behavior["tag"]] = result
			_set_behavior_status(id, "done")
		else:
			Console.print_line("run_next_behavior | Warning: No method '%s' found" % method_name)

	GlobalBehaviorData.prof_run_next_time_us += Time.get_ticks_usec() - _t0

func check_value_key(value_key_data):
	if value_key_data["valueKey"] == "$null":
		return value_key_data["value"]

	var behavior_tag = value_key_data["controlledBy"]
	var key = value_key_data["valueKey"]
	var source_outputs = output_store.get(behavior_tag, {})

	if source_outputs.has(key):
		return source_outputs[key]
	else:
		return 0.0

func get_action_field(actions: Dictionary, key: String, default_value = 0):
	if not actions.has(key):
		return default_value
	return check_value_key(actions[key])

func get_target_nodes(_behavior_data: Dictionary, object_key: String = "objectA") -> Array[Node2D]:
	var _t0 = Time.get_ticks_usec()
	GlobalBehaviorData.prof_get_target_calls += 1

	if not is_inside_tree():
		return []

	var actions: Dictionary = _behavior_data.get("actions", {})
	var targets: Array[Node2D] = []

	var groups: Array = _behavior_data.get("groups", [])
	if groups != null and not groups.is_empty():
		for tag in groups:
			for node in get_tree().get_nodes_in_group(tag):
				if node is Node2D:
					targets.append(node)
	else:
		var object_id = str(check_value_key(actions[object_key]))
		var node = get_node_from_UUID(object_id)
		if node != null:
			targets.append(node)

	GlobalBehaviorData.prof_get_target_time_us += Time.get_ticks_usec() - _t0
	return targets

# -------- BEHAVIOR FUNCTIONS ------------------------------------------------------------------------------------------

func Timer(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")
	if !TIMERS_TO_EXECUTE.has(_behavior_data):
		TIMERS_TO_EXECUTE.append(_behavior_data)

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Timer_v1_33(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	Timer(_behavior_data)

func Frame_Event(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")
	if !FRAME_EVENTS_TO_RUN.has(_behavior_data):
		FRAME_EVENTS_TO_RUN.append(_behavior_data)

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

	return { "dt": get_physics_process_delta_time() }

var _active_move_tweens: Dictionary = {}
func Move(_behavior_data) -> void:
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

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

	var all_tweens: Array[Tween] = []

	for node in target_nodes:
		GlobalBehaviorData.prof_move_unique_targets[node.get_instance_id()] = true
		var target_position = node.global_position + offset
		var node_key = node.get_instance_id()

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

		all_tweens.append(tween)

	for tween in all_tweens:
		await tween.finished

	for node in target_nodes:
		var node_key = node.get_instance_id()
		if _active_move_tweens.get(node_key) in all_tweens:
			_active_move_tweens.erase(node_key)

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Wait(_behavior_data) -> void:
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var wait_amount = float(check_value_key(_behavior_data["actions"]["waitTime"]))
	await get_tree().create_timer(wait_amount).timeout

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

# tag: 80B9B29E-CCC2-4A86-8EA7-9BCEE86A9010
func While_Touching(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})
	var object_id = str(check_value_key(actions["objectA"]))
	var object_to_touch = get_node_from_UUID(object_id) as RigidBody2D

	if object_to_touch == null:
		Console.print_line("While_Touching: objectA not found — skipping")
		return

	var touch_component = object_to_touch.get_node_or_null("touchingComponent")
	if touch_component == null:
		Console.print_line("While_Touching: no touchingComponent on %s" % object_id)
		return

	touch_component.set_while_touching_behavior(_behavior_data, self)

	_set_behavior_status(_behavior_data["tag"], "done")

	var parent = get_parent() as RigidBody2D
	var mouse_pos = parent.get_global_mouse_position()
	var screen_height = get_viewport().get_visible_rect().size.y
	var flipped_y = screen_height - mouse_pos.y

	return { "x": mouse_pos.x, "y": flipped_y, "dt": get_physics_process_delta_time() }

func Started_Touching(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	var actions = _behavior_data["actions"]
	var groups: Array = _behavior_data.get("groups", [])

	if groups == null or groups.is_empty():
		var object_id = str(check_value_key(actions["objectA"]))
		var object_to_touch = get_node_from_UUID(object_id) as RigidBody2D

		if object_to_touch == null:
			Console.print_line("Started_Touching: objectA not found (%s) — skipping" % object_id)
			return

		var touch_component = object_to_touch.get_node_or_null("touchingComponent")

		if touch_component == null:
			Console.print_line("Started_Touching: no touchingComponent on %s" % object_id)
			return

		touch_component.set_touch_behavior(_behavior_data, self)
	else:
		var matched_uuids: Array = []
		var all_scenes: Dictionary = EmulatorManager.project_json_parsed.get("Objects", {})

		for scene_name in all_scenes:
			var scene_objects: Dictionary = all_scenes[scene_name]
			for object_uuid in scene_objects:
				var object_def: Dictionary = scene_objects[object_uuid]
				var object_tags: Array = object_def.get("gameobjectdata", {}).get("tags", [])
				for tag in groups:
					if tag in object_tags:
						matched_uuids.append(object_uuid)
						break

		if matched_uuids.is_empty():
			Console.print_line("Started_Touching: no objects found with tags %s" % [groups])

		for object_uuid in matched_uuids:
			var node = get_node_from_UUID(object_uuid)
			if node == null:
				continue

			var touch_component = node.get_node_or_null("touchingComponent")
			if touch_component == null:
				Console.print_line("Started_Touching: no touchingComponent on %s" % object_uuid)
				continue

			touch_component.set_touch_behavior(_behavior_data, self)

	_set_behavior_status(_behavior_data["tag"], "done")

func Load_Level(_behavior_data) -> void:
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions = _behavior_data["actions"]

	if not actions.has("index"):
		Console.print_line("Warning: Load Level '%s' has no target scene configured — skipping" % _behavior_data.get("tag", "?"))
		run_next_behavior(_behavior_data)
		return

	var target_index = int(get_action_field(actions, "index", -1))
	var scene_type = int(get_action_field(actions, "sceneType", 0))

	var list_key = "Overlays" if scene_type == 1 else "Scenes"
	var candidates: Array = EmulatorManager.project_json_parsed[list_key]

	var target_name = ""
	for scene_entry in candidates:
		if int(scene_entry.get("index", -1)) == target_index:
			target_name = scene_entry["name"]
			break

	if target_name == "":
		Console.print_line("Warning: no %s found with index '%d'" % [list_key, target_index])
		run_next_behavior(_behavior_data)
		return

	Console.print_line("Loading scene: %s" % target_name)
	EmulatorManager.load_scene(target_name)

@export var SCALE_METERS_DIVISOR: float = 20.0
var _active_scale_tweens: Dictionary = {}
func Scale(_behavior_data: Dictionary) -> void:
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions = _behavior_data["actions"]
	var target_nodes = get_target_nodes(_behavior_data)

	if target_nodes.is_empty():
		Console.print_line("Scale: no valid target(s) found")
		run_next_behavior(_behavior_data)
		return

	var scale_type   = str(get_action_field(actions, "scaleType", "Percentage"))
	var duration     = float(get_action_field(actions, "duration", 0.0))
	var ease_action  = int(get_action_field(actions, "easeAction", 0))

	var all_tweens: Array[Tween] = []

	for node in target_nodes:
		var node_key = node.get_instance_id()

		if _active_scale_tweens.has(node_key):
			var existing: Tween = _active_scale_tweens[node_key]
			if is_instance_valid(existing) and existing.is_valid():
				existing.kill()

		var target_scale: Vector2
		if scale_type == "Meters":
			var sx = float(get_action_field(actions, "scaleXMeters", 0.0))
			var sy = float(get_action_field(actions, "scaleYMeters", 0.0))
			var delta = Vector2(sx / SCALE_METERS_DIVISOR, sy / SCALE_METERS_DIVISOR)
			target_scale = node.scale + delta
		else:
			var sx = float(get_action_field(actions, "scaleX", 0.0)) / 100.0
			var sy = float(get_action_field(actions, "scaleY", 0.0)) / 100.0
			target_scale = node.scale + Vector2(sx, sy)

		if duration <= 0.0:
			node.scale = target_scale
			continue

		var tween = create_tween()
		_active_scale_tweens[node_key] = tween

		var ease_pair = _get_ease(ease_action)
		tween.set_trans(ease_pair[0])
		tween.set_ease(ease_pair[1])

		tween.tween_property(node, "scale", target_scale, duration)

		all_tweens.append(tween)

	for tween in all_tweens:
		await tween.finished

	for node in target_nodes:
		var node_key = node.get_instance_id()
		if _active_scale_tweens.get(node_key) in all_tweens:
			_active_scale_tweens.erase(node_key)

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Scale_v2_7(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	Scale(_behavior_data)

func Show_Layer_v1_26(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})

	if not actions.has("index"):
		Console.print_line("Show_Layer_v1_26: no layer configured — skipping (tag %s)" % _behavior_data["tag"])
		_set_behavior_status(_behavior_data["tag"], "done")
		run_next_behavior(_behavior_data)
		return

	var what_layer = check_value_key(actions["index"])

	if what_layer is float:
		match what_layer:
			-1.0:
				var LayersUI = get_tree().get_first_node_in_group("LayersUI") as CanvasLayer
				LayersUI.get_child(1).show()

	if what_layer is String:
		for node in get_tree().get_nodes_in_group("hyperpadLayer"):
			if node.name == what_layer:
				node.show()

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

# tag: 658DD123-B5C1-4F1F-B4B1-0FF35D6BAA67
func Hide_Layer_v1_26(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})

	if not actions.has("index"):
		Console.print_line("Hide_Layer_v1_26: no layer configured — skipping (tag %s)" % _behavior_data["tag"])
		_set_behavior_status(_behavior_data["tag"], "done")
		run_next_behavior(_behavior_data)
		return

	var what_layer = check_value_key(actions["index"])

	if what_layer is float:
		match what_layer:
			-1.0:
				var LayersUI = get_tree().get_first_node_in_group("LayersUI") as CanvasLayer
				LayersUI.get_child(1).hide()

	if what_layer is String:
		for node in get_tree().get_nodes_in_group("hyperpadLayer"):
			if node.name == what_layer:
				node.hide()

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)


func Change_Colour(_behavior_data) -> void:
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions = _behavior_data["actions"]
	var target_nodes = get_target_nodes(_behavior_data)

	if target_nodes.is_empty():
		Console.print_line("Change_Colour: no valid target(s) found")
		run_next_behavior(_behavior_data)
		return

	var colour_hex = str(get_action_field(actions, "colourPicker", "#FFFFFFFF"))
	var target_colour = Color.html(colour_hex)
	var duration = float(get_action_field(actions, "duration", 0.0))

	if duration <= 0.0:
		for node in target_nodes:
			node.modulate = target_colour
		_set_behavior_status(_behavior_data["tag"], "done")
		run_next_behavior(_behavior_data)
		return

	var tween = create_tween()
	tween.set_parallel(true)
	for node in target_nodes:
		tween.tween_property(node, "modulate", target_colour, duration)

	await tween.finished

	if not is_instance_valid(self):
		return

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Destroy_Object(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var target_nodes = get_target_nodes(_behavior_data)

	for node in target_nodes:
		node.queue_free()

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Play_Sound_v1_21(_behavior_data) -> void:
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})
	var sound_path = str(actions.get("soundPath", ""))

	if sound_path == "":
		Console.print_line("Play_Sound_v1_21: no soundPath configured — skipping")
		run_next_behavior(_behavior_data)
		return

	var sound_file_name = sound_path.get_file()
	var base_path = "user://project/" + sound_path + "/" + sound_file_name

	var sound_source: AudioStream = null
	var ogg_path = base_path + ".ogg"
	var wav_path = base_path + ".wav"

	if FileAccess.file_exists(ogg_path):
		sound_source = AudioStreamOggVorbis.load_from_file(ogg_path)
	elif FileAccess.file_exists(wav_path):
		sound_source = AudioStreamWAV.load_from_file(wav_path)

	if sound_source == null:
		Console.print_line("Play_Sound_v1_21: could not load audio for '%s' (neither .ogg nor .wav found)" % sound_path)
		run_next_behavior(_behavior_data)
		return

	var audio_node := AudioStreamPlayer.new()
	add_child(audio_node)
	audio_node.stream = sound_source
	audio_node.pitch_scale = 1.0 + (float(get_action_field(actions, "pitch", 0.0)) / 100.0)
	audio_node.volume_db = float(get_action_field(actions, "volume", 100.0)) / 50
	audio_node.play()

	await audio_node.finished

	if is_instance_valid(audio_node):
		audio_node.queue_free()

	if not is_instance_valid(self):
		return

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)


func Play_Music_v1_21(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})
	var sound_path = str(actions.get("soundPath", ""))

	if sound_path == "":
		Console.print_line("Play_Music_v1_21: no soundPath configured — skipping")
		_set_behavior_status(_behavior_data["tag"], "done")
		run_next_behavior(_behavior_data)
		return

	var sound_file_name = sound_path.get_file()
	var base_path = "user://project/" + sound_path + "/" + sound_file_name

	var sound_source: AudioStream = null
	var ogg_path = base_path + ".ogg"
	var wav_path = base_path + ".wav"
	if FileAccess.file_exists(ogg_path):
		sound_source = AudioStreamOggVorbis.load_from_file(ogg_path)
	elif FileAccess.file_exists(wav_path):
		sound_source = AudioStreamWAV.load_from_file(wav_path)

	if sound_source == null:
		Console.print_line("Play_Music_v1_21: could not load audio for '%s'" % sound_path)
		_set_behavior_status(_behavior_data["tag"], "done")
		run_next_behavior(_behavior_data)
		return

	var root = get_tree().root
	var music_player = root.get_node_or_null("MusicPlayer")
	if not music_player:
		music_player = AudioStreamPlayer.new()
		music_player.name = "MusicPlayer"
		root.add_child(music_player)

	if music_player.playing:
		music_player.stop()

	music_player.stream = sound_source
	music_player.volume_db = float(get_action_field(actions, "volume", 100.0)) / 50.0
	music_player.stream.loop = bool(check_value_key(actions["loop"]))
	music_player.play()

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

var _execute_sequence_index: Dictionary = {}

func _run_single_output(target_tag: String) -> void:
	var behavior = _behavior_by_tag.get(target_tag)
	if behavior == null:
		return

	_set_behavior_status(target_tag, "running")
	var behavior_name = behavior.get("name", "no behavior name???")
	var method_name = behavior_name.replace(" ", "_").replace(".", "_")

	if has_method(method_name):
		var result = call(method_name, behavior)
		if result is Dictionary:
			output_store[target_tag] = result
		_set_behavior_status(target_tag, "done")
	else:
		Console.print_line("_run_single_output | Warning: No method '%s' found" % method_name)

func Execute_Sequence(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})
	var outputs: Array = actions.get("outputs", [])
	var sequence_type = str(get_action_field(actions, "sequenceType", "Sequential"))
	var self_tag = _behavior_data["tag"]

	if outputs.is_empty():
		Console.print_line("Execute_Sequence: no outputs configured — skipping")
		_set_behavior_status(self_tag, "done")
		return

	if sequence_type == "Random":
		var target_tag = outputs[randi() % outputs.size()]
		_run_single_output(target_tag)
	else:
		var current_index: int = _execute_sequence_index.get(self_tag, 0)
		current_index = current_index % outputs.size()

		var target_tag = outputs[current_index]
		_run_single_output(target_tag)

		_execute_sequence_index[self_tag] = (current_index + 1) % outputs.size()

	_set_behavior_status(self_tag, "done")

@export var MOVE_TO_OBJECT_ANCHOR_OFFSET_SCALE: float = 1.0

func _get_hyperpad_object_size(node: Node2D) -> Vector2:
	var collision_shape := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null and collision_shape.shape != null:
		var shape := collision_shape.shape
		if shape is RectangleShape2D:
			return (shape as RectangleShape2D).size * collision_shape.scale * node.scale
		elif shape is CircleShape2D:
			var diameter = (shape as CircleShape2D).radius * 2.0
			return Vector2(diameter, diameter) * collision_shape.scale * node.scale
		elif shape is CapsuleShape2D:
			var capsule := shape as CapsuleShape2D
			return Vector2(capsule.radius * 2.0, capsule.height) * collision_shape.scale * node.scale

	var sprite := node.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		return Vector2.ZERO
	return sprite.texture.get_size() * sprite.scale * node.scale

func Move_To_Object_v1_15(_behavior_data) -> void:
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})

	var object_a_id = str(check_value_key(actions["objectA"]))
	var object_b_id = str(check_value_key(actions["objectB"]))

	var node_a = get_node_from_UUID(object_a_id)
	var node_b = get_node_from_UUID(object_b_id)

	if node_a == null or node_b == null:
		Console.print_line("Move_To_Object_v1_15: objectA or objectB not found — skipping")
		run_next_behavior(_behavior_data)
		return

	var relative_a = Vector2(
		float(get_action_field(actions, "relativeAnchorA_x", 50.0)),
		100.0 - float(get_action_field(actions, "relativeAnchorA_y", 50.0))
	) / 100.0
	var relative_b = Vector2(
		float(get_action_field(actions, "relativeAnchorB_x", 50.0)),
		100.0 - float(get_action_field(actions, "relativeAnchorB_y", 50.0))
	) / 100.0

	var size_a: Vector2 = _get_hyperpad_object_size(node_a)
	var size_b: Vector2 = _get_hyperpad_object_size(node_b)

	var anchor_a_local = (relative_a - Vector2(0.5, 0.5)) * size_a
	var anchor_b_local = (relative_b - Vector2(0.5, 0.5)) * size_b

	var anchor_a_global = node_a.global_position + anchor_a_local
	var anchor_b_global = node_b.global_position + anchor_b_local

	var offset_a = Vector2(
		float(get_action_field(actions, "anchorA_x", 0.0)),
		float(get_action_field(actions, "anchorA_y", 0.0))
	) * MOVE_TO_OBJECT_ANCHOR_OFFSET_SCALE
	var offset_b = Vector2(
		float(get_action_field(actions, "anchorB_x", 0.0)),
		float(get_action_field(actions, "anchorB_y", 0.0))
	) * MOVE_TO_OBJECT_ANCHOR_OFFSET_SCALE

	var move_delta = (anchor_b_global + offset_b) - (anchor_a_global + offset_a)
	var target_position = node_a.global_position + move_delta

	var duration = float(get_action_field(actions, "duration", 0.0))

	if duration <= 0.0:
		node_a.global_position = target_position
	else:
		var tween = create_tween()
		tween.tween_property(node_a, "global_position", target_position, duration)
		await tween.finished

	if not is_instance_valid(self):
		return

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Move_To_Point(_behavior_data) -> void:
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})
	var target_nodes = get_target_nodes(_behavior_data)

	if target_nodes.is_empty():
		Console.print_line("Move_To_Point: no valid target(s) found")
		run_next_behavior(_behavior_data)
		return

	var screen_coordinates = bool(get_action_field(actions, "screenCoordinates", false))

	var move_x_field: Dictionary = actions.get("moveX", {})
	var is_chained = move_x_field.get("controlledBy", "self") != "self"

	var raw_x = float(get_action_field(actions, "moveX", 0.0))
	var raw_y = float(get_action_field(actions, "moveY", 0.0))

	var world_height = get_viewport().get_visible_rect().size.y
	var camera = get_viewport().get_camera_2d()
	if camera != null:
		world_height = get_viewport().get_visible_rect().size.y * camera.zoom.y

	var target_position: Vector2
	if screen_coordinates:
		target_position = Vector2(raw_x, raw_y)
	elif is_chained:
		var screen_height = get_viewport().get_visible_rect().size.y
		target_position = Vector2(raw_x, screen_height - raw_y)
	else:
		target_position = Vector2(raw_x * 30, world_height - (raw_y * 30))

	var duration = float(get_action_field(actions, "duration", 0.0))
	var ease_action = int(get_action_field(actions, "easeAction", 0))

	var all_tweens: Array[Tween] = []

	for node in target_nodes:
		if duration <= 0.0:
			node.global_position = target_position
			continue

		var tween = create_tween()
		var ease_pair = _get_ease(ease_action)
		tween.set_trans(ease_pair[0])
		tween.set_ease(ease_pair[1])
		tween.tween_property(node, "global_position", target_position, duration)
		all_tweens.append(tween)

	for tween in all_tweens:
		await tween.finished

	if not is_instance_valid(self):
		return

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func While_Colliding(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]
	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	# Get my own collision component (the object that has this behavior)
	var my_parent = get_parent()
	var my_component = my_parent.get_node_or_null("CollisionDetectionComponent")
	if my_component == null:
		Console.print_line("While_Colliding: missing CollisionDetectionComponent on self")
		run_next_behavior(_behavior_data)
		return

	# Register on MY component, not on the target's
	if not my_component.while_nodes_to_check.has(self):
		my_component.while_nodes_to_check[self] = []
	my_component.while_nodes_to_check[self].append(_behavior_data)

	_set_behavior_status(_behavior_data["tag"], "done")

func Collision_Event(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var target_nodes = get_target_nodes(_behavior_data)

	for node in target_nodes:
		var collisionComponent = node.get_node("CollisionDetectionComponent")
		if not collisionComponent.nodes_to_check.has(self):
			collisionComponent.nodes_to_check[self] = []
		collisionComponent.nodes_to_check[self].append(_behavior_data)

	_set_behavior_status(_behavior_data["tag"], "done")

# tag: 6BB98D4A-8FB0-4067-B5A4-AE9D871A203B
func Behaviour_On(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var behaviour_A_UUID = _behavior_data["actions"]["behaviourA"]
	if GlobalBehaviorData.BehaviorStates[behaviour_A_UUID] == false:
		GlobalBehaviorData.BehaviorStates[behaviour_A_UUID] = true

		for interpreter in get_tree().get_nodes_in_group("Interpreter"):
			interpreter.run_behavior_from_uuid(behaviour_A_UUID)

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

# tag: 3C91ABC7-9629-4EA7-94D5-9697CE04FB54
func Spawn_On_Point(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})
	var behavior_tag: String = _behavior_data["tag"]

	var object_id = str(check_value_key(actions["objectA"]))
	var original = get_node_from_UUID(object_id)

	if original == null:
		Console.print_line("Spawn_On_Point: objectA not found — skipping")
		run_next_behavior(_behavior_data)
		return

	var objects_alive_cap = int(get_action_field(actions, "objectsAlive", 20))
	var current_alive = _count_alive_clones(behavior_tag)

	if current_alive >= objects_alive_cap:
		if bool(get_action_field(actions, "recycle", false)):
			var oldest = _get_oldest_clone(behavior_tag)
			if oldest != null:
				oldest.queue_free()
				current_alive -= 1
		else:
			_set_behavior_status(_behavior_data["tag"], "done")
			run_next_behavior(_behavior_data)
			return

	var multiplier = int(get_action_field(actions, "multiplier", 1))
	var screen_coordinates = bool(get_action_field(actions, "screenCoordinates", false))

	var min_x = float(get_action_field(actions, "minAreaX", 0.0))
	var max_x = float(get_action_field(actions, "maxAreaX", 0.0))
	var min_y = float(get_action_field(actions, "minAreaY", 0.0))
	var max_y = float(get_action_field(actions, "maxAreaY", 0.0))

	if min_x > max_x:
		var tmp = min_x; min_x = max_x; max_x = tmp
	if min_y > max_y:
		var tmp = min_y; min_y = max_y; max_y = tmp

	var spread_variance = float(get_action_field(actions, "spreadVariance", 100.0)) / 100.0

	var world_height = get_viewport().get_visible_rect().size.y
	var camera = get_viewport().get_camera_2d()
	if camera != null:
		world_height = get_viewport().get_visible_rect().size.y * camera.zoom.y

	for i in range(max(multiplier, 1)):
		var rand_x = randf_range(min_x, max_x)
		var rand_y = randf_range(min_y, max_y)

		if spread_variance < 1.0:
			var center_x = (min_x + max_x) * 0.5
			var center_y = (min_y + max_y) * 0.5
			rand_x = lerp(center_x, rand_x, spread_variance)
			rand_y = lerp(center_y, rand_y, spread_variance)

		var spawn_position: Vector2
		if screen_coordinates:
			spawn_position = Vector2(rand_x, rand_y)
		else:
			spawn_position = Vector2(rand_x * 30, world_height - (rand_y * 30))

		var clone = original.duplicate(DUPLICATE_GROUPS | DUPLICATE_SIGNALS | DUPLICATE_SCRIPTS)
		clone.object_data = original.object_data
		clone.id = object_id
		original.get_parent().add_child(clone)
		clone.global_position = spawn_position
		clone.global_position.x += 35

		if not clone.is_in_group("HyperpadObject"):
			clone.add_to_group("HyperpadObject")

		clone.add_to_group("spawned_%s" % object_id)
		clone.add_to_group("spawned_by_%s" % behavior_tag)

		var clone_interpreter = clone.get_node_or_null("BehaviorInterpreter")
		if clone_interpreter != null and clone_interpreter.has_method("scene_ready"):
			clone_interpreter.scene_ready()

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func _count_alive_clones(behavior_tag: String) -> int:
	return get_tree().get_nodes_in_group("spawned_by_%s" % behavior_tag).size()

func _get_oldest_clone(behavior_tag: String) -> Node2D:
	var nodes = get_tree().get_nodes_in_group("spawned_by_%s" % behavior_tag)
	return nodes[0] if not nodes.is_empty() else null

func Add_To_Score(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})
	var target_nodes = get_target_nodes(_behavior_data)
	var increment = float(check_value_key(actions["increment"]))
	var is_infinite = bool(get_action_field(actions, "infinite", true))
	var max_score = float(get_action_field(actions, "maximumScore", 0.0))

	var reached_max := false

	for node in target_nodes:
		var label = node.get_node("Label")
		var current_value = float(label.text) if label.text.is_valid_float() else 0.0
		var new_value = current_value + increment

		if not is_infinite and new_value >= max_score:
			new_value = max_score
			reached_max = true

		if new_value == floor(new_value):
			label.text = str(int(new_value))
		else:
			label.text = str(new_value)

	_set_behavior_status(_behavior_data["tag"], "done")

	if is_infinite or reached_max:
		run_next_behavior(_behavior_data)

func If(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var condition = _behavior_data["actions"]["condition"]["value"]
	var valueA = get_action_field(_behavior_data["actions"], "valueA", 0)
	var valueB = get_action_field(_behavior_data["actions"], "valueB", 0)

	match condition:
		">=":
			if float(valueA) >= float(valueB):
				run_next_behavior(_behavior_data)
		"<=":
			if float(valueA) <= float(valueB):
				run_next_behavior(_behavior_data)
		">":
			if float(valueA) > float(valueB):
				run_next_behavior(_behavior_data)
		"<":
			if float(valueA) < float(valueB):
				run_next_behavior(_behavior_data)
		"=":
			if str(valueA) == str(valueB):
				run_next_behavior(_behavior_data)
		"!=":
			if str(valueA) != str(valueB):
				run_next_behavior(_behavior_data)

	_set_behavior_status(_behavior_data["tag"], "done")

func Get_Label(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var target_nodes = get_target_nodes(_behavior_data)
	var result_text := ""

	if target_nodes.is_empty():
		Console.print_line("Get_Label: no valid target(s) found")
	else:
		result_text = target_nodes[0].get_node("Label").text

	output_store[_behavior_data["tag"]] = {"text": result_text}

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

	return {"text": result_text}

var _broadcasting_keys: Dictionary = {}

func Broadcast_Message_v1_19(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var eventKey = str(get_action_field(_behavior_data["actions"], "eventKey", ""))

	if GlobalBehaviorData.Broadcasting.has(eventKey):
		_set_behavior_status(_behavior_data["tag"], "done")
		return

	GlobalBehaviorData.Broadcasting[eventKey] = true

	for receiver_tag in GlobalBehaviorData.Broadcasts:
		for entry in GlobalBehaviorData.Broadcasts[receiver_tag]:
			if entry["eventKey"] == eventKey:
				var interpreter = entry["interpreter"]
				if is_instance_valid(interpreter):
					interpreter.run_behavior_from_uuid(receiver_tag, true)

	GlobalBehaviorData.Broadcasting.erase(eventKey)

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Receive_Message_v1_19(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var eventKey = str(get_action_field(_behavior_data["actions"], "eventKey", ""))
	var tag = _behavior_data["tag"]

	if not GlobalBehaviorData.Broadcasts.has(tag):
		GlobalBehaviorData.Broadcasts[tag] = []

	var already_registered := false
	for entry in GlobalBehaviorData.Broadcasts[tag]:
		if entry["interpreter"] == self:
			already_registered = true
			entry["eventKey"] = eventKey
			break

	if not already_registered:
		GlobalBehaviorData.Broadcasts[tag].append({"eventKey": eventKey, "interpreter": self})

	_set_behavior_status(_behavior_data["tag"], "done")

func Set_Graphic_v1_26(_behavior_data):
	if !GlobalBehaviorData.BehaviorStates.has(_behavior_data["tag"]):
		GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] = _behavior_data["actions"]["active"]

	if GlobalBehaviorData.BehaviorStates[_behavior_data["tag"]] == false:
		return

	_set_behavior_status(_behavior_data["tag"], "running")

	var actions: Dictionary = _behavior_data.get("actions", {})
	var target_nodes = get_target_nodes(_behavior_data)

	if target_nodes.is_empty():
		Console.print_line("Set_Graphic_v1_26: no valid target(s) found")
		run_next_behavior(_behavior_data)
		return

	var graphic_path = str(actions.get("graphic", ""))

	if graphic_path == "":
		Console.print_line("Set_Graphic_v1_26: no graphic path configured — skipping")
		run_next_behavior(_behavior_data)
		return

	var full_path = TapAssetExtractor.get_asset_user_path(graphic_path)
	var image := Image.new()
	var err := image.load(full_path)

	if err != OK:
		Console.print_line("Set_Graphic_v1_26: failed to load image '%s' (error %s)" % [full_path, err])
		run_next_behavior(_behavior_data)
		return

	var new_texture := ImageTexture.create_from_image(image)

	for node in target_nodes:
		var sprite := node.get_node_or_null("Sprite2D") as Sprite2D
		if sprite == null:
			continue
		sprite.texture = new_texture

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)
