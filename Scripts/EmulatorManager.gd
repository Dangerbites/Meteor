extends Node

signal finished_loading_level

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

var converter_pid: int = -1
var expected_output_path: String = ""

var recent_projects = []
signal project_loaded(tap_path)

# Only third-party (non-stdlib) import in hyperpad_convert3.py - the rest
# (json, os, plistlib, re, sqlite3, tempfile, zipfile) ship with any
# standard Python install and don't need a pip check.
const REQUIRED_PIP_PACKAGES := ["av"]

func _ready() -> void:
	ensure_check_script_in_user_folder()
	ensure_hyperpad_convert_in_user_folder()
	ensure_m4a_converter_in_user_folder()
	check_python_environment()

	get_window().files_dropped.connect(_on_files_dropped)

	#console commands
	Console.add_command("loadScene", load_scene, ["Scene Name"])
	Console.add_command("getSceneNames", get_scene_names,)

func _get_warn_label() -> RichTextLabel:
	return get_tree().current_scene.get_node("%warn") as RichTextLabel

func _set_warn_text(text: String) -> void:
	var warn_label := _get_warn_label()
	if warn_label == null:
		push_warning("check_python_environment: no '%%warn' node found to display message")
		return
	warn_label.text = text
	warn_label.show()

func _clear_warn_text() -> void:
	var warn_label := _get_warn_label()
	if warn_label != null:
		warn_label.text = ""
		warn_label.hide()

## Verifies Python is on PATH and that hyperpad_convert3.py's one
## third-party dependency (the "av" package) is importable, then writes
## a clear message + ready-to-paste pip command into the "%warn" label
## if either check fails. Does nothing (and hides the label) if both
## checks pass.
func check_python_environment() -> void:
	var python_cmd = "py" if OS.has_feature("windows") else "python3"

	# --- Check 1: is Python on PATH? ---
	var version_output := []
	var version_exit := OS.execute(python_cmd, ["--version"], version_output, true)
	if version_exit != 0:
		_set_warn_text(
			"[color=red][b]Python not found[/b][/color]\n" +
			"'%s' is not on your PATH, or Python isn't installed.\n" % python_cmd +
			"Install Python from https://python.org and make sure to check " +
			"\"Add Python to PATH\" during setup, then restart this app."
		)
		return

	# --- Check 2: run check_av.py (must already be in user://) ---
	var user_dir = OS.get_user_data_dir()
	var check_script_path = user_dir.path_join("check_av.py")

	# In case the script hasn't been copied yet (should be done in _ready)
	if not FileAccess.file_exists(check_script_path):
		_set_warn_text(
			"[color=red][b]Check script missing[/b][/color]\n" +
			"%s not found. Please restart the app to regenerate it." % check_script_path
		)
		return

	var check_output := []
	var check_exit := OS.execute(python_cmd, [check_script_path], check_output, true)

	if check_exit != 0:
		# The script prints the error details to stdout – show them
		var details = "\n".join(check_output)
		_set_warn_text(
			"[color=red][b]Missing Python package(s)[/b][/color]\n" +
			"The check script reported:\n%s\n\n" % details +
			"Run this command, then restart this app:\n" +
			"[code]%s -m pip install av[/code]" % python_cmd
		)
		return

	# Everything is fine
	_clear_warn_text()

func _on_files_dropped(files: PackedStringArray):
	for file_path in files:
		if file_path.get_extension().to_lower() == "tap":
			_run_converter(file_path)
			emulated_tap = file_path
			break

func _run_converter(tap_path: String):
	if not recent_projects.has(tap_path): # Add tap path to recent projects if it dosent have, and limit it to 5 values.
		recent_projects.push_front(tap_path)
	if len(recent_projects) > 5:
		recent_projects.pop_back()
	project_loaded.emit(tap_path)
	
	var progress_ui = get_tree().current_scene.get_node("ProgressUI")
	progress_ui.set_progress("Converting sqlite data to JSON...", 69)

	var script_dir = OS.get_user_data_dir()
	
	var script_path = script_dir.path_join("hyperpad_convert3.py")
	expected_output_path = script_dir.path_join(project_json)

	print("Looking for Python script at: ", script_path)

	if not FileAccess.file_exists(script_path):
		push_error("Error: Python script not found at: " + script_path)
		return

	var python_cmd = "py" if OS.has_feature("windows") else "python3"

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

	# Name the container after the layer's UUID (falling back to the
	# Z_PK-based layer_key for layers with no UUID, e.g. default/unnamed
	# editor layers) so it can be found by name and so Show_Layer /
	# Hide_Layer's UUID-based lookup has a stable, human-inspectable name
	# to match against in the scene tree / remote debugger.
	var layer_uuid = layer_info.get("uuid", null)
	container.name = str(layer_uuid) if layer_uuid != null else "Layer_%s" % layer_key

	#print("Created layer container: key=", layer_key, " uuid=", layer_uuid, " name=", container.name)

	container.add_to_group("hyperpadLayer")

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

	# Apply the layer's own hidden state up front, so a layer marked
	# hidden in the editor starts hidden instead of every object inside
	# it needing its own individual visibility/alpha toggled to fake it.
	if layer_info.get("hidden", false):
		container.hide()

	_layer_nodes[layer_key] = container
	return container


