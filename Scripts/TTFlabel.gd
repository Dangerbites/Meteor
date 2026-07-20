extends RichTextLabel

var object_data
var BMFont = false

func _ready() -> void:
	object_data = get_parent().object_data
	#print(object_data["asset_path"])

	# hyperPad's own data distinguishes these by object_type, not by
	# guessing from asset_path or the presence/absence of a key:
	#   "TTFLabel" -> has dimensions + fontSize in gameobjectdata
	#   "Label"    -> bitmap font, no dimensions/fontSize at all
	# Hardcoding this to false meant every label always fell through to
	# the TTF branch below, which is what crashed on the "dimensions" key
	# for bitmap-font objects like "32-1" (asset Assets/UI/Fonts/8bit/32).
	BMFont = object_data.get("object_type") == "Label"

	if BMFont:
		load_user_bmfont(object_data["asset_path"])
		text = object_data["gameobjectdata"]["text"]

		horizontal_alignment = object_data["gameobjectdata"]["textAlignment"]
		fit_content = true
		scroll_active = false

		# Label-type (BMFont) objects have no "dimensions" key in
		# gameobjectdata at all - unlike TTFLabel, hyperPad never declared
		# a fixed box size for these; fit_content computes it from the
		# rendered text instead. That computation isn't guaranteed to be
		# done by the time this line runs, so defer the anchor math to
		# read this control's *actual* resulting size rather than reading
		# a "dimensions" value that doesn't exist for this object_type.
		call_deferred("_apply_bmfont_position")
	else:
		if object_data["asset_path"] == "included_assets/UI/Fonts/Helvetica/Helvetica":
			add_theme_font_override("normal_font", load("res://helvetica-255/Helvetica.ttf"))
		else:
			var font = load_ttf_from_folder(object_data["asset_path"])
			if font:
				add_theme_font_override("normal_font", font)
			else:
				# fallback to your original hardcoded path as a last resort
				var path = "res://project/%s/%s.ttf" % [object_data["asset_path"], object_data["asset_path"].get_file()]
				if ResourceLoader.exists(path):
					add_theme_font_override("normal_font", load(path))
				else:
					push_error("Could not load font for: ", object_data["asset_path"])
	
		text = object_data["gameobjectdata"]["text"]
		var ttf_size = string_to_vector2(object_data["gameobjectdata"]["dimensions"]["NS.sizeval"])
		size = ttf_size
		add_theme_font_size_override("normal_font_size", object_data["gameobjectdata"]["fontSize"])

		horizontal_alignment = object_data["gameobjectdata"]["textAlignment"]

		# Offsets
		apply_anchor_offset(ttf_size)
		global_position += Vector2(28, 28)

	global_position.y -= 10


func _apply_bmfont_position() -> void:
	# By now (one frame after _ready, via call_deferred), fit_content
	# should have sized this control to its actual rendered text - untested
	# against a real BMFont object, so if the box still looks unsized here
	# (0,0) or the position looks off, that assumption is the first thing
	# to check; a second call_deferred layer or a size_changed signal
	# connection may be needed instead of a single deferred call.
	apply_anchor_offset(size)
	global_position += Vector2(28, -18)


# Cocos2d anchorPoint correction, same model as the Sprite2D version:
# object_data["anchor"] is a fraction of this box's own size (bottom-up,
# can go outside 0-1), and it's supposed to land at the parent Node2D's
# global_position (the pin). A Control's `position` is its TOP-LEFT
# corner (Godot-fraction 0,0) rather than Sprite2D's default center
# (0.5,0.5), so the reference point differs from the sprite formula -
# this shifts FROM (0,0) TO the real anchor point instead of FROM (0.5,0.5).
# Previously this was hardcoded as `global_position -= box_size/2`, which
# is exactly what this formula reduces to when anchor = (0.5, 0.5) - so
# that old behavior is preserved as a special case, not replaced.
func apply_anchor_offset(box_size: Vector2) -> void:
	if not object_data.has("anchor"):
		global_position -= box_size / 2.0  # fallback: old centered assumption
		return

	var anchor = Vector2(object_data["anchor"][0], object_data["anchor"][1])

	global_position += Vector2(
		-anchor.x * box_size.x,
		(anchor.y - 1.0) * box_size.y
	)

func load_user_bmfont(base_path: String) -> void:
	# 1. Construct the path: user://project/Assets/UI/Fonts/...
	var target_dir = "user://project/" + base_path.trim_prefix("/")
	if not target_dir.ends_with("/"):
		target_dir += "/"
		
	# 2. Open the directory and search for the .fnt file
	var dir = DirAccess.open(target_dir)
	if dir:
		var fnt_path = ""
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			# Check if it's a file (not a folder) and ends with .fnt
			if not dir.current_is_dir() and file_name.get_extension().to_lower() == "fnt":
				fnt_path = target_dir + file_name
				break # Grab the first .fnt file found
			file_name = dir.get_next()
			
		# 3. Load the font and apply it
		if fnt_path != "":
			var bm_font = FontFile.new()
			var err = bm_font.load_bitmap_font(fnt_path)
			
			if err == OK:
				# Godot automatically grabs the .png referenced inside the .fnt file
				add_theme_font_override("normal_font", bm_font)
			else:
				push_error("Error loading BMFont at " + fnt_path + ". Error code: " + str(err))
		else:
			push_error("No .fnt file found in directory: " + target_dir)
	else:
		push_error("Could not open directory: " + target_dir)

func string_to_vector2(input: String) -> Vector2:
	# Remove the curly braces and any spaces, then split by comma
	var cleaned = input.strip_edges().trim_prefix("{").trim_suffix("}")
	var parts = cleaned.split(",")
	if parts.size() == 2:
		return Vector2(float(parts[0]), float(parts[1]))
	return Vector2.ZERO  # fallback if parsing fails

func load_ttf_from_folder(base_path: String) -> Font:
	# 1. Look in user:// instead of res://
	var dir_path = "user://project/" + base_path.trim_prefix("/")
	if not dir_path.ends_with("/"):
		dir_path += "/"
	
	var dir = DirAccess.open(dir_path)
	if not dir:
		push_error("Cannot open folder: " + dir_path)
		return null
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var font_path = ""
	
	while file_name != "":
		if not dir.current_is_dir():
			var ext = file_name.get_extension().to_lower()
			if ext in ["ttf", "otf", "ttc"]:
				font_path = dir_path + file_name
				break
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	if font_path.is_empty():
		push_error("No .ttf/.otf/.ttc found in: " + dir_path)
		return null
	
	# 2. Load the TTF dynamically (ResourceLoader doesn't work in user://)
	var font_bytes = FileAccess.get_file_as_bytes(font_path)
	if font_bytes.is_empty():
		push_error("Failed to read font bytes at: " + font_path)
		return null
		
	var font = FontFile.new()
	font.data = font_bytes # Godot 4 creates the font directly from the raw bytes
	
	return font
