extends CanvasLayer

@export var SettingsWindow : Window

const RECENT_TAPS_MAX: int = 25
const RECENT_TAPS_SAVE_PATH := "user://recent_taps.cfg"

func _update_recent_projects(_tap_path):
	$MenuBar/PopupMenu/PopupMenu.clear()
	for x in EmulatorManager.recent_projects:
		$MenuBar/PopupMenu/PopupMenu.add_item(x)
		
func _update_scenes(_tap_path):
	$MenuBar/PopupMenu2/PopupMenu.clear()
	for x in EmulatorManager.get_scene_names():
		$MenuBar/PopupMenu2/PopupMenu.add_item(x)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_load_recent_projects()
	
	EmulatorManager.project_finishing_loading.connect(_update_scenes)
	EmulatorManager.project_loaded.connect(_update_recent_projects)
	EmulatorManager.project_loaded.connect(_on_project_loaded_save)

	$MenuBar/PopupMenu.add_item("Open TAP")
	$MenuBar/PopupMenu.add_submenu_item("Recent TAPs", "PopupMenu")
	
	$MenuBar/PopupMenu2.add_submenu_item("Load Scene", "PopupMenu")

	$MenuBar/PopupMenu2.add_item("Settings", 100)
	$MenuBar/PopupMenu2.id_pressed.connect(_on_menu_item_pressed)

	_update_recent_projects(null)

func _on_menu_item_pressed(id: int):
	if id == 100:
		SettingsWindow.show()

func _recent_project_id_pressed(id: int) -> void:
	_open_project($MenuBar/PopupMenu/PopupMenu.get_item_text(id))

func _on_file_menu_id_pressed(id: int) -> void:
	if id == 0:
		$OpenTapFileDialog.show()

func _on_open_tap_file_dialog_file_selected(path: String) -> void:
	_open_project(path)

func _open_project(file_path):
	if file_path.get_extension().to_lower() == "tap":
		EmulatorManager._run_converter(file_path)
		EmulatorManager.emulated_tap = file_path

# Called whenever a project loads - EmulatorManager.recent_projects has
# already been updated (push_front + trim) by _run_converter by this
# point, so we just need to persist whatever it currently holds.
func _on_project_loaded_save(_tap_path: String) -> void:
	_save_recent_projects()

func _save_recent_projects() -> void:
	var config := ConfigFile.new()

	# Trim defensively in case something upstream ever pushes past the cap -
	# this is the one place that actually enforces RECENT_TAPS_MAX on disk,
	# regardless of what EmulatorManager's own in-memory list is doing.
	var trimmed: Array = EmulatorManager.recent_projects.slice(0, RECENT_TAPS_MAX)
	config.set_value("recent_taps", "paths", trimmed)

	var err := config.save(RECENT_TAPS_SAVE_PATH)
	if err != OK:
		push_warning("Failed to save recent taps to '%s' (error %d)" % [RECENT_TAPS_SAVE_PATH, err])

func _load_recent_projects() -> void:
	var config := ConfigFile.new()
	var err := config.load(RECENT_TAPS_SAVE_PATH)

	if err != OK:
		# No file yet (first run) or unreadable - not an error worth
		# warning about on first launch specifically.
		if err != ERR_FILE_NOT_FOUND:
			push_warning("Failed to load recent taps from '%s' (error %d)" % [RECENT_TAPS_SAVE_PATH, err])
		return

	var loaded = config.get_value("recent_taps", "paths", [])
	if loaded is Array:
		EmulatorManager.recent_projects = loaded.slice(0, RECENT_TAPS_MAX)

func _load_scene_id_pressed(id: int) -> void:
	EmulatorManager.load_scene($MenuBar/PopupMenu2/PopupMenu.get_item_text(id))
