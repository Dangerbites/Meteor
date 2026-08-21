extends Node

# While Colliding — { interpreter: [behavior_data, ...] }
var while_nodes_to_check : Dictionary = {}
# Collision Event — { interpreter: [behavior_data, ...] }
var nodes_to_check : Dictionary = {}

var parent: Node2D
var colliding_bodies: Dictionary = {}  # body -> true, acts as a set
var touch_area: Area2D

func _ready() -> void:
	parent = get_parent() as Node2D
	if parent == null:
		print("ERROR: parent is not a Node2D!")
		return
	call_deferred("_setup_collision_detection")

func _setup_collision_detection() -> void:
	touch_area = parent.get_node_or_null("TouchArea") as Area2D
	if touch_area == null:
		await get_tree().process_frame
		touch_area = parent.get_node_or_null("TouchArea") as Area2D

	if touch_area == null:
		print("WARNING: CollisionDetectionComponent could not find TouchArea on parent: ", parent.name)
		return

	# Scenery: frozen + passable with no collision behaviors, but still touchable
	# (TouchArea mouse picking uses input_pickable, not monitoring).
	var is_scenery := false
	if parent.get("object_data") != null:
		is_scenery = str(parent.object_data.get("physics_mode", "Dynamic")) == "Scenery"
	if is_scenery:
		touch_area.monitoring = false
		touch_area.monitorable = false
		set_physics_process(false)
		return

	touch_area.monitoring = true
	touch_area.monitorable = true
	if not touch_area.body_entered.is_connected(_on_parent_body_entered):
		touch_area.body_entered.connect(_on_parent_body_entered)
	if not touch_area.body_exited.is_connected(_on_parent_body_exited):
		touch_area.body_exited.connect(_on_parent_body_exited)

func _on_parent_body_entered(body: Node) -> void:
	if body == parent:
		return
	if body is Node2D:
		colliding_bodies[body] = true
		#print(parent.name, " started colliding with: ", body.name)

		for node in nodes_to_check:
			for behavior_data in nodes_to_check[node]:
				if behavior_data["actions"]["collisionEvent"]["value"] == "Started Colliding":
					var objectBList = node.get_target_nodes(behavior_data, "objectB")
					for objectB in objectBList:
						if objectB == body:
							node.run_next_behavior(behavior_data)

func _on_parent_body_exited(body: Node) -> void:
	if colliding_bodies.has(body):
		colliding_bodies.erase(body)
		#print(parent.name, " stopped colliding with: ", body.name)

		for node in nodes_to_check:
			for behavior_data in nodes_to_check[node]:
				if behavior_data["actions"]["collisionEvent"]["value"] == "Stopped Colliding":
					var objectBList = node.get_target_nodes(behavior_data, "objectB")
					for objectB in objectBList:
						if objectB == body:
							node.run_next_behavior(behavior_data)

func _physics_process(_delta: float) -> void:
	if colliding_bodies.size() > 0:
		for body in colliding_bodies:
			for node in nodes_to_check:
				for behavior_data in nodes_to_check[node]:
					if behavior_data["actions"]["collisionEvent"]["value"] == "While Colliding":
						if _matches_object_b(node, behavior_data, body):
							node.run_next_behavior(behavior_data)

			#return
			for node in while_nodes_to_check:
				for behavior_data in while_nodes_to_check[node]:
					if _matches_object_b(node, behavior_data, body):
						node.run_next_behavior(behavior_data)

func _matches_object_b(node, behavior_data: Dictionary, body: Node) -> bool:
	var object_b_field = behavior_data.get("actions", {}).get("objectB", {})

	if object_b_field.get("__class__", "") == "NSNull" or object_b_field.is_empty():
		return true

	# groups filter — check if body itself has the group, O(1)-ish,
	# no need to enumerate the whole group
	var groups: Array = behavior_data.get("groups", [])
	if groups != null and not groups.is_empty():
		for tag in groups:
			if body.is_in_group(tag):
				return true
		return false

	# single UUID target — resolve once via cached UUID lookup, not a scan
	var object_id = str(node.check_value_key(object_b_field))
	var resolved = node.get_node_from_UUID(object_id)
	return resolved == body

#func _process(delta: float) -> void:
#	return
#
#	if not while_nodes_to_check.is_empty():
#		ImGui.Begin(get_parent().name)
#		var pretty_text = JSON.stringify(while_nodes_to_check, "  ", false)
#		ImGui.TextWrapped(pretty_text)
#		ImGui.SameLine()
#		if ImGui.SmallButton("copy"):
#			DisplayServer.clipboard_set(pretty_text)
#		ImGui.End()
