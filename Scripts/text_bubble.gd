extends Node2D

@onready var TextLabel : RichTextLabel = %text
# Typed as Control (not ColorRect) because setup() may swap this node for a
# TextureRect when a tail graphic is supplied - ColorRect and TextureRect
# are unrelated siblings under Control, so a shared base type is required
# for the reassignment below to type-check.
@onready var Tail : Control = %tail

## Extra spaces added to each side of the text before it's measured/shown,
## e.g. padding_spaces = 1 turns "test" into " test ". Simple and matches
## how Hyperpad itself pads bubble text.
@export var padding_spaces: int = 1

@export var init_scale : Vector2 = Vector2.ONE

# Base (authored-in-editor) sizes, captured on _ready() so we can grow the
# bubble from its original proportions rather than hardcoding numbers here.
var _base_label_size: Vector2
var _base_label_center: Vector2
var _base_tail_size: Vector2
var _tail_gap: float = 0.0  # authored gap between label bottom and tail top

const FADE_DURATION := 0.3
const SPAWN_SCALE_DURATION := 0.2

func _ready() -> void:
	scale = init_scale

	_base_label_size = TextLabel.size
	_base_label_center = TextLabel.position + TextLabel.size / 2.0
	_base_tail_size = Tail.size
	_tail_gap = Tail.position.y - (TextLabel.position.y + TextLabel.size.y)

	# fit_content only grows the RichTextLabel's *minimum* size; the control
	# itself still needs to be resized to that minimum for the StyleBoxFlat
	# background / clipping to track the text.
	TextLabel.fit_content = true
	TextLabel.bbcode_enabled = false

	# top_level detaches this node's transform AND modulate from inheriting
	# the parent's — without this, a colored/tinted owner object would tint
	# the bubble too. We still manually sync our global_position from the
	# owner every frame (see _process) so it visually stays attached while
	# remaining a real child (freed with the owner, findable in the tree,
	# etc).
	top_level = true
	modulate = Color.WHITE

var _follow_target: Node2D = null
var _follow_local_position: Vector2 = Vector2.ZERO

func _process(_delta: float) -> void:
	if _follow_target != null and is_instance_valid(_follow_target):
		global_position = _follow_target.global_position + _follow_local_position

## Configures the bubble from a Text Bubble behavior's resolved fields and
## starts its lifecycle (grow-to-fit -> show for `duration` -> fade -> free).
## `owner_node` is the Node2D this bubble is anchored to (behavior's objectA);
## the bubble becomes its child so it inherits position automatically.
func setup(
	owner_node: Node2D,
	text: String,
	duration: float,
	width: float,
	anchor_percent: Vector2,       # relativeAnchorA_x/y, 0-100
	pixel_offset: Vector2,         # anchorA_x/y, raw pixel nudge
	set_font: bool,
	font: Font,
	font_color: Color,
	font_size: int,
	set_graphic: bool,
	bubble_graphic: Texture2D,
	tail_graphic: Texture2D,
	margins: Dictionary             # {left, top, right, bottom} - tail alignment margins
) -> void:
	owner_node.add_child(self)

	# Spawn hidden-scaled; the actual pop-in tween happens after we've
	# resized/positioned below, so it animates from the correct final spot
	# instead of visibly snapping into place first.
	scale = Vector2.ZERO

	if set_font:
		if font != null:
			TextLabel.add_theme_font_override("normal_font", font)
		TextLabel.add_theme_color_override("default_color", font_color)
		TextLabel.add_theme_font_size_override("normal_font_size", font_size)

	if set_graphic:
		if bubble_graphic != null:
			var style := StyleBoxTexture.new()
			style.texture = bubble_graphic
			# Hyperpad recommends 9-slice bubble graphics; StyleBoxTexture's
			# default margins (0) mean no slicing, so anyone relying on 9-slice
			# stretch should set margins on the returned StyleBoxTexture - we
			# leave it to Set_Graphic_v1_26-style callers to refine if needed.
			TextLabel.add_theme_stylebox_override("normal", style)
		if tail_graphic != null:
			# Swap the ColorRect tail for a TextureRect so a real tail
			# graphic can be shown. ColorRect and TextureRect are unrelated
			# Control subclasses (no cast between them works), so instead of
			# casting we build the replacement, splice it into the tree at
			# the same index, and repoint Tail (typed as Control) at it.
			var texture_tail := TextureRect.new()
			texture_tail.name = Tail.name
			texture_tail.texture = tail_graphic
			texture_tail.rotation = Tail.rotation
			texture_tail.size = Tail.size
			texture_tail.position = Tail.position
			texture_tail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

			var tail_parent := Tail.get_parent()
			var tail_idx := Tail.get_index()
			var old_tail := Tail

			tail_parent.remove_child(old_tail)
			old_tail.queue_free()
			tail_parent.add_child(texture_tail)
			tail_parent.move_child(texture_tail, tail_idx)

			Tail = texture_tail

	TextLabel.text = _pad_text(text)

	# "width" from Hyperpad is a MAX width, not a fixed width: the bubble
	# should size to the text's natural (unwrapped) width and only wrap
	# once that exceeds this cap. autowrap must be off to measure the
	# unwrapped width, then we decide whether to turn wrapping on.
	TextLabel.autowrap_mode = TextServer.AUTOWRAP_OFF
	TextLabel.custom_minimum_size.x = 0.0
	TextLabel.size.x = 0.0

	# Let fit_content settle the label's minimum size for the unwrapped
	# text before we measure it (fit_content resizes are deferred
	# internally, hence the frame waits).
	await get_tree().process_frame
	await get_tree().process_frame

	var natural_width = TextLabel.get_minimum_size().x

	if width > 0.0 and natural_width > width:
		# Text is wider than the max — cap the width and let it wrap.
		TextLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		TextLabel.custom_minimum_size.x = width
		TextLabel.size.x = width
		await get_tree().process_frame
		await get_tree().process_frame
	# else: leave autowrap off and width at its natural (content) size —
	# no cap was hit, so the bubble stays exactly as wide as the text.

	_resize_to_fit()
	_position_on_owner(owner_node, anchor_percent, pixel_offset, margins)

	# _position_on_owner() just set global_position for this frame's owner
	# position; store the offset so _process() can keep re-deriving
	# global_position as the owner moves, without recomputing anchors
	# every frame.
	_follow_target = owner_node
	_follow_local_position = global_position - owner_node.global_position

	await _scale_in()

	if duration > 0.0:
		await get_tree().create_timer(duration).timeout

	await _scale_out_and_free()

