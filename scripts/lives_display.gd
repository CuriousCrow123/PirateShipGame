class_name LivesDisplay
extends CanvasLayer
## Top-left ships-remaining display. Each life is a framed hull icon in a row
## that mirrors the HPDisplay visual language: active lives stay vivid, lost
## lives drain to LOST_COLOR and shrink. The count is built dynamically from
## the Ship's stats.max_lives so the scene file stays generic.

const SpritesheetTex: Texture2D = preload("res://textures/ships_spritesheet.png")

const ACTIVE_COLOR: Color = Color(0.95, 0.93, 0.85, 1.0)
const LOST_COLOR: Color = Color(0.35, 0.33, 0.3, 0.6)
const DRAIN_DURATION: float = 0.25
const ICON_SIZE: Vector2 = Vector2(10, 16)

var _icons: Array[TextureRect] = []
var _ship: Ship = null
var _last_lives: int = -1

@onready var _icon_row: HBoxContainer = %Icons


func _ready() -> void:
	assert(_icon_row != null, "LivesDisplay: Icons container not found")


func setup(ship: Ship) -> void:
	_ship = ship
	_ship.lives_changed.connect(_on_lives_changed)
	_build_icons(ship.stats.max_lives)


func _build_icons(count: int) -> void:
	for child: Node in _icon_row.get_children():
		child.queue_free()
	_icons.clear()
	for i: int in range(count):
		var icon: TextureRect = TextureRect.new()
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# AtlasTexture points at the healthy hull region inside the spritesheet.
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = SpritesheetTex
		atlas.region = ShipConfig.get_hull_region(0)
		icon.texture = atlas
		icon.modulate = ACTIVE_COLOR
		icon.pivot_offset = ICON_SIZE / 2.0
		_icon_row.add_child(icon)
		_icons.append(icon)


func _on_lives_changed(current: int, maximum: int) -> void:
	# Rebuild if the maximum changed between runs (scene reload shouldn't
	# trigger this, but guard anyway).
	if _icons.size() != maximum:
		_build_icons(maximum)
	# Drain any newly-lost icons since the last update. Icons with index >=
	# current represent lost ships.
	for i: int in range(_icons.size()):
		var icon: TextureRect = _icons[i]
		var is_alive: bool = i < current
		var was_alive: bool = (_last_lives < 0) or (i < _last_lives)
		if not is_alive and was_alive:
			_tween_drain(icon)
		elif is_alive and not was_alive:
			# Defensive restore path (not used in normal play since lives
			# don't come back within a single run).
			icon.modulate = ACTIVE_COLOR
			icon.scale = Vector2.ONE
	_last_lives = current


func _tween_drain(icon: TextureRect) -> void:
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(icon, "modulate", LOST_COLOR, DRAIN_DURATION)
	tw.tween_property(icon, "scale", Vector2(0.6, 0.6), DRAIN_DURATION)
