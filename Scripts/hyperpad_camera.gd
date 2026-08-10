extends Camera2D

# Set by the "Camera Follow" behavior via set_follow_target().
# This is a DELTA follow, not a snap-to-target follow: the camera stays
# exactly where it currently is, and only moves by however much the
# target moves each frame (scaled per-axis by follow_x / follow_y).
# "Camera To Object" is a separate one-shot teleport and does not touch
# any of this state.

var follow_target: Node2D = null
var follow_x: bool = true
var follow_y: bool = true

var _last_target_position: Vector2 = Vector2.ZERO
var _has_last_position: bool = false

func _ready() -> void:
	if not is_in_group("HyperpadCamera"):
		add_to_group("HyperpadCamera")

func set_follow_target(node: Node2D, follows_x: bool = true, follows_y: bool = true) -> void:
	follow_target = node
	follow_x = follows_x
	follow_y = follows_y

	if is_instance_valid(node):
		# Seed with the target's CURRENT position so the camera doesn't
		# jump on the first frame — it only reacts to movement from here on.
		_last_target_position = node.global_position
		_has_last_position = true
	else:
		_has_last_position = false

func clear_follow_target() -> void:
	follow_target = null
	_has_last_position = false

func _process(_delta: float) -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		return

	var current_position: Vector2 = follow_target.global_position

	if not _has_last_position:
		_last_target_position = current_position
		_has_last_position = true
		return

	var movement_delta: Vector2 = current_position - _last_target_position

	if not follow_x:
		movement_delta.x = 0.0
	if not follow_y:
		movement_delta.y = 0.0

	global_position += movement_delta
	_last_target_position = current_position