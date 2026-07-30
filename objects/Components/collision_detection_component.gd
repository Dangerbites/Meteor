extends Node

# While Colliding
var while_nodes_to_check : Dictionary = {}
# Collision Event
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
	parent.max_contacts_reported = 4
	parent.body_entered.connect(_on_parent_body_entered)
	parent.body_exited.connect(_on_parent_body_exited)
	#print("Connected body_entered on: ", parent.name)

func _on_parent_body_entered(body: Node) -> void:
	if body is RigidBody2D:
		colliding_bodies[body] = true
		#print(parent.name, " started colliding with: ", body.name)

		for node in nodes_to_check:
			if nodes_to_check[node]["actions"]["collisionEvent"]["value"] == "Started Colliding":
				var objectBList = node.get_target_nodes(nodes_to_check[node], "objectB")
				for objectB in objectBList:
					if objectB == body:
						node.run_next_behavior(nodes_to_check[node])

func _on_parent_body_exited(body: Node) -> void:
	if colliding_bodies.has(body):
		colliding_bodies.erase(body)
		#print(parent.name, " stopped colliding with: ", body.name)

		for node in nodes_to_check:
			if nodes_to_check[node]["actions"]["collisionEvent"]["value"] == "Stopped Colliding":
				var objectBList = node.get_target_nodes(nodes_to_check[node], "objectB")
				for objectB in objectBList:
					if objectB == body:
						node.run_next_behavior(nodes_to_check[node])

func _physics_process(_delta: float) -> void:
	if while_nodes_to_check.is_empty() and nodes_to_check.is_empty():
		parent.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	else:
		parent.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

	# Runs every physics frame WHILE colliding with anything
	if colliding_bodies.size() > 0:
		for body in colliding_bodies:
			#print(parent.name, " is currently colliding with: ", body.name)

			for node in nodes_to_check:
				if nodes_to_check[node]["actions"]["collisionEvent"]["value"] == "While Colliding":
					var objectBList = node.get_target_nodes(nodes_to_check[node], "objectB")
					for objectB in objectBList:
						if objectB == body:
							node.run_next_behavior(nodes_to_check[node])
							print("DO SOMETHING COLLISION WITH : ", node.get_parent().name)

			for node in while_nodes_to_check:
				var objectBList = node.get_target_nodes(while_nodes_to_check[node], "objectB")
				for objectB in objectBList:
					if objectB == body:
						node.run_next_behavior(while_nodes_to_check[node])
						print("DO SOMETHING COLLISION WITH : ", node.get_parent().name)
