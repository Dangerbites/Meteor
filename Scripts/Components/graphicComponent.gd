extends Sprite2D
var object_data

@export var collision : CollisionShape2D

func _ready() -> void:
	object_data = get_parent().object_data
	var asset_path = object_data["asset_path"]
	var full_path = TapAssetExtractor.get_asset_user_path(asset_path)

	var image := Image.new()
	var err := image.load(full_path)
	if err != OK:
		push_error("Failed to load image: %s (error %s)" % [full_path, err])
		return

	texture = ImageTexture.create_from_image(image)

	apply_anchor_offset()


# Cocos2d anchorPoint correction. By default Godot centers the texture
# (anchor 0.5, 0.5) on the node's global_position. hyperPad/Cocos2d lets
# anchor be any fraction of the sprite's own size, including values
# outside 0-1 (e.g. a head sprite pinned far below itself so it sits
# above a body). `offset` is applied in this node's local space, so
# Godot scales and rotates it automatically along with the texture -
# matching how Cocos2d applies scale/rotation around the anchor point.
# Assumes this Sprite2D has centered = true (Godot's default).
func apply_anchor_offset() -> void:
	if not object_data.has("anchor") or texture == null:
		return

	var anchor = Vector2(object_data["anchor"][0], object_data["anchor"][1])
	var tex_size = texture.get_size()

	var target_offset = Vector2(
		tex_size.x * (0.5 - anchor.x),
		tex_size.y * (anchor.y - 0.5)
	)

	position = target_offset * scale

	# Duplicate the shape so we don't affect other instances that share it
	var new_shape = collision.shape.duplicate(true)
	collision.shape = new_shape
	collision.shape.size = tex_size * scale

	# position can stay as is – it’s a node property, not shared
	collision.position = position
