extends Node2D

var ui_element : bool = false
var id : String
var obj_name : String
var object_data
var layer : int

func _ready() -> void:
	visible = !object_data["gameobjectdata"]["hidden"]

	ui_element = object_data["ui_element"]
	obj_name = object_data["name"]

	name = obj_name

	var data_x = object_data["position"][0]
	var data_y = object_data["position"][1]
	var viewport_size = get_viewport().get_visible_rect().size

	if ui_element:
		global_position = Vector2(
			data_x * viewport_size.x,
			(1.0 - data_y) * viewport_size.y
		)
	else:
		global_position = Vector2(data_x, viewport_size.y - data_y)

	scale = Vector2(object_data["scale"][0], object_data["scale"][1])
	rotation_degrees = object_data["rotation"]

	modulate = Color(object_data["gameobjectdata"]["tint"]["UIRed"], object_data["gameobjectdata"]["tint"]["UIGreen"], object_data["gameobjectdata"]["tint"]["UIBlue"], object_data["gameobjectdata"]["tint"]["UIAlpha"])

	z_index = object_data["z_index"]

	# O(1) UUID -> Node lookup cache, so get_node_from_UUID doesn't need
	# to linearly scan every HyperpadObject in the scene on every call -
	# critical for large scenes / hot paths like collision checks that
	# call it every physics frame. Every object type routes through this
	# shared script's _ready(), so registering here covers Graphic, TTF
	# Label, Empty, Joystick, HealthBar, and LifeIndicator all at once.
	GlobalBehaviorData.register_uuid(id, self)

func _exit_tree() -> void:
	GlobalBehaviorData.unregister_uuid(id, self)