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

		global_position += Vector2(5, 22)
		size.x += 40
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
	call_deferred("_sync_collision")


func _apply_bmfont_position() -> void:
	# By now (one frame after _ready, via call_deferred), fit_content
	# should have sized this control to its actual rendered text - untested
	# against a real BMFont object, so if the box still looks unsized here
	# (0,0) or the position looks off, that assumption is the first thing
	# to check; a second call_deferred layer or a size_changed signal
	# connection may be needed instead of a single deferred call.
	apply_anchor_offset(size)
	global_position += Vector2(28, -18)
	call_deferred("_sync_collision")

# --- Collision: exact unique shape matching the rendered text ---------------
func _sync_collision() -> void:
	# hyperPad exports no reliable collision_points for labels (Default /
	# empty) and the .tscn's RectangleShape2D is a single shared SubResource
	# (0×0). Mutating it would resize every label at once. This builds a
	# unique per-instance RectangleShape2D sized to the exact rendered text
	# (tight glyph bounds) and positions it at the visual center of that
	# tight rect inside the container, so each label gets an independent,
	# pixel-exact hitbox. Called deferred from _ready and from
	# Change_Label for live updates.
	var parent = get_parent() as Node2D
	if parent == null:
		return
	var coll = parent.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if coll == null:
		return
	# BMFont fit_content sizing is deferred – if size is still zero wait a frame.
	if size == Vector2.ZERO:
		call_deferred("_sync_collision")
		return
	# Container size is the Control's fixed size (TTF: dimensions box) or
	# the fit_content tight size (BMFont). Tight glyph size is preferred
	# so "Hi" in a 256×64 box doesn't give a 256×64 collider.
	var container_size: Vector2 = size
	var tight_size: Vector2 = container_size
	var font = get_theme_font("normal_font")
	if font != null and text != "":
		var fs = 32
		if has_theme_font_size("normal_font_size"):
			fs = get_theme_font_size("normal_font_size")
		elif parent.object_data != null and parent.object_data.has("gameobjectdata"):
			var gd = parent.object_data["gameobjectdata"]
			if gd.has("fontSize"):
				fs = int(gd["fontSize"])
		var t = font.get_string_size(text, horizontal_alignment, -1, fs)
		if t.x > 0 and t.y > 0:
			tight_size = t
			if text.contains("\n"):
				var lines = text.split("\n")
				var max_w := 0.0
				for l in lines:
					var w = font.get_string_size(l, horizontal_alignment, -1, fs).x
					max_w = max(max_w, w)
				tight_size.x = max_w
				# RichTextLabel line spacing ~1.2× font size; prefer content height if larger.
				tight_size.y = fs * lines.size() * 1.2
				var ch = get_content_height()
				if ch > tight_size.y:
					tight_size.y = ch
			# Clamp tight to container if tighter would exceed container due to empty metrics edge.
			# Otherwise tight is exact glyph bounds.
		else:
			tight_size = container_size

	var box_size: Vector2 = tight_size
	# Unique per-instance shape – never mutate the shared .tscn SubResource.
	# Bake handling: hyperpad_object.gd bakes Dynamic scale into children and
	# resets parent scale to ONE. To keep world size exact, local shape must
	# be box_size * orig_scale / parent_scale so world = tight * orig_scale.
	var orig_scale := Vector2.ONE
	if parent.object_data != null and parent.object_data.has("scale"):
		var sd = parent.object_data["scale"]
		if sd is Array and sd.size() == 2:
			orig_scale = Vector2(float(sd[0]), float(sd[1]))
		elif sd is Vector2:
			orig_scale = sd
	var parent_gs: Vector2 = parent.scale
	if parent_gs == Vector2.ZERO:
		parent_gs = Vector2.ONE
	if parent_gs.x == 0:
		parent_gs.x = 1
	if parent_gs.y == 0:
		parent_gs.y = 1
	var local_size := Vector2(box_size.x * orig_scale.x / parent_gs.x, box_size.y * orig_scale.y / parent_gs.y)
	# Guard against degenerate zero from empty text.
	if local_size.x < 1.0:
		local_size.x = 1.0
	if local_size.y < 1.0:
		local_size.y = 1.0
	var new_shape := RectangleShape2D.new()
	new_shape.size = local_size
	new_shape.resource_local_to_scene = true
	coll.shape = new_shape

	# Position the collider at the tight text's visual center in parent-local space.
	# Tight rect is offset inside container by alignment (left/center/right) and
	# vertically centered. `position` is the Control's local top-left (already
	# includes anchor + 28px fudge offsets baked or not).
	var align_factor := 0.5
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_LEFT:
			align_factor = 0.0
		HORIZONTAL_ALIGNMENT_CENTER:
			align_factor = 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			align_factor = 1.0
		_:
			align_factor = 0.5

	# If position is still zero (parent bake hasn't run yet, Control uses
	# offset_* not position), fall back to anchor-derived placement.
	var top_left_local: Vector2
	if position != Vector2.ZERO:
		top_left_local = position
	else:
		var anchor = Vector2(0.5, 0.5)
		if parent.object_data != null and parent.object_data.has("anchor"):
			anchor = Vector2(parent.object_data["anchor"][0], parent.object_data["anchor"][1])
		top_left_local = Vector2(-anchor.x * container_size.x, (anchor.y - 1.0) * container_size.y)
		if BMFont:
			top_left_local += Vector2(5, 22)
			# _apply_bmfont_position adds (28,-18) after anchor, already included via deferred size,
			# but if we fallback early we must add it.
			top_left_local += Vector2(28, -18)
		else:
			top_left_local += Vector2(28, 28)
			top_left_local.y -= 10

	# Vertical placement: hyperPad `verticalAlignment` 0=Top,1=Center,2=Bottom (all sample labels 0=top).
	# Previous 0.5 (center) put the tight hitbox ~14px underneath the glyphs.
	var v_align_factor := 0.0
	if parent.object_data != null and parent.object_data.has("gameobjectdata"):
		var gd_v = parent.object_data["gameobjectdata"]
		if gd_v.has("verticalAlignment"):
			match int(gd_v["verticalAlignment"]):
				0:
					v_align_factor = 0.0
				1:
					v_align_factor = 0.5
				2:
					v_align_factor = 1.0
				_:
					v_align_factor = 0.0
	var offset_in_container = Vector2((container_size.x - box_size.x) * align_factor, (container_size.y - box_size.y) * v_align_factor)
	# Control's `scale` (baked for Dynamic) scales the offset and half-size in local space.
	var center_local = top_left_local + (offset_in_container + box_size * 0.5) * scale
	coll.position = center_local
	# Ensure the node's own scale doesn't double-scale the shape; shape size is
	# already in local units, and parent's global scale will be applied at
	# physics time. Reset any baked node scale on the shape itself.
	coll.scale = Vector2.ONE


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
