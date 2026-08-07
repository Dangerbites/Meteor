extends Node

signal finished_loading_level

# SETTINGS VARIABLES
var Aspect_Ratio : String = "4:3"

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
signal project_finishing_loading(tap_path)

const REQUIRED_PIP_PACKAGES := ["av"]

# Every user://-copied Python script that should match its res:// source
# exactly. Checked on startup so a hand-edited or stale copy (e.g. from
# an older app version) gets flagged instead of silently misbehaving.
const TRACKED_PYTHON_SCRIPTS := [
	"hyperpad_convert3.py",
	"m4a_to_ogg.py",
	"check_av.py",
]

# Accumulated warning lines for this session - each failed check appends
# one entry here instead of overwriting the label, so multiple problems
# (missing Python, missing package, edited scripts) all show at once.
var _warning_log: Array[String] = []

func _ready() -> void:
	ensure_check_script_in_user_folder()
	ensure_hyperpad_convert_in_user_folder()
	ensure_m4a_converter_in_user_folder()

	check_python_environment()
	check_tracked_scripts_unmodified()

	_refresh_warn_label()

	get_window().files_dropped.connect(_on_files_dropped)

	#console commands
	Console.add_command("loadScene", load_scene, ["Scene Name"])
	Console.add_command("getSceneNames", get_scene_names,)

func _get_warn_label() -> RichTextLabel:
	return get_tree().current_scene.get_node("%warn") as RichTextLabel

## Appends one warning entry to the log. Does NOT touch the label directly -
## call _refresh_warn_label() (or let check_python_environment /
## check_tracked_scripts_unmodified do it) once all checks for this pass
## have run, so every issue found this session shows together.
func _log_warning(text: String) -> void:
	_warning_log.append(text)

## Rebuilds the %warn label's full text from _warning_log. If the log is
## empty, hides the label instead of showing an empty box.
func _refresh_warn_label() -> void:
	var warn_label := _get_warn_label()
	if warn_label == null:
		push_warning("_refresh_warn_label: no '%%warn' node found to display messages")
		return

	if _warning_log.is_empty():
		warn_label.text = ""
		warn_label.hide()
		return

	# Number each entry and separate with a rule so multiple stacked
	# warnings read as a log, not a wall of run-together text.
	var lines: Array[String] = []
	for i in _warning_log.size():
		lines.append("[b]%d.[/b] %s" % [i + 1, _warning_log[i]])

	warn_label.text = "\n\n".join(lines)
	warn_label.show()

## Verifies Python is on PATH and that hyperpad_convert3.py's one
## third-party dependency (the "av" package) is importable. Appends a
## warning for each failed check rather than stopping at the first one,
## so "no Python" and "no av" (which can't both be meaningfully checked
## if Python itself is missing) don't hide each other - if Python isn't
## found at all, the av check is skipped since it can't run anyway.
func check_python_environment() -> void:
	var python_cmd = "py" if OS.has_feature("windows") else "python3"

	var version_output := []
	var version_exit := OS.execute(python_cmd, ["--version"], version_output, true)
	if version_exit != 0:
		_log_warning(
			"[color=red][b]Python not found[/b][/color]\n" +
			"'%s' is not on your PATH, or Python isn't installed. " % python_cmd +
			"Install Python from https://python.org and check " +
			"\"Add Python to PATH\" during setup, then restart this app."
		)
		return  # Can't run the av check without Python at all.

	var user_dir = OS.get_user_data_dir()
	var check_script_path = user_dir.path_join("check_av.py")

	if not FileAccess.file_exists(check_script_path):
		_log_warning(
			"[color=red][b]Check script missing[/b][/color]\n" +
			"%s not found. Restart the app to regenerate it." % check_script_path
		)
		return

	var check_output := []
	var check_exit := OS.execute(python_cmd, [check_script_path], check_output, true)

	if check_exit != 0:
		var details = "\n".join(check_output)
		_log_warning(
			"[color=red][b]Missing Python package(s)[/b][/color]\n" +
			"The check script reported:\n%s\n\n" % details +
			"Run this command, then restart this app:\n" +
			"[code]%s -m pip install av[/code]" % python_cmd
		)

