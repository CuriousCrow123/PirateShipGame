class_name WaveToast
extends CanvasLayer
## Centered "WAVE N" toast that slides in, holds, then fades out. The Frame
## is centered and auto-sized by a full-rect CenterContainer, so we animate
## the slide by tweening the CanvasLayer's own `offset` property (which
## translates all children uniformly) instead of fighting the container's
## layout pass on the Frame's position.

const SLIDE_IN_DURATION: float = 0.35
const HOLD_DURATION: float = 1.1
const SLIDE_OUT_DURATION: float = 0.45
const SLIDE_OFFSET_Y: float = -40.0

var _active_tween: Tween = null

@onready var _frame: PanelContainer = $Centerer/Frame
@onready var _wave_label: Label = %WaveLabel


func _ready() -> void:
	assert(_frame != null, "WaveToast: Frame panel not found")
	assert(_wave_label != null, "WaveToast: WaveLabel not found")
	_frame.modulate.a = 0.0


func show_wave(wave: int) -> void:
	_wave_label.text = "WAVE %d" % wave
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	offset = Vector2(0.0, SLIDE_OFFSET_Y)
	_frame.modulate.a = 0.0
	_active_tween = create_tween()
	# Slide in (BACK ease for a snappy drop) + fade in, in parallel.
	(
		_active_tween
		. parallel()
		. tween_property(self, "offset", Vector2.ZERO, SLIDE_IN_DURATION)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_active_tween.parallel().tween_property(_frame, "modulate:a", 1.0, SLIDE_IN_DURATION)
	# Hold (chained, runs after the parallel block).
	_active_tween.chain().tween_interval(HOLD_DURATION)
	# Fade out + slight upward drift, in parallel.
	_active_tween.chain().tween_property(_frame, "modulate:a", 0.0, SLIDE_OUT_DURATION)
	_active_tween.parallel().tween_property(
		self, "offset", Vector2(0.0, SLIDE_OFFSET_Y * 0.5), SLIDE_OUT_DURATION
	)
