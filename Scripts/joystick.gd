extends VirtualJoystick

var object_data

func _ready() -> void:
	object_data = get_parent().object_data

	# --- Load base texture ---
	var base_asset_path = object_data["asset_path"]
	if base_asset_path.begins_with("included_assets/"):
		base_asset_path = "Assets/" + base_asset_path.trim_prefix("included_assets/")
	
	var base_full_path = TapAssetExtractor.get_asset_user_path(base_asset_path)
	var base_image := Image.new()
	var err := base_image.load(base_full_path)
	if err != OK:
		push_error("Failed to load base texture: %s (error %s)" % [base_full_path, err])
	else:
		var base_texture = ImageTexture.create_from_image(base_image)
		var base_stylebox = StyleBoxTexture.new()
		base_stylebox.texture = base_texture
		add_theme_stylebox_override("normal_joystick", base_stylebox)
		add_theme_stylebox_override("pressed_joystick", base_stylebox)

	# --- Load tip texture ---
	var tip_asset_path = object_data["secondary_asset_path"]
	if tip_asset_path.begins_with("included_assets/"):
		tip_asset_path = "Assets/" + tip_asset_path.trim_prefix("included_assets/")

	var tip_full_path = TapAssetExtractor.get_asset_user_path(tip_asset_path)
	var tip_image := Image.new()
	err = tip_image.load(tip_full_path)
	if err != OK:
		push_error("Failed to load tip texture: %s (error %s)" % [tip_full_path, err])
	else:
		var tip_texture = ImageTexture.create_from_image(tip_image)
		var tip_stylebox = StyleBoxTexture.new()
		tip_stylebox.texture = tip_texture
		add_theme_stylebox_override("normal_tip", tip_stylebox)
		add_theme_stylebox_override("pressed_tip", tip_stylebox)

	# --- Apply the anchor offset (same logic as your other scripts) ---
	apply_anchor_offset()

func apply_anchor_offset() -> void:
	if not object_data.has("anchor"):
		return

	var anchor = Vector2(object_data["anchor"][0], object_data["anchor"][1])

	# Use joystick_size as the reference size for the anchor offset.
	# This works because the control's visual centre is at the middle of
	# a square of size joystick_size × joystick_size.
	var ref_size = Vector2(joystick_size, joystick_size)

	# Same conversion as your Sprite2D example:
	#   x = size.x * (0.5 - anchor.x)
	#   y = size.y * (anchor.y - 0.5)   ← flipped because Cocos2d Y is reversed
	position = Vector2(
		ref_size.x * (0.5 - anchor.x),
		ref_size.y * (anchor.y - 0.5)
	)