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
	var collidable := int(object_data.get("collidable", 1))
	var physics_mode := str(object_data.get("physics_mode", "Dynamic"))

	var body := get_node(".") as RigidBody2D
	if body != null:
		var layer_index := clampi(layer - 1, 0, 31)
		var layer_mask := 1 << layer_index

		# Scenery overrides collidable: always frozen + fully passable, no
		# collision events fire on it. Touching still works because the
		# TouchArea Area2D uses input_pickable, not the body's
		# collision_layer. collidable alone (without Scenery) keeps the
		# hyperPad per-layer bit so within-layer collision works.
		# Passable (collidable==0) stays detectable for While Colliding via
		# shared bit 0 (layer 1) so Area (mask layer|1) still sees it, but
		# physical collision is disabled (mask 0).
		if physics_mode == "Scenery":
			body.collision_layer = 0
			body.collision_mask = 0
		elif collidable == 1:
			body.collision_layer = layer_mask
			body.collision_mask = layer_mask
		else:
			body.collision_layer = 1
			body.collision_mask = 0

		if physics_mode == "Dynamic":
			body.freeze = false
		elif physics_mode == "Kinematic" or physics_mode == "Scenery":
			body.freeze = true

		# Must be set on the RigidBody2D (body), not on self before body exists.
		# Also only Dynamic respects mass — Kinematic/Scenery are frozen so 1000 does nothing, which is expected.
		var friction_val := float(object_data.get("friction", 0.35))
		var restitution_val := float(object_data.get("restitution", 0.0))
		var hyperpad_mass := float(object_data.get("mass", 20.0))
		var physics_material := PhysicsMaterial.new() as PhysicsMaterial
		physics_material.friction = friction_val + 0.2
		physics_material.absorbent = restitution_val
		body.physics_material_override = physics_material
		body.mass = hyperpad_mass


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

	if physics_mode == "Dynamic":
		bake_scale_into_children()

	modulate = Color(object_data["gameobjectdata"]["tint"]["UIRed"], object_data["gameobjectdata"]["tint"]["UIGreen"], object_data["gameobjectdata"]["tint"]["UIBlue"], object_data["gameobjectdata"]["tint"]["UIAlpha"])

	# Layers must always outrank in-layer object ordering. The parent
	# layer container (EmulatorManager._get_layer_container) puts each
	# layer in its own LAYER_Z_BAND-wide band of the z_index space, so we
	# clamp this object's z_index to OBJECT_Z_CLAMP (comfortably inside
	# half a band) before assigning it. z_as_relative defaults to true
	# on Node2D, so this value is added to the layer container's
	# z_index rather than replacing it - clamping keeps that sum from
	# ever spilling into a neighboring layer's band, no matter how
	# extreme the tap's authored z_index is.
	z_index = clampi(int(object_data["z_index"]), -EmulatorManager.OBJECT_Z_CLAMP, EmulatorManager.OBJECT_Z_CLAMP)

	# O(1) UUID -> Node lookup cache, so get_node_from_UUID doesn't need
	# to linearly scan every HyperpadObject in the scene on every call -
	# critical for large scenes / hot paths like collision checks that
	# call it every physics frame. Every object type routes through this
	# shared script's _ready(), so registering here covers Graphic, TTF
	# Label, Empty, Joystick, HealthBar, and LifeIndicator all at once.
	GlobalBehaviorData.register_uuid(id, self)

func bake_scale_into_children() -> void:
	if scale == Vector2.ONE:
		return
	var s := scale
	scale = Vector2.ONE
	for child in get_children():
		if child is CollisionShape2D:
			var col := child as CollisionShape2D
			if col.shape != null:
				var dup = col.shape.duplicate()
				if dup is RectangleShape2D:
					(dup as RectangleShape2D).size *= s
				elif dup is CircleShape2D:
					var avg = (abs(s.x) + abs(s.y)) * 0.5
					(dup as CircleShape2D).radius *= avg
				elif dup is CapsuleShape2D:
					var cap := dup as CapsuleShape2D
					cap.radius *= (abs(s.x) + abs(s.y)) * 0.5
					cap.height *= abs(s.y)
				elif dup is ConvexPolygonShape2D:
					var convex := dup as ConvexPolygonShape2D
					var pts := convex.points
					for i in pts.size():
						pts[i] = Vector2(pts[i].x * s.x, pts[i].y * s.y)
					convex.points = pts
				elif dup is SegmentShape2D:
					var seg := dup as SegmentShape2D
					seg.a *= s
					seg.b *= s
				col.shape = dup
			col.position *= s
			if col.scale != Vector2.ONE:
				col.scale *= s
		elif child is Node2D:
			child.position *= s
			child.scale *= s
			# Area2D children (TouchArea) are already handled by scaling the
			# Area itself — its global transform scales grandchildren, so don't
			# walk grandchildren or we'd double-scale their world size/offset.
		elif child is Control:
			child.position *= s
			if child is ColorRect:
				var cr := child as ColorRect
				cr.offset_left *= s.x
				cr.offset_right *= s.x
				cr.offset_top *= s.y
				cr.offset_bottom *= s.y
				cr.size *= s
			else:
				child.scale *= s

func _exit_tree() -> void:
	GlobalBehaviorData.unregister_uuid(id, self)