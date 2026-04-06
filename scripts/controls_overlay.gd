class_name ControlsOverlay
extends CanvasLayer

var _dismissed: bool = false
var _pulse_tween: Tween

@onready var _dismiss_prompt: Label = %DismissPrompt


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	assert(_dismiss_prompt != null, "ControlsOverlay: DismissPrompt label not found")
	get_tree().paused = true
	_setup_pulse_tween()


func _unhandled_input(event: InputEvent) -> void:
	if _dismissed:
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	if not key_event.is_pressed() or key_event.is_echo():
		return
	_dismissed = true
	get_viewport().set_input_as_handled()
	_dismiss.call_deferred()


func _setup_pulse_tween() -> void:
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	(
		_pulse_tween
		. tween_property(_dismiss_prompt, "modulate:a", 0.3, 0.8)
		. set_ease(Tween.EASE_IN_OUT)
		. set_trans(Tween.TRANS_SINE)
	)
	(
		_pulse_tween
		. tween_property(_dismiss_prompt, "modulate:a", 1.0, 0.8)
		. set_ease(Tween.EASE_IN_OUT)
		. set_trans(Tween.TRANS_SINE)
	)


func _dismiss() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
	get_tree().paused = false
	queue_free()
