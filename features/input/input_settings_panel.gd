class_name InputSettingsPanel
extends CanvasLayer
## Controller-agnostic input mode selection UI. Navigable via keyboard
## (arrow keys + Enter), gamepad (D-pad + A), or touch (tap directly).
##
## Pauses the game while open. Toggled via the "toggle_input_settings"
## action (Tab / Start button).

const SLIDE_DURATION: float = 0.35
const SLIDE_OFFSET_Y: float = -30.0
const BG_TARGET_ALPHA: float = 0.6

var _is_open: bool = false
var _active_tween: Tween = null
var _mode_buttons: Array[Button] = []

@onready var _background: ColorRect = $Background
@onready var _panel: PanelContainer = $Centerer/Panel
@onready var _btn_keyboard: Button = $Centerer/Panel/Content/BtnKeyboard
@onready var _btn_gamepad: Button = $Centerer/Panel/Content/BtnGamepad
@onready var _btn_touch_joy: Button = $Centerer/Panel/Content/BtnTouchJoy
@onready var _btn_touch_tilt: Button = $Centerer/Panel/Content/BtnTouchTilt
@onready var _btn_rumble: CheckButton = $Centerer/Panel/Content/BtnRumble
@onready var _btn_close: Button = $Centerer/Panel/Content/BtnClose


func _ready() -> void:
	assert(_background != null, "InputSettingsPanel: Background not found")
	assert(_panel != null, "InputSettingsPanel: Panel not found")
	assert(_btn_keyboard != null, "InputSettingsPanel: BtnKeyboard not found")
	assert(_btn_gamepad != null, "InputSettingsPanel: BtnGamepad not found")
	assert(_btn_touch_joy != null, "InputSettingsPanel: BtnTouchJoy not found")
	assert(_btn_touch_tilt != null, "InputSettingsPanel: BtnTouchTilt not found")
	assert(_btn_rumble != null, "InputSettingsPanel: BtnRumble not found")
	assert(_btn_close != null, "InputSettingsPanel: BtnClose not found")

	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_mode_buttons = [_btn_keyboard, _btn_gamepad, _btn_touch_joy, _btn_touch_tilt]

	_panel.modulate.a = 0.0
	_panel.visible = false
	_background.color.a = 0.0
	_background.visible = false

	_btn_keyboard.pressed.connect(_on_mode_selected.bind(TouchInputManager.InputMode.KEYBOARD))
	_btn_gamepad.pressed.connect(_on_mode_selected.bind(TouchInputManager.InputMode.GAMEPAD))
	_btn_touch_joy.pressed.connect(
		_on_mode_selected.bind(TouchInputManager.InputMode.TOUCH_JOYSTICK)
	)
	_btn_touch_tilt.pressed.connect(_on_mode_selected.bind(TouchInputManager.InputMode.TOUCH_TILT))
	_btn_rumble.toggled.connect(_on_rumble_toggled)
	_btn_close.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_input_settings"):
		get_viewport().set_input_as_handled()
		if _is_open:
			close()
		else:
			open()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	_sync_button_states()
	_panel.visible = true
	_background.visible = true
	offset = Vector2(0.0, SLIDE_OFFSET_Y)
	_panel.modulate.a = 0.0
	_background.color.a = 0.0

	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_active_tween.parallel().tween_property(_background, "color:a", BG_TARGET_ALPHA, SLIDE_DURATION)
	(
		_active_tween
		. parallel()
		. tween_property(self, "offset", Vector2.ZERO, SLIDE_DURATION)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_active_tween.parallel().tween_property(_panel, "modulate:a", 1.0, SLIDE_DURATION)
	_active_tween.finished.connect(_on_open_complete, CONNECT_ONE_SHOT)
	get_tree().paused = true


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_panel.visible = false
	_background.visible = false
	get_tree().paused = false


func _on_open_complete() -> void:
	_get_active_mode_button().grab_focus()


func _sync_button_states() -> void:
	var mode: int = TouchInputManager.current_mode
	for btn: Button in _mode_buttons:
		btn.button_pressed = false
	_mode_buttons[mode].button_pressed = true

	var rumble_mgr: Node = get_tree().current_scene.find_child("RumbleManager")
	if rumble_mgr != null:
		_btn_rumble.set_pressed_no_signal(rumble_mgr.enabled)


func _get_active_mode_button() -> Button:
	return _mode_buttons[TouchInputManager.current_mode]


func _on_mode_selected(mode: int) -> void:
	TouchInputManager.set_mode(mode)
	_sync_button_states()


func _on_rumble_toggled(pressed: bool) -> void:
	var rumble_mgr: Node = get_tree().current_scene.find_child("RumbleManager")
	if rumble_mgr == null:
		return
	rumble_mgr.enabled = pressed
	rumble_mgr._save_setting()
