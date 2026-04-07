class_name HPDisplay
extends CanvasLayer
## Top-left HP pip display. Each pip is a ColorRect that drains with a
## shrink+fade tween on damage and pops back in on respawn.

const FILL_COLOR: Color = Color(0.95, 0.93, 0.85, 1.0)
const LOST_COLOR: Color = Color(0.35, 0.33, 0.3, 0.6)
const DRAIN_DURATION: float = 0.2
const POP_STAGGER: float = 0.06

var _pips: Array[ColorRect] = []
var _ship: Ship = null

@onready var _pip_container: HBoxContainer = %Pips


func _ready() -> void:
	assert(_pip_container != null, "HPDisplay: Pips container not found")
	for child: Node in _pip_container.get_children():
		var pip: ColorRect = child as ColorRect
		assert(pip != null, "HPDisplay: expected all pip children to be ColorRect")
		pip.color = FILL_COLOR
		pip.pivot_offset = pip.size / 2.0
		_pips.append(pip)


func setup(ship: Ship) -> void:
	_ship = ship
	_ship.health_changed.connect(_on_health_changed)
	_ship.respawned.connect(_on_respawned)


func _on_health_changed(current: int, _maximum: int) -> void:
	for i: int in range(_pips.size()):
		var pip: ColorRect = _pips[i]
		var should_fill: bool = i < current
		var is_filled: bool = pip.color.a >= 0.99
		if should_fill and not is_filled:
			_tween_pip_restore(pip, 0.0)
		elif not should_fill and is_filled:
			_tween_pip_drain(pip)


func _on_respawned() -> void:
	for i: int in range(_pips.size()):
		_tween_pip_restore(_pips[i], i * POP_STAGGER)


func _tween_pip_drain(pip: ColorRect) -> void:
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(pip, "color", LOST_COLOR, DRAIN_DURATION)
	tw.tween_property(pip, "scale", Vector2(0.6, 0.6), DRAIN_DURATION)


func _tween_pip_restore(pip: ColorRect, delay: float) -> void:
	var tw: Tween = create_tween().set_parallel(true)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(pip, "color", FILL_COLOR, DRAIN_DURATION)
	tw.tween_property(pip, "scale", Vector2.ONE, DRAIN_DURATION)
