class_name HPDisplay
extends CanvasLayer
## Top-left HP pip display. Each pip is a ColorRect that drains with a
## shrink+fade tween on damage and pops back in on respawn. Active pips
## shift from green → yellow → orange → red as HP drops. The last pip
## pulses red at 1 HP as a danger cue.

const COLOR_FULL: Color = Color(0.45, 0.85, 0.4, 1.0)  # green
const COLOR_MID: Color = Color(0.95, 0.85, 0.3, 1.0)  # yellow
const COLOR_LOW: Color = Color(0.95, 0.55, 0.2, 1.0)  # orange
const COLOR_CRITICAL: Color = Color(0.95, 0.25, 0.2, 1.0)  # red
const LOST_COLOR: Color = Color(0.35, 0.33, 0.3, 0.6)

const DRAIN_DURATION: float = 0.2
const POP_STAGGER: float = 0.06
const RECOLOR_DURATION: float = 0.15
const CRITICAL_PULSE_INTERVAL: float = 0.35
const CRITICAL_PULSE_SCALE: Vector2 = Vector2(1.05, 1.05)
const CRITICAL_FLASH_BRIGHT: Color = Color(1.6, 1.6, 1.6, 1.0)
const CRITICAL_SHAKE_AMPLITUDE: float = 1.0  # pixels (pixel-snapped)
const CRITICAL_SHAKE_PROBABILITY: float = 0.35  # chance-per-frame of a jitter step

var _pips: Array[ColorRect] = []
var _ship: Ship = null
var _critical_tween: Tween = null
var _critical_active: bool = false
var _frame_base_pos: Vector2 = Vector2.ZERO

@onready var _frame: PanelContainer = $Frame
@onready var _pip_container: HBoxContainer = %Pips


func _ready() -> void:
	assert(_frame != null, "HPDisplay: Frame panel not found")
	assert(_pip_container != null, "HPDisplay: Pips container not found")
	_frame_base_pos = _frame.position
	for child: Node in _pip_container.get_children():
		var pip: ColorRect = child as ColorRect
		assert(pip != null, "HPDisplay: expected all pip children to be ColorRect")
		pip.color = COLOR_FULL
		pip.pivot_offset = pip.size / 2.0
		_pips.append(pip)


func _process(_delta: float) -> void:
	if not _critical_active:
		return
	# Sparse pixel-snapped jitter at 1 HP — most frames sit on the base
	# position, occasionally nudging by a single pixel so it feels nervy
	# without rattling the whole screen.
	if randf() > CRITICAL_SHAKE_PROBABILITY:
		_frame.position = _frame_base_pos
		return
	var jitter: Vector2 = Vector2(
		roundf(randf_range(-CRITICAL_SHAKE_AMPLITUDE, CRITICAL_SHAKE_AMPLITUDE)),
		roundf(randf_range(-CRITICAL_SHAKE_AMPLITUDE, CRITICAL_SHAKE_AMPLITUDE))
	)
	_frame.position = _frame_base_pos + jitter


func setup(ship: Ship) -> void:
	_ship = ship
	_ship.health_changed.connect(_on_health_changed)
	_ship.respawned.connect(_on_respawned)


func _on_health_changed(current: int, maximum: int) -> void:
	var target_color: Color = _get_fill_color_for(current, maximum)
	for i: int in range(_pips.size()):
		var pip: ColorRect = _pips[i]
		var should_fill: bool = i < current
		var is_filled: bool = pip.color.a >= 0.99
		if should_fill:
			if is_filled:
				_tween_pip_recolor(pip, target_color)
			else:
				_tween_pip_restore(pip, 0.0, target_color)
		elif is_filled:
			# Stop critical effects on a pip that is about to drain.
			_stop_critical_pulse()
			_tween_pip_drain(pip)

	# Last-standing pip pulses red as a danger cue at exactly 1 HP.
	if current == 1 and maximum > 1:
		_start_critical_pulse(_pips[0])
	else:
		_stop_critical_pulse()


func _on_respawned() -> void:
	_stop_critical_pulse()
	for i: int in range(_pips.size()):
		_tween_pip_restore(_pips[i], i * POP_STAGGER, COLOR_FULL)


func _get_fill_color_for(current: int, maximum: int) -> Color:
	if maximum <= 1:
		return COLOR_FULL if current >= 1 else LOST_COLOR
	# t in [0, 1] where 1.0 = full HP, 0.0 = last hit.
	var t: float = clampf(float(current - 1) / float(maximum - 1), 0.0, 1.0)
	if t >= 0.5:
		# Upper half: yellow → green.
		return COLOR_MID.lerp(COLOR_FULL, (t - 0.5) * 2.0)
	# Lower half: red → orange → yellow.
	if t >= 0.25:
		return COLOR_LOW.lerp(COLOR_MID, (t - 0.25) * 4.0)
	return COLOR_CRITICAL.lerp(COLOR_LOW, t * 4.0)


func _tween_pip_drain(pip: ColorRect) -> void:
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(pip, "color", LOST_COLOR, DRAIN_DURATION)
	tw.tween_property(pip, "scale", Vector2(0.6, 0.6), DRAIN_DURATION)


func _tween_pip_restore(pip: ColorRect, delay: float, target_color: Color) -> void:
	var tw: Tween = create_tween().set_parallel(true)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(pip, "color", target_color, DRAIN_DURATION)
	tw.tween_property(pip, "scale", Vector2.ONE, DRAIN_DURATION)
	tw.tween_property(pip, "modulate", Color.WHITE, DRAIN_DURATION)


func _tween_pip_recolor(pip: ColorRect, target_color: Color) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(pip, "color", target_color, RECOLOR_DURATION)


func _start_critical_pulse(pip: ColorRect) -> void:
	_stop_critical_pulse()
	_critical_active = true
	pip.color = COLOR_CRITICAL
	_critical_tween = create_tween().set_loops()
	_critical_tween.set_parallel(true)
	# Scale pulse (loops between 1.0 and the critical scale).
	(
		_critical_tween
		. tween_property(pip, "scale", CRITICAL_PULSE_SCALE, CRITICAL_PULSE_INTERVAL)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_critical_tween
		. tween_property(pip, "scale", Vector2.ONE, CRITICAL_PULSE_INTERVAL)
		. set_delay(CRITICAL_PULSE_INTERVAL)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	# Brightness flash on modulate so it doesn't fight the base color.
	(
		_critical_tween
		. tween_property(pip, "modulate", CRITICAL_FLASH_BRIGHT, CRITICAL_PULSE_INTERVAL)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_critical_tween
		. tween_property(pip, "modulate", Color.WHITE, CRITICAL_PULSE_INTERVAL)
		. set_delay(CRITICAL_PULSE_INTERVAL)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)


func _stop_critical_pulse() -> void:
	_critical_active = false
	if _critical_tween and _critical_tween.is_valid():
		_critical_tween.kill()
	_critical_tween = null
	# Restore the frame position after the shake.
	if _frame != null:
		_frame.position = _frame_base_pos
	# Hard-restore scale + modulate on all pips so no pip is left mid-pulse.
	for pip: ColorRect in _pips:
		pip.modulate = Color.WHITE
		# Don't touch drained pips' scale — they're at 0.6 intentionally.
		if pip.color.a >= 0.99:
			pip.scale = Vector2.ONE
