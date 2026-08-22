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

# ---------- SHAKE ----------------------------------------------------------
# Shake is an additive offset applied on top of whatever global_position
# ends up being from follow/tween logic, so it composes instead of
# fighting other camera behaviors for ownership of global_position.

var _shake_offset: Vector2 = Vector2.ZERO
var _shake_tween: Tween = null

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

## Shakes the camera with amplitude decaying linearly from
## (amplitude_x, amplitude_y) down to 0 over `duration` seconds.
## Interruptible: calling this again while a shake is in progress kills
## the old shake (snapping its offset back out) and starts fresh.
## Returns once the shake has fully decayed to 0.
func shake(amplitude_x: float, amplitude_y: float, duration: float) -> void:
	# Interrupt any in-progress shake and remove its offset immediately,
	# so offsets from two overlapping shakes never stack/compound.
	if is_instance_valid(_shake_tween) and _shake_tween.is_valid():
		_shake_tween.kill()
	global_position -= _shake_offset
	_shake_offset = Vector2.ZERO

	if duration <= 0.0 or (amplitude_x == 0.0 and amplitude_y == 0.0):
		return

	# Tween a single scalar 1.0 -> 0.0 representing the decaying envelope;
	# each step we derive a new random offset scaled by that envelope and
	# swap it in for the previous frame's offset. This gives "random
	# jitter whose magnitude decays linearly to 0 over duration" without
	# needing a custom _process loop here — matches the tween-driven style
	# used by Move/Scale/Zoom_Camera elsewhere in this codebase.
	var envelope := {"t": 1.0}
	var tween = create_tween()
	_shake_tween = tween
	tween.tween_method(
		func(t: float):
			global_position -= _shake_offset
			_shake_offset = Vector2(
				randf_range(-amplitude_x, amplitude_x) * t,
				randf_range(-amplitude_y, amplitude_y) * t
			)
			global_position += _shake_offset,
		1.0, 0.0, duration
	)

	await tween.finished

	if _shake_tween == tween:
		_shake_tween = null
		global_position -= _shake_offset
		_shake_offset = Vector2.ZERO