## Wraps text in padding_spaces worth of literal spaces on each side, e.g.
## padding_spaces = 1 turns "test" into " test ".
func _pad_text(text: String) -> String:
	var pad = " ".repeat(padding_spaces)
	return pad + text + pad

## Grows the label (and moves the tail to stay attached beneath it) to match
## the RichTextLabel's fit_content-computed minimum size, keeping the label
## horizontally/vertically centered on its original anchor point.
func _resize_to_fit() -> void:
	# By the time this runs, setup() has already decided the label's final
	# width: either capped+wrapped (custom_minimum_size.x > 0) or left at
	# its natural content width (autowrap off, size untouched since the
	# reset). Either way, TextLabel.get_minimum_size() now reflects the
	# correct width and get_content_height() the correct wrapped/unwrapped
	# height — just clamp both to the authored minimum so a very short
	# string never shrinks the bubble to a sliver.
	var target_width = max(TextLabel.get_minimum_size().x, _base_label_size.x)
	var target_height = max(TextLabel.get_content_height(), _base_label_size.y)

	# Always recenter around the ORIGINAL authored center, not whatever
	# TextLabel.position/.size happen to read right now — those were reset
	# to 0/left to drift during the autowrap-measurement frame waits in
	# setup(), so trusting them here was compounding that drift into the
	# resize itself (visible as the bubble appearing to slide while it
	# scales in).
	var new_size = Vector2(target_width, target_height)

	TextLabel.size = new_size
	TextLabel.position = _base_label_center - new_size / 2.0

	# Tail stays horizontally centered under the label and sits `_tail_gap`
	# pixels below the label's new bottom edge, regardless of how much the
	# label grew in width or height.
	var label_bottom = TextLabel.position.y + TextLabel.size.y
	var label_center_x = TextLabel.position.x + TextLabel.size.x / 2.0

	Tail.position.y = label_bottom + _tail_gap
	Tail.position.x = label_center_x - Tail.size.x / 2.0

## Computes the bubble's position relative to the owner object, using the
## same relative-anchor + pixel-offset convention as Move_To_Object_v1_15
## (relativeAnchorA_x/y as a 0-100 percent of the owner's bounds, anchorA_x/y
## as a further raw pixel nudge). Since top_level=true means `position` is
## this node's own global position (not parent-relative), we set
## global_position directly here; setup() then derives the fixed local
## offset from the owner for _process()'s per-frame follow.
func _position_on_owner(
	owner_node: Node2D,
	anchor_percent: Vector2,
	pixel_offset: Vector2,
	_margins: Dictionary
) -> void:
	var owner_size := Vector2.ZERO
	var collision_shape := owner_node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null and collision_shape.shape != null:
		var shape := collision_shape.shape
		if shape is RectangleShape2D:
			owner_size = (shape as RectangleShape2D).size * collision_shape.scale
		elif shape is CircleShape2D:
			var diameter = (shape as CircleShape2D).radius * 2.0
			owner_size = Vector2(diameter, diameter) * collision_shape.scale
	else:
		var sprite := owner_node.get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null and sprite.texture != null:
			owner_size = sprite.texture.get_size() * sprite.scale

	# relativeAnchorA_y follows Hyperpad's bottom-up percentage convention
	# (matches Move_To_Object_v1_15's `100.0 - relativeAnchorA_y`).
	var relative = Vector2(
		anchor_percent.x,
		100.0 - anchor_percent.y
	) / 100.0

	var local_anchor = (relative - Vector2(0.5, 0.5)) * owner_size

	# Position anchors the tail tip (bottom of the bubble) at the computed
	# point, since the tail visually points at the object - offset the whole
	# bubble upward by its own height so the tail (not the label center)
	# lands on the anchor.
	var tail_tip_local = Tail.position + Tail.size / 2.0
	var offset_from_owner = local_anchor + Vector2(pixel_offset.x, -pixel_offset.y) - tail_tip_local

	global_position = owner_node.global_position + offset_from_owner

## Pops the bubble in by tweening scale 0 -> init_scale.
func _scale_in() -> void:
	var tween = create_tween()
	#tween.set_trans(Tween.TRANS_BACK)
	#tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", init_scale, SPAWN_SCALE_DURATION)
	await tween.finished

## Shrinks the bubble out by tweening scale -> 0, then frees it - matching
## Hyperpad's own Text Bubble teardown (scale out, not fade).
func _scale_out_and_free() -> void:
	var tween = create_tween()
	#tween.set_trans(Tween.TRANS_QUAD)
	#tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ZERO, FADE_DURATION)
	await tween.finished
	queue_free()