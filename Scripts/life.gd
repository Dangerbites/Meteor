extends Node2D

var object_data
var heart_texture : ImageTexture = null

func _ready() -> void:
	scale = Vector2(0.5,0.5)
	object_data = get_parent().object_data

	# --- Load the heart texture once ---
	var asset_path = object_data["asset_path"]
	if asset_path.begins_with("included_assets/"):
		asset_path = "Assets/" + asset_path.trim_prefix("included_assets/")

	var full_path = TapAssetExtractor.get_asset_user_path(asset_path)
	var image := Image.new()
	var err := image.load(full_path)
	if err != OK:
		push_error("Failed to load heart texture: %s (error %s)" % [full_path, err])
		return

	heart_texture = ImageTexture.create_from_image(image)

	# --- Set initial lives (example: from object_data if available, else 3) ---
	var initial_lives = object_data["gameobjectdata"]["lives"]
	var rows = object_data["gameobjectdata"]["livesPerRow"]

	if object_data.has("lives"):
		initial_lives = object_data["lives"]
	set_lives(initial_lives, rows)


# Spawns 'lives' number of hearts in rows of up to 'max_per_row' items.
# The whole grid is centred on this node's position.
func set_lives(lives: int, max_per_row: int = 5) -> void:
	# Clear any previously spawned sprites
	for child in get_children():
		child.queue_free()

	if lives <= 0 or heart_texture == null:
		return

	# --- Grid dimensions ---
	var tex_size = heart_texture.get_size()
	var spacing_x = tex_size.x + 0   # 2 px horizontal padding between hearts
	var spacing_y = tex_size.y + 0   # 2 px vertical padding between rows

	var num_rows = ceil(float(lives) / max_per_row)
	# Width of the widest row (the first row, except possibly the last if incomplete)
	var full_row_items = min(lives, max_per_row)
	var total_width = full_row_items * spacing_x
	var total_height = num_rows * spacing_y

	# Start offset so that the grid is centred at (0,0)
	var start_x = -total_width / 2.0 + spacing_x / 2.0
	var start_y = -total_height / 2.0 + spacing_y / 2.0

	# Anchor correction so this grid sits where object_data["anchor"]
	# actually says, instead of always dead-centre on this node's position.
	apply_anchor_offset(Vector2(total_width, total_height))

	# --- Spawn hearts ---
	for i in range(lives):
		var row_index = i / max_per_row
		var col_index = i % max_per_row

		var sprite := Sprite2D.new()
		sprite.texture = heart_texture
		# Position within the grid, centred on the cell
		sprite.position = Vector2(
			start_x + col_index * spacing_x,
			start_y + row_index * spacing_y
		)
		# Default Sprite2D is already centered (offset = 0,0) – perfect for grid layout
		add_child(sprite)


# Cocos2d anchorPoint correction, same model as the Sprite2D version:
# by default this whole grid is laid out centred on this node's position
# (see start_x/start_y above), matching Godot's own centered=true default
# for Sprite2D. hyperPad/Cocos2d lets anchor be any fraction of the
# object's own size, including values outside 0-1, and it's meant to land
# at the parent's global_position instead of the centre. `position` here
# is this node's local offset, so Godot scales/rotates it automatically
# along with the parent's transform - same as Sprite2D's `offset` does.
# grid_size is (total_width, total_height) rather than a texture size,
# recomputed on every set_lives() call since the grid's footprint changes
# with the life count.
func apply_anchor_offset(grid_size: Vector2) -> void:
	if not object_data.has("anchor"):
		return

	var anchor = Vector2(object_data["anchor"][0], object_data["anchor"][1])

	# grid_size is in raw, unscaled heart-texture pixels, but `position`
	# is this node's offset within its PARENT's space - unlike
	# Sprite2D.offset, it is NOT automatically scaled by this node's own
	# `scale` (0.5, 0.5). Without multiplying by scale here, the offset
	# ends up computed at full size while everything drawn under this
	# node actually renders at half that, overshooting by 2x in the
	# correct direction.
	position = Vector2(
		grid_size.x * (0.5 - anchor.x),
		grid_size.y * (anchor.y - 0.5)
	) * scale