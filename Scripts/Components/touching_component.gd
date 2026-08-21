extends Node

var started_touching_to_trigger : Dictionary = {}

# Separate from started_touching_to_trigger: this fires every frame
# while held down, not once on initial click - keyed the same way
# (interpreter node -> Array of behavior_datas) so multiple While
# Touching behaviors on the same object all get registered correctly.
var while_touching_to_trigger : Dictionary = {}

var hovering : bool = false
var pressing : bool = false

# Our own Area2D + CollisionShape2D, built at runtime from whatever
# CollisionShape2D sibling the object already has. This decouples touch
# detection from the RigidBody2D's own physics body/collision shape -
# freezing, disabling collision, or otherwise messing with the body's
# physics no longer has any effect on whether touching still works.
var _touch_area : Area2D
var _touch_shape : CollisionShape2D

func set_touch_behavior(_behavior_data, _node : Node) -> void:
    if not started_touching_to_trigger.has(_node):
        started_touching_to_trigger[_node] = []

    var existing_entries: Array = started_touching_to_trigger[_node]
    var behavior_tag = _behavior_data.get("tag", null)

    for existing in existing_entries:
        if existing.get("tag", null) == behavior_tag:
            return

    existing_entries.append(_behavior_data)

func set_while_touching_behavior(_behavior_data, _node : Node) -> void:
    if not while_touching_to_trigger.has(_node):
        while_touching_to_trigger[_node] = []

    var existing_entries: Array = while_touching_to_trigger[_node]
    var behavior_tag = _behavior_data.get("tag", null)

    for existing in existing_entries:
        if existing.get("tag", null) == behavior_tag:
            return

    existing_entries.append(_behavior_data)

func _ready() -> void:
    # Godot calls _ready() bottom-up: this node's _ready() runs BEFORE
    # its parent's (HyperpadObject._ready(), which is where the
    # hyperPad-specific collision_layer/mask bits get OR'd onto the
    # body). Reading parent.collision_layer here would see the stale
    # pre-fixup default. call_deferred runs after the whole scene has
    # finished entering the tree, so the parent's _ready() has already
    # applied its layer changes by the time we copy them.
    call_deferred("_setup_touch_area")

func _setup_touch_area() -> void:
    var parent := get_parent()

    # Find the sibling CollisionShape2D that the object was already using
    # for its physics body, so we mirror the same shape for touch
    # detection. We don't reparent or remove it - the physics body keeps
    # its own shape untouched; we just point our Area2D's shape at the
    # same Shape2D resource.
    var source_shape_node : CollisionShape2D = null
    for child in parent.get_children():
        if child is CollisionShape2D:
            source_shape_node = child
            break

    _touch_area = Area2D.new()
    _touch_area.name = "TouchArea"
    # Areas don't need to be monitoring other areas/bodies for our purposes -
    # we only need it to receive mouse-cursor enter/exit, which Godot
    # delivers via CollisionObject2D.mouse_entered/mouse_exited regardless
    # of monitoring/monitorable, so keep it lightweight.
    _touch_area.monitoring = true
    _touch_area.monitorable = true
    _touch_area.input_pickable = true

    # Mouse picking is resolved against collision_layer, same as any other
    # CollisionObject2D - an Area2D left at the engine default (layer 1
    # only) can end up unreachable once HyperpadObject._ready() has OR'd
    # hyperPad's per-object layer bit onto the body. Mirror the parent
    # body's collision_layer/mask here so the touch area is picked
    # correctly regardless of what layer(s) the object landed on.
    if parent.has_method("get") and parent.get("layer") != null:
        var l := int(parent.layer)
        var layer_index := clampi(l - 1, 0, 31)
        var layer_mask := 1 << layer_index
        # Include bit 0 (layer 1) so passable bodies (collidable==0, layer 1)
        # are still seen by While Colliding/Collision Event even though they
        # have no physical collision. Same-layer physical bodies still match
        # via layer_mask.
        _touch_area.collision_layer = layer_mask | 1
        _touch_area.collision_mask = layer_mask | 1
    elif parent is CollisionObject2D:
        _touch_area.collision_layer = (parent as CollisionObject2D).collision_layer | 1
        _touch_area.collision_mask = (parent as CollisionObject2D).collision_mask | 1

    parent.add_child(_touch_area)

    _touch_shape = CollisionShape2D.new()
    _touch_shape.name = "TouchCollisionShape2D"

    if source_shape_node != null and source_shape_node.shape != null:
        # Share the same Shape2D resource (not a duplicate) so if a
        # behavior resizes the body's collision shape at runtime, the
        # touch area's shape changes with it automatically - they're
        # literally the same Resource object. Local transform is mirrored
        # once here relative to the shared parent so the touch area lines
        # up with the original collider.
        _touch_shape.shape = source_shape_node.shape
        _touch_shape.position = source_shape_node.position
        _touch_shape.rotation = source_shape_node.rotation
        _touch_shape.scale = source_shape_node.scale
        _touch_shape.disabled = source_shape_node.disabled
    else:
        # No sibling CollisionShape2D found (shouldn't normally happen) -
        # fall back to a small default shape so touching still works
        # rather than silently doing nothing.
        var fallback := RectangleShape2D.new()
        fallback.size = Vector2(64, 64)
        _touch_shape.shape = fallback

    _touch_area.add_child(_touch_shape)

    _touch_area.mouse_entered.connect(mouse_enter)
    _touch_area.mouse_exited.connect(mouse_exit)

func mouse_enter():
    hovering = true

func mouse_exit():
    hovering = false
    # If the pointer leaves the object while still held, stop treating it
    # as "being touched" - otherwise While Touching would keep firing for
    # an object the pointer isn't over anymore.
    pressing = false

func _input(_event: InputEvent) -> void:
    if hovering:
        if Input.is_action_just_pressed("left_click"):
            pressing = true

            for key in started_touching_to_trigger:
                for behavior_data in started_touching_to_trigger[key]:
                    key.run_next_behavior(behavior_data)

    if Input.is_action_just_released("left_click"):
        pressing = false

func _process(_delta: float) -> void:
    if not pressing:
        return

    var parent = get_parent() as Node2D

    for key in while_touching_to_trigger:
        for behavior_data in while_touching_to_trigger[key]:
            var mouse_pos = parent.get_global_mouse_position()
            var screen_height = get_viewport().get_visible_rect().size.y

            # Flip to Y-up, origin bottom-left: Godot's global_mouse_position
            # is Y-down from the top-left. screen_height - mouse_pos.y puts
            # (0,0) at the bottom and makes +Y point up, matching
            # hyperPad/cocos2d's own convention (same flip already confirmed
            # correct in Move_To_Object's relativeAnchor handling).
            var flipped_y = screen_height - mouse_pos.y

            key.output_store[behavior_data["tag"]] = {
                "x": mouse_pos.x,
                "y": flipped_y,
                "dt": _delta,
            }
            key.run_next_behavior(behavior_data)