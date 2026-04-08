class_name MineCooldownDisplay
extends CanvasLayer
## Square HUD next to the lives row: procedurally-drawn mine icon on top,
## red→green reload bar underneath. Polls the ship's mine cooldown each
## frame — Ship is the source of truth; this HUD is pure presentation.

const BAR_COLOR_COOLING: Color = Color(0.62, 0.32, 0.28, 0.9)  # muted rust
const BAR_COLOR_READY: Color = Color(0.52, 0.68, 0.42, 0.9)  # faded sage
const BAR_BG_COLOR: Color = Color(0.1, 0.08, 0.05, 0.7)

var _ship: Ship = null

@onready var _icon: Control = %MineIcon
@onready var _bar_fg: ColorRect = %BarFill


func _ready() -> void:
	assert(_icon != null, "MineCooldownDisplay: MineIcon not found")
	assert(_bar_fg != null, "MineCooldownDisplay: BarFill not found")
	_icon.draw.connect(_draw_mine_icon)


func setup(ship: Ship) -> void:
	_ship = ship


func _process(_delta: float) -> void:
	if _ship == null:
		return
	var progress: float = _ship.get_mine_cooldown_progress()
	# Anchor-driven width: right anchor from 0 → 1.0 as the bar fills.
	_bar_fg.anchor_right = progress
	_bar_fg.color = BAR_COLOR_COOLING.lerp(BAR_COLOR_READY, progress)


func _draw_mine_icon() -> void:
	# Classic naval mine: dark sphere with radial spikes and a tiny highlight.
	var rect_size: Vector2 = _icon.size
	var center: Vector2 = rect_size / 2.0
	var radius: float = minf(rect_size.x, rect_size.y) * 0.32
	var spike_len: float = radius * 0.55
	var hull_color: Color = Color(0.32, 0.3, 0.26)
	var spike_color: Color = Color(0.42, 0.4, 0.35)
	var highlight_color: Color = Color(0.78, 0.76, 0.68)
	# Spikes first so the hull draws over their inner ends.
	for i: int in range(8):
		var angle: float = TAU * float(i) / 8.0
		var dir: Vector2 = Vector2.from_angle(angle)
		_icon.draw_line(
			center + dir * radius * 0.9, center + dir * (radius + spike_len), spike_color, 2.0
		)
	_icon.draw_circle(center, radius, hull_color)
	_icon.draw_circle(center - Vector2(1.0, 1.0), radius * 0.25, highlight_color)
