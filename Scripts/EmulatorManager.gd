extends Node

# HYPERPAD OBJECT TYPES
var EmptyObjectScene : PackedScene = preload("res://objects/EmptyObject.tscn")
var GraphicObjectScene : PackedScene = preload("res://objects/graphic_object.tscn")
var TTFLabelObjectScene : PackedScene = preload("res://objects/ttf_label_object.tscn")
var JoystickObjectScene : PackedScene = preload("res://objects/joystick_object.tscn")
var HealthBarScene : PackedScene = preload("res://objects/health_bar_object.tscn")
var LifeIndicatorObject : PackedScene = preload("res://objects/LifeIndicatorObject.tscn")

var project_json := "game.json"
var emulated_tap := "Iamafuckingarchitect.tap"

var project_json_parsed
var main_scene_name := ""
var debug_move_speed : float = 500

# NEW: Variables to track the Python converter process
var converter_pid: int = -1
var expected_output_path: String = ""

func _ready() -> void:
	ensure_hyperpad_convert_in_user_folder()

	get_window().files_dropped.connect(_on_files_dropped)

	#console commands
	Console.add_command("loadScene", load_scene, ["Scene Name"])

func _on_files_dropped(files: PackedStringArray):
	for file_path in files:
		if file_path.get_extension().to_lower() == "tap":
			_run_converter(file_path)
			emulated_tap = file_path
			break

func _run_converter(tap_path: String):
	var progress_ui = get_tree().current_scene.get_node("ProgressUI")
	progress_ui.set_progress("Converting sqlite data to JSON...", 69)

	var script_dir = OS.get_user_data_dir()
	
	# Build the full paths
	var script_path = script_dir.path_join("hyperpad_convert3.py")
	expected_output_path = script_dir.path_join(project_json)

	# Debug: print the path to confirm it's correct
	print("Looking for Python script at: ", script_path)

	# Check if the script exists
	if not FileAccess.file_exists(script_path):
		push_error("Error: Python script not found at: " + script_path)
		return

	# Choose Python executable
	var python_cmd = "py" if OS.has_feature("windows") else "python3"

	# Run the converter in the background (non-blocking)
	var args = PackedStringArray([script_path, tap_path, expected_output_path])
	converter_pid = OS.create_process(python_cmd, args)

	if converter_pid == -1:
		push_error("Error: Failed to start the Python converter.")
	else:
		print("Converter started! PID: ", converter_pid)
		print("Output will be saved to: ", expected_output_path)
		print("Waiting for generation to finish...")

func _process(_delta):
	# Monitor the Python script process
	if converter_pid != -1:
		if not OS.is_process_running(converter_pid):
			print("Python converter finished!")
			converter_pid = -1 # Reset the PID so this doesn't run twice
			
			# Verify the file was actually created before starting
			if FileAccess.file_exists(expected_output_path):
				start_emulating()
			else:
				push_error("Error: Converter finished but game.json was not found!")

	# Standard input processing
	if Input.is_action_just_pressed("open_user_folder"):
		var user_path = ProjectSettings.globalize_path("user://")
		OS.shell_open(user_path)

	return

	if Input.is_action_pressed("arrow_down"):
		for node in get_tree().get_nodes_in_group("HyperpadObject"):
			node.global_position.y -= _delta * debug_move_speed
	if Input.is_action_pressed("arrow_up"):
		for node in get_tree().get_nodes_in_group("HyperpadObject"):
			node.global_position.y += _delta * debug_move_speed
	if Input.is_action_pressed("arrow_left"):
		for node in get_tree().get_nodes_in_group("HyperpadObject"):
			node.global_position.x += _delta * debug_move_speed
	if Input.is_action_pressed("arrow_right"):
		for node in get_tree().get_nodes_in_group("HyperpadObject"):
			node.global_position.x -= _delta * debug_move_speed

func start_emulating():
	if get_tree().current_scene.get_node("ipad"):
		get_tree().current_scene.get_node("ipad").queue_free()

	delete_directory_recursive("user://project")

	var path = ProjectSettings.globalize_path("user://" + project_json)

	# Grab the ProgressUI node (adjust path to your actual scene)
	var progress_ui = get_tree().current_scene.get_node("ProgressUI")
	
	# Start extraction – it will update the bar every file and yield every 5 files.
	await TapAssetExtractor.extract_tap_assets_non_blocking(
		emulated_tap, true, true, progress_ui
	)
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open file: ", path)
		return
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.parse_string(json_text)
	if json == null:
		push_error("Failed to parse JSON")
		return

	project_json_parsed = json

	var scene_map = json["SceneMap"]
	print(scene_map)
	
	for key in scene_map:
		var value = scene_map[key]
		if value != "Global" and value != "Pause Menu" and value != "Game Over":
			main_scene_name = value
			print("Main Scene Set To: ", main_scene_name)
			break

	load_scene()


var _layer_nodes: Dictionary = {}


