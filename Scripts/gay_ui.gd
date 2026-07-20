extends CanvasLayer

func _update_recent_projects(tap_path):
	$MenuBar/PopupMenu/PopupMenu.clear()
	for x in EmulatorManager.recent_projects:
		$MenuBar/PopupMenu/PopupMenu.add_item(x)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	EmulatorManager.project_loaded.connect(_update_recent_projects)
	$MenuBar/PopupMenu.add_item("Open TAP")
	$MenuBar/PopupMenu.add_submenu_item("Recent TAPs", "PopupMenu")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

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