## Compares every user://-copied script in TRACKED_PYTHON_SCRIPTS against
## its res:// source byte-for-byte. Appends one warning per mismatched
## file (not one combined warning), so if e.g. two of three scripts were
## edited, both show as separate log entries.
func check_tracked_scripts_unmodified() -> void:
	var user_dir = OS.get_user_data_dir()

	for script_name in TRACKED_PYTHON_SCRIPTS:
		var source_path = "res://%s" % script_name
		var user_path = user_dir.path_join(script_name)

		if not FileAccess.file_exists(source_path):
			# Nothing to compare against - not a user-side problem, skip silently.
			continue
		if not FileAccess.file_exists(user_path):
			# ensure_*_in_user_folder() should have created this already;
			# if it's still missing that's its own failure mode, not a
			# "modified" one, so don't report it here.
			continue

		var source_file = FileAccess.open(source_path, FileAccess.READ)
		var user_file = FileAccess.open(user_path, FileAccess.READ)

		if source_file == null or user_file == null:
			continue

		var source_content = source_file.get_as_text()
		var user_content = user_file.get_as_text()
		source_file.close()
		user_file.close()

		if source_content != user_content:
			_log_warning(
				"[color=orange][b]%s has been modified[/b][/color]\n" % script_name +
				"Your copy in the user data folder no longer matches this app's version, " +
				"which can cause outdated or broken behavior.\n" +
				"Please delete the Python files in your user data folder " +
				"[press F1 to open the folder] and restart Meteor."
			)

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
	if converter_pid != -1:
		if not OS.is_process_running(converter_pid):
			print("Python converter finished!")
			converter_pid = -1
			
			if FileAccess.file_exists(expected_output_path):
				start_emulating()
			else:
				push_error("Error: Converter finished but game.json was not found!")

	if Input.is_action_just_pressed("open_user_folder"):
		var user_path = ProjectSettings.globalize_path("user://")
		OS.shell_open(user_path)

	# F1 opens the user data folder - referenced in the "modified scripts"
	# warning text above, so it needs to actually do that.
	if Input.is_action_just_pressed("ui_home") or Input.is_key_pressed(KEY_F1):
		var user_path = ProjectSettings.globalize_path("user://")
		OS.shell_open(user_path)

func start_emulating():
	if get_tree().current_scene.get_node("ipad"):
		get_tree().current_scene.get_node("ipad").queue_free()

	delete_directory_recursive("user://project")

	var path = ProjectSettings.globalize_path("user://" + project_json)

	var progress_ui = get_tree().current_scene.get_node("ProgressUI")
	
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
	project_finishing_loading.emit(expected_output_path)

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

	var layer_uuid = layer_info.get("uuid", null)
	container.name = str(layer_uuid) if layer_uuid != null else "Layer_%s" % layer_key

	container.add_to_group("hyperpadLayer")

	container.z_index = -int(layer_info["z_order"])
	container.z_as_relative = true

	var parent_name = "GlobalUI" if layer_info["ui_layer"] else "Scene"
	get_tree().current_scene.get_node(parent_name).add_child(container)

	if layer_info.get("hidden", false):
		container.hide()

	_layer_nodes[layer_key] = container
	return container


var _is_loading_scene := false

func load_scene(_scene : String = main_scene_name):
	get_tree().current_scene.get_node("%warn").hide()

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

	if FileAccess.file_exists(target_path):
		print("hyperpad_convert3.py already exists in user folder.")
		return

	var source_path = "res://hyperpad_convert3.py"
	if not FileAccess.file_exists(source_path):
		push_error("Source file not found: " + source_path)
		return

	var source_file = FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		push_error("Failed to open source file: " + source_path)
		return

	var content = source_file.get_as_text()
	source_file.close()

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

	if FileAccess.file_exists(target_path):
		print("m4a_to_ogg.py already exists in user folder.")
		return

	var source_path = "res://m4a_to_ogg.py"
	if not FileAccess.file_exists(source_path):
		push_error("Source file not found: " + source_path)
		return

	var source_file = FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		push_error("Failed to open source file: " + source_path)
		return

	var content = source_file.get_as_text()
	source_file.close()

	var target_file = FileAccess.open(target_path, FileAccess.WRITE)
	if target_file == null:
		push_error("Failed to create target file: " + target_path)
		return

	target_file.store_string(content)
	target_file.close()
	print("Copied m4a_to_ogg.py to user folder.")

# -------------------------
# DEVELOPER CONSOLE FUNCTIONS

func get_scene_names():
	var obtained_scenes = []
	for i in project_json_parsed["Scenes"]:
		obtained_scenes.append(i["name"])
		Console.print_line(i["name"])
	return obtained_scenes
