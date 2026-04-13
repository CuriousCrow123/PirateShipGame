class_name WaveToast
extends CanvasLayer
## Centered "WAVE N" toast that slides in, holds, then fades out. The Frame
## is centered and auto-sized by a full-rect CenterContainer, so we animate
## the slide by tweening the CanvasLayer's own `offset` property (which
## translates all children uniformly) instead of fighting the container's
## layout pass on the Frame's position.
##
## Phase 11 Step 48c: subscribes directly to the Events bus for both wave
## announcements and the invincibility cheat banner. Pre-Phase-11 main.gd
## had two `_on_*` forwarders for these (Phase 7 retro line 470–479);
## migrating to direct bus subscriptions deletes both.

const SLIDE_IN_DURATION: float = 0.35
const HOLD_DURATION: float = 1.1
const SLIDE_OUT_DURATION: float = 0.45
const SLIDE_OFFSET_Y: float = -40.0

var _active_tween: Tween = null

@onready var _frame: PanelContainer = $Centerer/Frame
@onready var _subtitle_label: Label = %Subtitle
@onready var _wave_label: Label = %WaveLabel


func _ready() -> void:
	assert(_frame != null, "WaveToast: Frame panel not found")
	assert(_subtitle_label != null, "WaveToast: Subtitle label not found")
	assert(_wave_label != null, "WaveToast: WaveLabel not found")
	_frame.modulate.a = 0.0
	Events.wave_announced.connect(_on_wave_announced)
	Events.cheat_toggled.connect(_on_cheat_toggled)


func _on_wave_announced(wave: int) -> void:
	show_wave(wave)


func _on_cheat_toggled(cheat_id: StringName, active: bool) -> void:
	if cheat_id == &"invincibility":
		var title: String = "INVINCIBLE ON" if active else "INVINCIBLE OFF"
		show_message("CHEAT", title)
	elif cheat_id == &"rumble":
		var title: String = "RUMBLE ON" if active else "RUMBLE OFF"
		show_message("CONTROLLER", title)


func show_wave(wave: int) -> void:
	show_message("INCOMING", "WAVE %d" % wave)


## Generic title+subtitle toast. Reused for wave announcements and the
## secret Invincible toggle — same slide/fade choreography.
func show_message(subtitle: String, title: String) -> void:
	_subtitle_label.text = subtitle
	_wave_label.text = title
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
