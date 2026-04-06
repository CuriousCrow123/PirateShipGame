extends Line2D
## Maintains a point queue tracking follow_target's movement, rendered as a
## width-tapered trail inside a SubViewport. The SubViewport's texture is then
## displayed by a sibling Sprite2D with a ripple shader.
##
## _offset compensates for SubViewport coordinates: the viewport origin is
## top-left (0,0) but we want the trail centered, so we shift by half the
## viewport size.

@export var max_length: int = 300
@export var sub_viewport: SubViewport
@export var follow_target: Node2D  ## Node whose position drives the trail
@export var distance_at_largest_width: float = 16.0 * 6.0
@export var smallest_tip_width: float = 0.15
@export var largest_tip_width: float = 0.8

var _queue: Array[Vector2] = []
var _offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	assert(sub_viewport != null, "Trails: sub_viewport export must be assigned")
	assert(follow_target != null, "Trails: follow_target export must be assigned")
	assert(
		width_curve != null and width_curve.point_count > 0,
		"Trails: width_curve must have at least one point"
	)
	_offset = Vector2(sub_viewport.size) / 2.0
	# Duplicate the Curve resource so mutations (set_point_value) don't corrupt
	# other instances sharing the same sub-resource. See plan: "Shared Curve
	# resource mutation bug".
	width_curve = width_curve.duplicate()


func _process(_delta: float) -> void:
	if _queue.is_empty() and get_point_count() == 0:
		# First frame or after reset — seed the queue
		_queue.append(follow_target.global_position + _offset)
		return

	var pos: Vector2 = follow_target.global_position + _offset
	_queue.append(pos)
	while _queue.size() > max_length and _queue.size() > 2:
		_queue.pop_front()

	var length: float = 0.0
	clear_points()
	for i: int in range(_queue.size() - 1):
		length += _queue[i].distance_to(_queue[i + 1])
		add_point(follow_target.to_local(_queue[i]))
	add_point(follow_target.to_local(_queue[-1]))

	var t: float = clampf(inverse_lerp(0.0, distance_at_largest_width, length), 0.0, 1.0)
	width_curve.set_point_value(0, lerpf(smallest_tip_width, largest_tip_width, t))


func reset_line() -> void:
	clear_points()
	_queue.clear()
