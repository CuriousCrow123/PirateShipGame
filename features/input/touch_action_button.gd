class_name TouchActionButton
extends Control
## A single on-screen button that fires an InputMap action on touch.
## Uses Input.parse_input_event() with InputEventAction so edge-detected
## actions (fire, dash, mine) flow through _unhandled_input correctly.
##
## Renders via _draw() using the project's UI colour palette.

const BG_COLOR: Color = Color(0.11, 0.1, 0.08, 0.55)
const BG_PRESSED_COLOR: Color = Color(0.25, 0.22, 0.15, 0.7)
const BORDER_COLOR: Color = Color(0.75, 0.7, 0.55, 0.7)
const TEXT_COLOR: Color = Color(0.95, 0.85, 0.55, 0.95)
const BORDER_WIDTH: float = 2.0

@export var action: StringName = &""
@export var button_label: String = ""

var _touch_index: int = -1
var _pressed: bool = false

var _font: Font = null
var _font_size: int = 10


func _ready() -> void:
	assert(action != &"", "TouchActionButton: action must be set")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = preload("res://assets/fonts/kims_bit_hand_spaced.tres")
	queue_redraw()


func _input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch == null:
		return
	var local_pos: Vector2 = _to_local_pos(touch.position)
	if touch.pressed:
		if _touch_index != -1:
			return
		if not Rect2(Vector2.ZERO, size).has_point(local_pos):
			return
		_touch_index = touch.index
		_pressed = true
		_fire_action(true)
		queue_redraw()
	elif touch.index == _touch_index:
		_touch_index = -1
		_pressed = false
		_fire_action(false)
		queue_redraw()


func _fire_action(pressed: bool) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var bg: Color = BG_PRESSED_COLOR if _pressed else BG_COLOR
	draw_rect(rect, bg)
	draw_rect(rect, BORDER_COLOR, false, BORDER_WIDTH)
	if _font != null and button_label != "":
		var text_size: Vector2 = _font.get_string_size(
			button_label, HORIZONTAL_ALIGNMENT_CENTER, -1, _font_size
		)
		var text_pos: Vector2 = (size - text_size) * 0.5
		text_pos.y += _font.get_ascent(_font_size)
		draw_string(
			_font, text_pos, button_label, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, TEXT_COLOR
		)


## Full transform: screen → viewport → canvas → control local space.
func _to_local_pos(screen_pos: Vector2) -> Vector2:
	return get_screen_transform().affine_inverse() * screen_pos
