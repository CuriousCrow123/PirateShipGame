extends Line2D
## Maintains a point queue tracking follow_target's movement, rendered as a
## width-tapered trail inside a SubViewport. The SubViewport's texture is then
## displayed by a sibling Sprite2D with a ripple shader.
##
## Multi-ship: every Line2D inside the wake SubViewport renders into the same
## texture. We map world positions to viewport-local space using `pivot_target`
## (the player ship), which the SubViewport visually follows. Each ship's Line2D
## is positioned by `world_pos - pivot_world + viewport_center`.

@export var max_length: int = 90
@export var sub_viewport: SubViewport
@export var follow_target: Node2D  ## node whose movement drives this trail
@export var pivot_target: Node2D  ## the SubViewport's centering target (player ship)
@export var distance_at_largest_width: float = 16.0 * 6.0
@export var smallest_tip_width: float = 0.15
@export var largest_tip_width: float = 0.8

var _queue: Array[Vector2] = []
var _length_sq: float = 0.0
var _center: Vector2 = Vector2.ZERO


func _ready() -> void:
	assert(sub_viewport != null, "Trails: sub_viewport export must be assigned")
	assert(follow_target != null, "Trails: follow_target export must be assigned")
	assert(pivot_target != null, "Trails: pivot_target export must be assigned")
	assert(
		width_curve != null and width_curve.point_count > 0,
		"Trails: width_curve must have at least one point"
	)
	_center = Vector2(sub_viewport.size) / 2.0
	# Duplicate the Curve resource so per-instance set_point_value() doesn't
	# corrupt other Line2Ds sharing the same .tres. See:
	# docs/solutions/shared-resource-mutation.md
	width_curve = width_curve.duplicate()


func _process(_delta: float) -> void:
	if not is_instance_valid(follow_target) or not is_instance_valid(pivot_target):
		return

	var world_pos: Vector2 = follow_target.global_position
	var pivot_pos: Vector2 = pivot_target.global_position
	var viewport_pos: Vector2 = world_pos - pivot_pos + _center

	# Incremental update: append the new point, drop the oldest when over capacity.
	# Avoids the per-frame clear_points() + add_point()×N rebuild.
	if _queue.size() > 0:
		var prev: Vector2 = _queue[-1]
		_length_sq += world_pos.distance_squared_to(prev)
	_queue.append(world_pos)
	add_point(viewport_pos)

	while _queue.size() > max_length and _queue.size() > 2:
		var dropped: Vector2 = _queue[0]
		var next: Vector2 = _queue[1]
		_length_sq -= dropped.distance_squared_to(next)
		_length_sq = maxf(_length_sq, 0.0)
		_queue.pop_front()
		remove_point(0)

	# Reposition every existing point to follow the moving pivot — unavoidable
	# because the viewport is centered on the pivot in world space.
	for i: int in range(_queue.size()):
		set_point_position(i, _queue[i] - pivot_pos + _center)

	var threshold_sq: float = distance_at_largest_width * distance_at_largest_width
	var t: float = clampf(_length_sq / threshold_sq, 0.0, 1.0)
	width_curve.set_point_value(0, lerpf(smallest_tip_width, largest_tip_width, t))


func reset_line() -> void:
	clear_points()
	_queue.clear()
	_length_sq = 0.0
