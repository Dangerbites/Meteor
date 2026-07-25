extends Node

# DEBUG
static var behavior_status := {}   # { tag: "idle" | "running" | "done" | "error" }

# --- TUNABLE ---
# "Scale by" behaviors in "Meters" mode store raw values like -200/-100 that
# are clearly not meant to be used as literal Vector2 scale multipliers
# (Godot scale of 1.0 == 100%; -200 would flip AND balloon the node).
# Treating "Meters" mode as a RELATIVE delta (matching the "Scale by" alias,
# not "Scale to") and dividing the raw value by this constant to turn it
# into a fractional change against the node's current scale. Adjust this
# until a Scale-by-Meters behavior visually matches what hyperPad shows.
# Bigger divisor = smaller/slower visual change per unit of raw value.

func _set_behavior_status(tag: String, status: String) -> void:
	behavior_status[tag] = status

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
			var method_name = behavior_name.replace(" ", "_").replace(".", "_")

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
	var actions: Dictionary = behavior.get("actions", {})
	return check_value_key(actions.get("repeat", {"valueKey": "$null", "value": true}))

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
		var get_next_behavior_id: Array = frame_event.get("actions", {}).get("outputs", [])

		for behavior in behaviorData:
			for id in get_next_behavior_id:
				if behavior["tag"] == id:

					var behavior_name = behavior.get("name", "no behavior name???")
					var method_name = behavior_name.replace(" ", "_").replace(".", "_")

					if has_method(method_name):
						var result = call(method_name, behavior)
						if result is Dictionary:
							output_store[behavior["tag"]] = result
					else:
						Console.print_line("FRAME_EVENTS_TO_RUN | Warning: No method '%s' found" % method_name)

func run_next_behavior(_behavior_data) -> void:
	var get_next_behavior_id: Array = _behavior_data.get("actions", {}).get("outputs", [])

	for behavior in behaviorData:
		for id in get_next_behavior_id:
			if behavior["tag"] == id:
				_set_behavior_status(id, "running")
				var behavior_name = behavior.get("name", "no behavior name???")
				var method_name = behavior_name.replace(" ", "_").replace(".", "_")

				if has_method(method_name):
					var result = call(method_name, behavior)
					if result is Dictionary:
						output_store[behavior["tag"]] = result
					_set_behavior_status(id, "done")
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
	var actions: Dictionary = _behavior_data.get("actions", {})
	var targets: Array[Node2D] = []

	# Group mode — .get() with a typed default avoids a Nil leaking through
	# when "groups" is absent, or explicitly stored as null, in the data.
	var groups: Array = _behavior_data.get("groups", [])
	if groups != null and not groups.is_empty():
		for tag in groups:
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
	_set_behavior_status(_behavior_data["tag"], "running")
	if !TIMERS_TO_EXECUTE.has(_behavior_data):
		TIMERS_TO_EXECUTE.append(_behavior_data)

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Frame_Event(_behavior_data):
	_set_behavior_status(_behavior_data["tag"], "running")
	if !FRAME_EVENTS_TO_RUN.has(_behavior_data):
		FRAME_EVENTS_TO_RUN.append(_behavior_data)

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

	return { "dt": get_physics_process_delta_time() }

var _active_move_tweens: Dictionary = {}   # { node_instance_id: Tween }
func Move(_behavior_data) -> void:
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

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Wait(_behavior_data) -> void:
	_set_behavior_status(_behavior_data["tag"], "running")

	var wait_amount = float(check_value_key(_behavior_data["actions"]["waitTime"]))
	await get_tree().create_timer(wait_amount).timeout

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Started_Touching(_behavior_data):
	var actions = _behavior_data["actions"]

	# .get() with a typed default instead of raw bracket access — a missing
	# or explicitly-null "groups" key used to silently produce Nil here,
	# which then blew up as a Nil -> Array assignment downstream.
	var groups: Array = _behavior_data.get("groups", [])

	if groups == null or groups.is_empty(): # not looking for tags
		var object_id = check_value_key(actions["objectA"])
		var object_to_touch = get_node_from_UUID(object_id) as RigidBody2D
		var touch_component = object_to_touch.get_node("touchingComponent")

		if touch_component == null:
			Console.print_line("Started_Touching: no touchingComponent on %s" % object_id)
			return

		touch_component.set_touch_behavior(_behavior_data, self)
	else: # looking for tags
		# hyperPad group membership lives in project_json_parsed["Objects"]
		# (per-scene dict of UUID -> object def, tags at gameobjectdata.tags)
		# — it is NOT the same thing as Godot's get_tree() groups. Nothing
		# calls add_to_group() from that data, so get_nodes_in_group() would
		# always return empty here, silently dropping any behavior that
		# targets objects by tag instead of by direct UUID. Resolve tag
		# membership from the parsed JSON instead, the same way
		# get_node_from_UUID() already looks objects up by UUID.
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

			var touch_component = node.get_node("touchingComponent")
			if touch_component == null:
				Console.print_line("Started_Touching: no touchingComponent on %s" % object_uuid)
				continue

			touch_component.set_touch_behavior(_behavior_data, self)

	_set_behavior_status(_behavior_data["tag"], "done")

