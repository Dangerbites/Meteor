extends Sprite2D
var object_data

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

	# anchor.x: cocos2d and Godot both run left-to-right, no flip needed.
	# anchor.y: cocos2d is bottom-up (0 = bottom of texture), Godot's
	# texture-fraction space is top-down (0 = top), so it's (1 - anchor.y)
	# in Godot terms. This shifts FROM Godot's default center (0.5, 0.5)
	# TO the real anchor point, in raw texture pixels (unscaled - the
	# node's transform applies scale/rotation to this automatically).
	offset = Vector2(
		tex_size.x * (0.5 - anchor.x),
		tex_size.y * (anchor.y - 0.5)
	)
