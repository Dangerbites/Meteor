extends TextureProgressBar

var object_data

func _ready() -> void:
	object_data = get_parent().object_data

	# --- Load primary texture ---
	if object_data["asset_path"] == "included_assets/UI/Health Bar/Green Square Container":
		var asset_path = "Assets/" + object_data["asset_path"]
		var full_path = TapAssetExtractor.get_asset_user_path(asset_path.substr(len("included_assets/")))
		var image := Image.new()
		var err := image.load(full_path)
		if err == OK:
			texture_under = ImageTexture.create_from_image(image)
		else:
			push_error("Failed to load primary texture: %s (error %s)" % [full_path, err])
	else:
		var full_path = TapAssetExtractor.get_asset_user_path(object_data["asset_path"])
		var image := Image.new()
		var err := image.load(full_path)
		if err == OK:
			texture_under = ImageTexture.create_from_image(image)
		else:
			push_error("Failed to load primary texture: %s (error %s)" % [full_path, err])

	# --- Load secondary texture ---
	var second_path = object_data["secondary_asset_path"]
	if second_path == "included_assets/UI/Health Bar/Green Square Bar":
		var asset_path = "Assets/" + second_path
		var full_path = TapAssetExtractor.get_asset_user_path(asset_path.substr(len("included_assets/")))
		var image := Image.new()
		var err := image.load(full_path)
		if err == OK:
			texture_progress = ImageTexture.create_from_image(image)
		else:
			push_error("Failed to load secondary texture: %s (error %s)" % [full_path, err])
	else:
		var full_path = TapAssetExtractor.get_asset_user_path(second_path)
		var image := Image.new()
		var err := image.load(full_path)
		if err == OK:
			texture_progress = ImageTexture.create_from_image(image)
		else:
			push_error("Failed to load secondary texture: %s (error %s)" % [full_path, err])

	# --- Set progress value ---
	value = object_data["gameobjectdata"]["percentage"]

	var first_tint = object_data["gameobjectdata"]["tint"]
	tint_under = Color(first_tint["UIRed"], first_tint["UIGreen"], first_tint["UIBlue"], first_tint["UIAlpha"])

	var second_tint = object_data["gameobjectdata"]["tintSecondary"]
	tint_progress = Color(second_tint["UIRed"], second_tint["UIGreen"], second_tint["UIBlue"], second_tint["UIAlpha"])

	# --- Apply anchor offset (centering + extra 52px down) ---
	apply_anchor_offset()

	# --- Fade-in effect (as originally) ---
	await get_tree().create_timer(0.05).timeout
	get_parent().modulate = Color.WHITE


func apply_anchor_offset() -> void:
	var box_size = size
	if box_size == Vector2.ZERO:
		return  # No size yet, skip

	var offset = Vector2.ZERO
	if object_data.has("anchor"):
		var anchor = Vector2(object_data["anchor"][0], object_data["anchor"][1])
		# Control origin is top‑left; shift so that the anchor point sits at (0,0)
		offset = Vector2(
			-anchor.x * box_size.x,
			(anchor.y - 1.0) * box_size.y
		)
	else:
		# Default: center the bar (original behaviour)
		offset = -box_size / 2.0

	# Your constant vertical adjustment (same as the old `global_position.y += 52`)
	offset.y += 52

	global_position += offset
