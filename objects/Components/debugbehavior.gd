extends Node

var interpreter
var show_window := false

func _ready() -> void:
	interpreter = get_parent()
	# We'll draw inside _process, no signal needed.

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next"):   # Tab toggles
		show_window = not show_window

func _process(_delta: float) -> void:
	if not show_window:
		return

	# --- Robust null checks ---
	if not is_instance_valid(interpreter):
		return                              # parent is gone or not ready
	if not interpreter.has_method("_set_behavior_status"):
		return
	if not ("behaviorData" in interpreter):
		return

	# --- ImGui drawing ---
	if not ImGui.Begin("Behaviour Tree Debug"):
		ImGui.End()
		return

	var raw_data = interpreter.behaviorData
	if raw_data == null or not (raw_data is Array) or raw_data.is_empty():
		ImGui.Text("No behaviour data loaded.")
		ImGui.End()
		return

	var data: Array = raw_data

	# Access the static status dictionary via the script resource
	var script = interpreter.get_script()
	var status: Dictionary = script.behavior_status if script else {}

	ImGui.Text("Behaviour Tree  (green=running, yellow=done, red=error)")
	ImGui.Separator()

	var drawn := []
	for behavior in data:
		if behavior.get("root", 0) == 1:
			_draw_tree(behavior, data, status, drawn)

	ImGui.End()

func _draw_tree(behavior: Dictionary, all_data: Array, status: Dictionary, drawn: Array) -> void:
	var tag = behavior["tag"]
	if tag in drawn:
		return
	drawn.append(tag)

	var name = behavior.get("name", "???")
	var stat = status.get(tag, "idle")

	var color := Color.WHITE
	match stat:
		"running": color = Color.GREEN
		"done":    color = Color.YELLOW
		"error":   color = Color.RED

	ImGui.PushStyleColor(ImGui.Col_Text, color)

	var children = _get_children(behavior, all_data)
	var flags = 0
	if children.is_empty():
		flags = ImGui.TreeNodeFlags_Leaf | ImGui.TreeNodeFlags_NoTreePushOnOpen

	# "##%s" (tag) is an invisible ID suffix — ImGui hashes labels for widget
	# identity, so two nodes with the same visible text (e.g. same name/status)
	# would otherwise collide and trigger the "conflicting ID" warning.
	var is_open = ImGui.TreeNodeEx("%s [%s]##%s" % [name, stat, tag], flags)

	ImGui.PopStyleColor()

	if ImGui.IsItemHovered():
		ImGui.BeginTooltip()
		ImGui.Text("Tag: %s" % tag)
		ImGui.Text("Status: %s" % stat)
		ImGui.EndTooltip()

	# Copy button — grabs tag + name so you can paste straight into a new
	# behavior function. "##copy_%s" keeps the ID unique per tag, same as
	# the tree node above; empty label + suffix keeps it visually compact.
	ImGui.SameLine()
	#if ImGui.SmallButton("Copy##copy_%s" % tag):
	#	var method_name = name.replace(" ", "_").replace(".", "_")
	#	var clip_text = "# tag: %s\nfunc %s(_behavior_data):\n\t_set_behavior_status(_behavior_data[\"tag\"], \"running\")\n\n\t_set_behavior_status(_behavior_data[\"tag\"], \"done\")\n\trun_next_behavior(_behavior_data)" % [tag, method_name]
	#	DisplayServer.clipboard_set(clip_text)

	if ImGui.SmallButton("Copy##copy_%s" % tag):
		var method_name = name.replace(" ", "_").replace(".", "_")
		var clip_text = (
			"# tag: %s\n" +
			"func %s(_behavior_data):\n" +
			"\tif !GlobalBehaviorData.BehaviorStates.has(_behavior_data[\"tag\"]):\n" +
			"\t\tGlobalBehaviorData.BehaviorStates[_behavior_data[\"tag\"]] = _behavior_data[\"actions\"][\"active\"]\n" +
			"\n" +
			"\tif GlobalBehaviorData.BehaviorStates[_behavior_data[\"tag\"]] == false:\n" +
			"\t\treturn\n" +
			"\n" +
			"\t_set_behavior_status(_behavior_data[\"tag\"], \"running\")\n" +
			"\n" +
			"\t_set_behavior_status(_behavior_data[\"tag\"], \"done\")\n" +
			"\trun_next_behavior(_behavior_data)"
		) % [tag, method_name]
		DisplayServer.clipboard_set(clip_text)

	if ImGui.IsItemHovered():
		ImGui.BeginTooltip()
		ImGui.Text("Copy tag + function stub for '%s'" % name)
		ImGui.EndTooltip()

	if is_open:
		for child in children:
			_draw_tree(child, all_data, status, drawn)
		if not (flags & ImGui.TreeNodeFlags_NoTreePushOnOpen):
			ImGui.TreePop()

func _get_children(behavior: Dictionary, all_data: Array) -> Array:
	var outputs = behavior.get("actions", {}).get("outputs", [])
	var children := []
	for out_tag in outputs:
		for b in all_data:
			if b["tag"] == out_tag:
				children.append(b)
				break
	return children
