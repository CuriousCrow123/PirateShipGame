extends Node
## Input mode state machine with auto-detection and persistence.
##
## Tracks which input method is active (keyboard, gamepad, touch-joystick,
## touch-tilt) and emits a signal when it changes so the touch overlay and
## settings panel can react.
##
## Persists the user's choice to user://settings.cfg [input] mode.

signal input_mode_changed(new_mode: int)

enum InputMode { KEYBOARD, GAMEPAD, TOUCH_JOYSTICK, TOUCH_TILT }

const SETTINGS_PATH: String = "user://settings.cfg"

var current_mode: int = InputMode.KEYBOARD


func _ready() -> void:
	_load_setting()
	if current_mode == InputMode.KEYBOARD:
		current_mode = _auto_detect()


func set_mode(mode: int) -> void:
	if mode == current_mode:
		return
	current_mode = mode
	_save_setting()
	input_mode_changed.emit(current_mode)


func is_touch_active() -> bool:
	return current_mode == InputMode.TOUCH_JOYSTICK or current_mode == InputMode.TOUCH_TILT


func _auto_detect() -> int:
	if DisplayServer.is_touchscreen_available():
		return InputMode.TOUCH_JOYSTICK
	if not Input.get_connected_joypads().is_empty():
		return InputMode.GAMEPAD
	return InputMode.KEYBOARD


func _load_setting() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SETTINGS_PATH)
	if err != OK:
		return
	var saved: int = config.get_value("input", "mode", -1)
	if saved >= InputMode.KEYBOARD and saved <= InputMode.TOUCH_TILT:
		current_mode = saved


func _save_setting() -> void:
	var config: ConfigFile = ConfigFile.new()
	if FileAccess.file_exists(SETTINGS_PATH):
		config.load(SETTINGS_PATH)
	config.set_value("input", "mode", current_mode)
	config.save(SETTINGS_PATH)
