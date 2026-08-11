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

    apply_collision_shape(tex_size)

    # position can stay as is - it's a node property, not shared
    collision.position = position


# hyperPad collision shape setter. hyperPad stores its own shape choice
# per-object ("Default" | "Rectangle" | "Circle" | "Polygon") separately
# from the texture, under top-level "collision_shape" / "collision_points".
# "Default" means hyperPad wasn't given an explicit shape, so we fall back
# to the original behavior (a rect matching the scaled texture size) -
# kept as its own branch below so it's byte-for-byte the old code path
# and can't be broken by the new cases.
func apply_collision_shape(tex_size: Vector2) -> void:
    if collision == null:
        return

    var shape_type: String = object_data.get("collision_shape", "Default")

    match shape_type:
        "Rectangle":
            _apply_rectangle_collision(tex_size)
        "Circle":
            _apply_circle_collision(tex_size)
        "Polygon":
            _apply_polygon_collision()
        _:
            _apply_default_collision(tex_size)


# Original behavior, unchanged: a RectangleShape2D sized to the texture.
func _apply_default_collision(tex_size: Vector2) -> void:
    var new_shape = collision.shape.duplicate(true)
    collision.shape = new_shape
    collision.shape.size = tex_size * scale


func _apply_rectangle_collision(tex_size: Vector2) -> void:
    var points = object_data.get("collision_points", [])
    var new_shape := RectangleShape2D.new()

    if points is Array and points.size() >= 2:
        # Rectangle points, if present, are two opposite corners
        # (mirrors the {{x,y},{w,h}} rect data hyperPad exports elsewhere).
        var p0 = Vector2(points[0][0], points[0][1])
        var p1 = Vector2(points[1][0], points[1][1])
        new_shape.size = Vector2(abs(p1.x - p0.x), abs(p1.y - p0.y)) * scale
    else:
        # No explicit points - fall back to texture size like Default.
        new_shape.size = tex_size * scale

    collision.shape = new_shape


func _apply_circle_collision(tex_size: Vector2) -> void:
    var new_shape := CircleShape2D.new()
    var diameter: float = min(tex_size.x, tex_size.y)
    var avg_scale: float = (abs(scale.x) + abs(scale.y)) * 0.5
    new_shape.radius = (diameter * 0.5) * avg_scale
    collision.shape = new_shape


# hyperPad/Cocos2d polygon points are stored relative to the object's
# center in Cocos2d's Y-UP space. Godot's 2D space is Y-DOWN, so a point
# that Cocos2d drew above center (positive Y) needs to end up below
# center in Godot, and vice versa - hence the Y negation below. Without
# this flip the collision polygon renders as a vertical mirror of the
# sprite it's supposed to wrap.
func _apply_polygon_collision() -> void:
    var points = object_data.get("collision_points", [])
    if not (points is Array) or points.is_empty():
        return

    var packed := PackedVector2Array()
    for p in points:
        packed.append(Vector2(p[0], -p[1]) * scale)

    var new_shape := ConvexPolygonShape2D.new()
    new_shape.points = packed
    collision.shape = new_shape