extends Node2D

# "collidable": 0,
# 0 = means that it is passable. but it can still get triggered by collision events and while collision and started collision etc.
# 1 = means that it should have collision normally

#"physics_mode": "Dynamic",
#dynamic = normal. it should have phyisics like freeze = false

#"physics_mode": "Kinematic",
# Kinematic = it means that it is frozen freeze/frozen = true. but it can still get triggered by collision events and while collision and started collision etc.

var ui_element : bool = false
var id : String
var obj_name : String
var object_data
var layer : int

func _ready() -> void:
    layer = int(object_data.get("layer", 1))

    var body := get_node(".") as CollisionObject2D
    if body != null:
        # Godot's Layer N (as shown in the editor) is bit index N-1, so
        # hyperPad layer 1 -> bit 0 (mask value 1), not bit 1 like
        # "1 << layer" produced before.
        var layer_index := clampi(layer - 1, 0, 31)
        var layer_mask := 1 << layer_index

        # OR the bit in instead of assigning with "=". Assigning
        # overwrote whatever collision_layer/mask the node already had
        # (Godot's default: Layer 1 on both), which is what
        # touchingComponent's Area2D relies on to detect these bodies
        # at all - once that default bit was gone, "touching"/"while
        # touching" stopped firing. This keeps the default intact while
        # adding the hyperPad-specific layer on top, so per-layer
        # separation works without breaking existing touch detection.
        body.collision_layer |= layer_mask
        body.collision_mask |= layer_mask


    visible = !object_data["gameobjectdata"]["hidden"]

    ui_element = object_data["ui_element"]
    obj_name = object_data["name"]

    name = obj_name

    var data_x = object_data["position"][0]
    var data_y = object_data["position"][1]
    var viewport_size = get_viewport().get_visible_rect().size

    if ui_element:
        global_position = Vector2(
            data_x * viewport_size.x,
            (1.0 - data_y) * viewport_size.y
        )
    else:
        global_position = Vector2(data_x, viewport_size.y - data_y)

    scale = Vector2(object_data["scale"][0], object_data["scale"][1])
    rotation_degrees = object_data["rotation"]

    modulate = Color(object_data["gameobjectdata"]["tint"]["UIRed"], object_data["gameobjectdata"]["tint"]["UIGreen"], object_data["gameobjectdata"]["tint"]["UIBlue"], object_data["gameobjectdata"]["tint"]["UIAlpha"])

    z_index = object_data["z_index"]

    # O(1) UUID -> Node lookup cache, so get_node_from_UUID doesn't need
    # to linearly scan every HyperpadObject in the scene on every call -
    # critical for large scenes / hot paths like collision checks that
    # call it every physics frame. Every object type routes through this
    # shared script's _ready(), so registering here covers Graphic, TTF
    # Label, Empty, Joystick, HealthBar, and LifeIndicator all at once.
    GlobalBehaviorData.register_uuid(id, self)

func _exit_tree() -> void:
    GlobalBehaviorData.unregister_uuid(id, self)