func _get_layer_container(layer_key: String, layers: Dictionary) -> Node2D:
	if _layer_nodes.has(layer_key):
		return _layer_nodes[layer_key]

	var layer_info = layers[layer_key]
	var container := Node2D.new()
	container.name = "Layer_%s" % layer_key

	# ZINDEX is inverted relative to Godot's z_index: in hyperPad, a
	# HIGHER z_order sits further BACK, while Godot's z_index is the
	# opposite (higher = further front). Negate it here rather than
	# changing what the exporter reports, since z_order there is a
	# faithful passthrough of the raw column - the inversion is a
	# hyperPad-vs-Godot convention difference, not a data error.
	container.z_index = -int(layer_info["z_order"])
	container.z_as_relative = true

	var parent_name = "GlobalUI" if layer_info["ui_layer"] else "Scene"
	get_tree().current_scene.get_node(parent_name).add_child(container)

	_layer_nodes[layer_key] = container
	return container


func load_scene(_scene : String = main_scene_name):
	for i in get_tree().current_scene.get_node("Scene").get_children():
		i.queue_free()

	for i in get_tree().current_scene.get_node("GlobalUI").get_children():
		i.queue_free()

	_layer_nodes.clear()

	var objects = project_json_parsed["Objects"][_scene]
	var SceneSettings = project_json_parsed["SceneSettings"][_scene]
	var Layers = project_json_parsed["Layers"]

	# SET BACKGROUND COLOR
	var BackgroundColorData = SceneSettings["background"]["color_rgb"]
	var BackgroundColor = Color(BackgroundColorData[0], BackgroundColorData[1], BackgroundColorData[2])
	RenderingServer.set_default_clear_color(BackgroundColor)

	# SET BACKGROUND IMAGE IF AVAILABLE
	var asset_path = SceneSettings["background"].get("image_path", "")

	if asset_path:
		get_tree().current_scene.get_node("BG_IMG").show()
		var full_path = TapAssetExtractor.get_asset_user_path(asset_path)

		var image := Image.new()
		var err := image.load(full_path)
		if err != OK:
			push_error("Failed to load image: %s (error %s)" % [full_path, err])
			return

		get_tree().current_scene.get_node("BG_IMG").texture = ImageTexture.create_from_image(image)
	else:
		get_tree().current_scene.get_node("BG_IMG").hide()

	# SPAWN OBJECTS IN SCENE
	for i in objects:
		var layer_key = str(int(objects[i]["layer"]))
		var layer_container = _get_layer_container(layer_key, Layers)

		var clone: Node2D
		match objects[i]["object_type"]:
			"Empty":
				clone = EmptyObjectScene.instantiate() as Node2D
			"Graphic":
				clone = GraphicObjectScene.instantiate() as Node2D
			"TTFLabel":
				clone = TTFLabelObjectScene.instantiate() as Node2D
			"Label":
				clone = TTFLabelObjectScene.instantiate() as Node2D
				clone.get_child(0).BMFont = true
			"Joystick":
				clone = JoystickObjectScene.instantiate() as Node2D
			"HealthBar":
				clone = HealthBarScene.instantiate() as Node2D
			"LifeIndicator":
				clone = LifeIndicatorObject.instantiate() as Node2D
			_:
				continue

		clone.object_data = objects[i]
		clone.id = i
		layer_container.add_child(clone)

			
func delete_directory_recursive(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("delete_directory_recursive: could not open '%s' (error %d)" % [path, DirAccess.get_open_error()])
		return false

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path := path.path_join(file_name)
			if dir.current_is_dir():
				delete_directory_recursive(full_path)
			else:
				dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Now that it's empty, remove the folder itself.
	var parent_dir := DirAccess.open(path.get_base_dir())
	if parent_dir:
		var err := parent_dir.remove(path.get_file())
		if err != OK:
			push_warning("delete_directory_recursive: failed to remove '%s' (error %d)" % [path, err])
			return false
	return true

func ensure_hyperpad_convert_in_user_folder() -> void:
	var user_dir = OS.get_user_data_dir()
	var target_path = user_dir.path_join("hyperpad_convert3.py")

	# Already there? Nothing to do.
	if FileAccess.file_exists(target_path):
		print("hyperpad_convert3.py already exists in user folder.")
		return

	# Source path inside the project's resources.
	var source_path = "res://hyperpad_convert3.py"
	if not FileAccess.file_exists(source_path):
		push_error("Source file not found: " + source_path)
		return

	# Read the whole file.
	var source_file = FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		push_error("Failed to open source file: " + source_path)
		return

	var content = source_file.get_as_text()
	source_file.close()

	# Write it to the user folder.
	var target_file = FileAccess.open(target_path, FileAccess.WRITE)
	if target_file == null:
		push_error("Failed to create target file: " + target_path)
		return

	target_file.store_string(content)
	target_file.close()
	print("Copied hyperpad_convert3.py to user folder.")
