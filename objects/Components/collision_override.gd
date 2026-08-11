extends Node
# Attach as a sibling of "CollisionShape2D" under any HyperpadObject root
# (Empty, Graphic, TTFLabel, Joystick, HealthBar, LifeIndicator - all of
# them name their collision node "CollisionShape2D" directly under the
# root). Waits one frame before reading object_data, since that's set by
# hyperpad_object.gd's _ready() on the parent and sibling _ready() order
# isn't guaranteed - without the wait this can run before object_data
# exists yet.

# Debug toggle: when false, Polygon points are used as-is (no Y flip).
# Flip this off if it turns out hyperPad's polygon data doesn't actually
# need mirroring for your scenes.
@export var flip_polygon_y: bool = false


func _ready() -> void:
    var object_data = get_parent().object_data
    var shape_type: String = object_data.get("collision_shape", "Default")

    if shape_type == "Default":
        return

    await get_tree().process_frame

    var collision := get_parent().get_node_or_null("CollisionShape2D") as CollisionShape2D
    if collision == null:
        return

    match shape_type:
        "Rectangle":
            _apply_rectangle(collision, object_data)
        "Circle":
            _apply_circle(collision, object_data)
        "Polygon":
            _apply_polygon(collision, object_data)


# hyperPad Rectangle/Circle shapes usually ship with an empty
# collision_points array - the real data lives in
# gameobjectdata.collisionArea as a cocos2d NSValue rect string:
# "{{x, y}, {w, h}}". IMPORTANT: use the UNTRANSFORMED "collisionArea",
# not "collisionAreaTransformed" - the Transformed version already has
# the object's scale baked in, but CollisionShape2D is a child of the
# scaled RigidBody2D root, so Godot applies that scale again through the
# node hierarchy. Using the pre-scaled rect double-scaled every shape.
func _parse_ns_rect(rect_str: String) -> Rect2:
    # "{{x, y}, {w, h}}" -> four floats, in order x, y, w, h
    var nums := Array(rect_str.replace("{", "").replace("}", "").split(","))
    for i in nums.size():
        nums[i] = float(String(nums[i]).strip_edges())
    return Rect2(nums[0], nums[1], nums[2], nums[3])


func _get_area_rect(object_data) -> Rect2:
    var points = object_data.get("collision_points", [])
    if points is Array and points.size() >= 2:
        var p0 = Vector2(points[0][0], points[0][1])
        var p1 = Vector2(points[1][0], points[1][1])
        return Rect2(p0, p1 - p0).abs()

    var area = object_data.get("gameobjectdata", {}).get("collisionArea")
    if area == null or not area.has("NS.rectval"):
        return Rect2()

    return _parse_ns_rect(area["NS.rectval"])


func _apply_rectangle(collision: CollisionShape2D, object_data) -> void:
    var rect := _get_area_rect(object_data)
    if rect.size == Vector2.ZERO:
        return

    var new_shape := RectangleShape2D.new()
    new_shape.size = rect.size
    collision.shape = new_shape


    # No offset - shape stays centered on the node.


func _apply_circle(collision: CollisionShape2D, object_data) -> void:
    var rect := _get_area_rect(object_data)
    if rect.size == Vector2.ZERO:
        return

    var new_shape := CircleShape2D.new()
    new_shape.radius = max(rect.size.x, rect.size.y) #* 0.5
    collision.shape = new_shape
    # No offset - shape stays centered on the node.


# Mirrors every point vertically around the POLYGON'S OWN min/max Y
# (not around y=0). Simple negation (-p.y) only swaps top/bottom
# correctly when the points are symmetric about y=0 - hyperPad's
# points usually aren't (e.g. ranging roughly -105 to +80), so negating
# also shifts the whole shape instead of just flipping it in place.
# Mirroring about the shape's own min/max guarantees the highest point
# becomes exactly as far below center as it was above, with no shift.
# Gated by flip_polygon_y so it can be toggled off from the Inspector
# in case the data turns out not to need mirroring at all.
func _apply_polygon(collision: CollisionShape2D, object_data) -> void:
    var points = object_data.get("collision_points", [])
    if not (points is Array) or points.is_empty():
        return

    var packed := PackedVector2Array()

    if flip_polygon_y:
        var min_y := INF
        var max_y := -INF
        for p in points:
            min_y = min(min_y, float(p[1]))
            max_y = max(max_y, float(p[1]))

        for p in points:
            var flipped_y: float = min_y + max_y - float(p[1])
            packed.append(Vector2(p[0], flipped_y))
    else:
        for p in points:
            packed.append(Vector2(p[0], p[1]))

    var new_shape := ConvexPolygonShape2D.new()
    new_shape.points = packed
    collision.shape = new_shape
    # No offset - shape stays centered on the node.