var _is_loading_scene := false

func load_scene(_scene : String = main_scene_name):
	if _is_loading_scene:
		push_warning("load_scene: already loading a scene — ignoring re-entrant call for '%s'" % _scene)
		return
	_is_loading_scene = true

	_layer_nodes.clear()

	var global_ui := get_tree().current_scene.get_node("GlobalUI")
	var scene_root := get_tree().current_scene.get_node("Scene")

	for i in global_ui.get_children():
		i.queue_free()
	for i in scene_root.get_children():
		i.queue_free()

	# Wait for queue_free()'d children to actually leave the tree before
	# spawning new ones - a fixed-duration timer (the old 0.01s wait) is
	# a race: deferred deletion usually finishes within a frame or two,
	# but isn't guaranteed to by any fixed wall-clock delay. Polling
	# child_count back to 0 (bounded, so a stuck node can't hang forever)
	# is the actual correctness condition we want.
	var max_wait_frames := 30
	var waited := 0
	while (global_ui.get_child_count() > 0 or scene_root.get_child_count() > 0) and waited < max_wait_frames:
		await get_tree().process_frame
		waited += 1

	if waited >= max_wait_frames:
		push_warning("load_scene: timed out waiting for old scene children to free (GlobalUI: %d, Scene: %d remaining)" % [global_ui.get_child_count(), scene_root.get_child_count()])

	var objects
	var objects_dict = project_json_parsed["Objects"]

	if objects_dict.has(_scene):
		objects = objects_dict[_scene]
	else:
		objects = objects_dict.get("null", {})

	var SceneSettings = project_json_parsed["SceneSettings"][_scene]
	var Layers = project_json_parsed["Layers"]

	var BackgroundColorData = SceneSettings["background"]["color_rgb"]
	var BackgroundColor = Color(BackgroundColorData[0], BackgroundColorData[1], BackgroundColorData[2])
	RenderingServer.set_default_clear_color(BackgroundColor)

	var asset_path = SceneSettings["background"].get("image_path", "")

	if asset_path:
		get_tree().current_scene.get_node("BG_IMG").show()
		var full_path = TapAssetExtractor.get_asset_user_path(asset_path)

		var image := Image.new()
		var err := image.load(full_path)
		if err != OK:
			push_error("Failed to load image: %s (error %s)" % [full_path, err])
			_is_loading_scene = false
			return

		get_tree().current_scene.get_node("BG_IMG").texture = ImageTexture.create_from_image(image)
	else:
		get_tree().current_scene.get_node("BG_IMG").hide()

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

		if objects[i].get("gameobjectdata", null):
			var tags_array = objects[i]["gameobjectdata"].get("tags", [])
			if tags_array != []:
				for tag in tags_array:
					clone.add_to_group(tag)

		clone.object_data = objects[i]
		clone.id = i
		layer_container.add_child(clone)

	_is_loading_scene = false
	finished_loading_level.emit()
			
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

func ensure_check_script_in_user_folder() -> void:
	var user_dir = OS.get_user_data_dir()
	var target_path = user_dir.path_join("check_av.py")

	if FileAccess.file_exists(target_path):
		return
	var source_path = "res://check_av.py"
	var source_file = FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		push_error("Source file not found: " + source_path)
		return
	var content = source_file.get_as_text()
	source_file.close()

	var target_file = FileAccess.open(target_path, FileAccess.WRITE)
	target_file.store_string(content)
	target_file.close()
	print("Copied check_av.py to user folder.")

func ensure_m4a_converter_in_user_folder() -> void:
	var user_dir = OS.get_user_data_dir()
	var target_path = user_dir.path_join("m4a_to_ogg.py")

	# Already there? Nothing to do.
	if FileAccess.file_exists(target_path):
		print("m4a_to_ogg.py already exists in user folder.")
		return

	# Source path inside the project's resources.
	var source_path = "res://m4a_to_ogg.py"
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
	print("Copied m4a_to_ogg.py to user folder.")

# -------------------------
# DEVELOPER CONSOLE FUNCTIONS

func get_scene_names() -> void:
	for i in project_json_parsed["Scenes"]:
		Console.print_line(i["name"])
