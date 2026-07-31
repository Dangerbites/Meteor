extends Node

# While Colliding — { interpreter: [behavior_data, ...] }
var while_nodes_to_check : Dictionary = {}
# Collision Event — { interpreter: [behavior_data, ...] }
var nodes_to_check : Dictionary = {}

var parent: RigidBody2D
var colliding_bodies: Dictionary = {}  # body -> true, acts as a set

func _ready() -> void:
	parent = get_parent() as RigidBody2D
	if parent == null:
		print("ERROR: parent is not a RigidBody2D!")
		return
	parent.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	parent.contact_monitor = true
	parent.max_contacts_reported = 64
	parent.body_entered.connect(_on_parent_body_entered)
	parent.body_exited.connect(_on_parent_body_exited)

func _on_parent_body_entered(body: Node) -> void:
	#print("body_entered fired on: ", parent.name, " <- ", body.name)
	if body is RigidBody2D:
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
	if while_nodes_to_check.is_empty() and nodes_to_check.is_empty():
		parent.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	else:
		parent.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

	if colliding_bodies.size() > 0:
		for body in colliding_bodies:
			for node in nodes_to_check:
				for behavior_data in nodes_to_check[node]:
					if behavior_data["actions"]["collisionEvent"]["value"] == "While Colliding":
						var objectBList = node.get_target_nodes(behavior_data, "objectB")
						for objectB in objectBList:
							if objectB == body:
								node.run_next_behavior(behavior_data)
								#print("DO SOMETHING COLLISION WITH : ", node.get_parent().name)

			for node in while_nodes_to_check:
				for behavior_data in while_nodes_to_check[node]:
					var objectBList = node.get_target_nodes(behavior_data, "objectB")
					for objectB in objectBList:
						if objectB == body:
							#print("MATCH — calling run_next_behavior")
							node.run_next_behavior(behavior_data)

func _process(delta: float) -> void:
	return

	if not while_nodes_to_check.is_empty():
		ImGui.Begin(get_parent().name)
		var pretty_text = JSON.stringify(while_nodes_to_check, "  ", false)
		ImGui.TextWrapped(pretty_text)
		ImGui.SameLine()
		if ImGui.SmallButton("copy"):
			DisplayServer.clipboard_set(pretty_text)
		ImGui.End()