func Load_Level(_behavior_data) -> void:
	_set_behavior_status(_behavior_data["tag"], "running")

	var actions = _behavior_data["actions"]

	if not actions.has("index"):
		Console.print_line("Warning: Load Level '%s' has no target scene configured — skipping" % _behavior_data.get("tag", "?"))
		run_next_behavior(_behavior_data)
		return

	var target_index = int(get_action_field(actions, "index", -1))
	var scene_type = int(get_action_field(actions, "sceneType", 0)) # 0 = Scenes, 1 = Overlays (unverified)

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
var _active_scale_tweens: Dictionary = {}   # { node_instance_id: Tween }
func Scale(_behavior_data: Dictionary) -> void:
	_set_behavior_status(_behavior_data["tag"], "running")

	var actions = _behavior_data["actions"]
	var target_nodes = get_target_nodes(_behavior_data)

	if target_nodes.is_empty():
		Console.print_line("Scale: no valid target(s) found")
		run_next_behavior(_behavior_data)
		return

	# Read action fields – use get_action_field which handles $null / linked values
	var scale_type   = str(get_action_field(actions, "scaleType", "Percentage"))
	var duration     = float(get_action_field(actions, "duration", 0.0))
	var ease_action  = int(get_action_field(actions, "easeAction", 0))
	# transformSpeed is ignored for now (same as Move)

	# Interrupt handling – reuse the same pattern as Move
	var all_tweens: Array[Tween] = []

	for node in target_nodes:
		var node_key = node.get_instance_id()

		# Stop existing scale tween if requested (here we always interrupt to match Move's default)
		if _active_scale_tweens.has(node_key):
			var existing: Tween = _active_scale_tweens[node_key]
			if is_instance_valid(existing) and existing.is_valid():
				existing.kill()   # interrupt previous animation

		# Determine the target scale per-node, since "Meters" mode is
		# relative to each node's own current scale (this is a "Scale BY",
		# not a "Scale TO" — per the JSON's "alias": "Scale by").
		var target_scale: Vector2
		if scale_type == "Meters":
			var sx = float(get_action_field(actions, "scaleXMeters", 0.0))
			var sy = float(get_action_field(actions, "scaleYMeters", 0.0))
			var delta = Vector2(sx / SCALE_METERS_DIVISOR, sy / SCALE_METERS_DIVISOR)
			target_scale = node.scale + delta
		else:  # Percentage (default) — also relative, matching "Scale by"
			var sx = float(get_action_field(actions, "scaleX", 0.0)) / 100.0
			var sy = float(get_action_field(actions, "scaleY", 0.0)) / 100.0
			target_scale = node.scale + Vector2(sx, sy)

		# If duration is zero or negative, apply instantly
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

	# Wait for all tweens to finish before triggering next behaviour
	for tween in all_tweens:
		await tween.finished

	# Clean up the dictionary
	for node in target_nodes:
		var node_key = node.get_instance_id()
		if _active_scale_tweens.get(node_key) in all_tweens:
			_active_scale_tweens.erase(node_key)

	_set_behavior_status(_behavior_data["tag"], "done")
	run_next_behavior(_behavior_data)

func Scale_v2_7(_behavior_data):
	Scale(_behavior_data)