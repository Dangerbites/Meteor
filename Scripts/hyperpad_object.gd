extends Node2D

var ui_element : bool = false
var id : String
var obj_name : String
var object_data
var layer : int

func _ready() -> void:
	visible = !object_data["gameobjectdata"]["hidden"]

	layer = object_data["layer"] 

	visible = !EmulatorManager.project_json_parsed["Layers"][str(layer)]["hidden"]

	ui_element = object_data["ui_element"]
	obj_name = object_data["name"]

	name = obj_name

	var data_x = object_data["position"][0]
	var data_y = object_data["position"][1]
	var viewport_size = get_viewport().get_visible_rect().size   # Godot 4 style

	if ui_element:
		# hyperPad UI coordinates are normalised 0-1, origin bottom-left.
		# Godot's UI origin is top-left, so flip Y.
		# This places the sprite's ANCHOR POINT here (not its center) -
		# the child Sprite2D corrects for that via its own offset.
		global_position = Vector2(
			data_x * viewport_size.x,
			(1.0 - data_y) * viewport_size.y
		)
	else:
		# World objects are in pixel coordinates, origin bottom-left.
		# Flip Y to Godot's top-left system.
		global_position = Vector2(data_x, viewport_size.y - data_y)

	scale = Vector2(object_data["scale"][0], object_data["scale"][1])

	rotation_degrees = object_data["rotation"]

	#print(object_data["gameobjectdata"]["tint"]["UIRed"])
	modulate = Color(object_data["gameobjectdata"]["tint"]["UIRed"], object_data["gameobjectdata"]["tint"]["UIGreen"], object_data["gameobjectdata"]["tint"]["UIBlue"], object_data["gameobjectdata"]["tint"]["UIAlpha"])

	z_index = object_data["z_index"]
