class_name MinimapDisplay
extends Control
## Circular radar HUD showing nearby entities relative to the player ship.
## World-fixed orientation: up on minimap = up on screen.
## Uses _draw() for lightweight rendering — no SubViewport needed.

const SCREEN_RADIUS: float = 40.0
const WORLD_RADIUS: float = 700.0
const DOT_RADIUS: float = 1.0
const PLAYER_DOT_RADIUS: float = 1.5
const PLAYER_ARROW_LENGTH: float = 6.0
const RANGE_SQ: float = SCREEN_RADIUS * SCREEN_RADIUS

const BG_COLOR := Color(0.11, 0.1, 0.08, 0.55)  # matches HP frame, slightly transparent
const BORDER_COLOR := Color(0.75, 0.7, 0.55, 0.7)  # matches HP frame border
const BORDER_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)
const BORDER_WIDTH := 1.0
const RING_COLOR := Color(0.75, 0.7, 0.55, 0.2)
const PLAYER_COLOR := Color.WHITE
const ENEMY_COLOR := Color(1.0, 0.4, 0.4, 1.0)
const MINE_COLOR := Color(1.0, 0.8, 0.27, 1.0)

var _player: CharacterBody2D = null
var _radar_scale: float = 0.0
var _center: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_scale = SCREEN_RADIUS / WORLD_RADIUS
	_center = Vector2(SCREEN_RADIUS + 2.0, SCREEN_RADIUS + 2.0)
	custom_minimum_size = Vector2(_center.x * 2.0, _center.y * 2.0)


func _process(_delta: float) -> void:
	if _player == null:
		return
	queue_redraw()


func _draw() -> void:
	if _player == null:
		return
	# 1. Shadow ring behind the border — mirrors the HP frame's drop shadow.
	draw_arc(
		_center + Vector2(1.0, 1.0),
		SCREEN_RADIUS,
		0.0,
		TAU,
		64,
		BORDER_SHADOW_COLOR,
		BORDER_WIDTH + 1.0,
		true
	)
	# 2. Background circle
	draw_circle(_center, SCREEN_RADIUS, BG_COLOR)
	# 3. Range ring at 50%
	draw_arc(_center, SCREEN_RADIUS * 0.5, 0.0, TAU, 32, RING_COLOR, 1.0, true)
	# 4. Entity dots (mines under enemies)
	_draw_group_entities(&"sea_mines", MINE_COLOR)
	_draw_group_entities(&"enemy_ships", ENEMY_COLOR)
	# 5. Player arrow — rotates to show ship heading
	draw_circle(_center, PLAYER_DOT_RADIUS, PLAYER_COLOR)
	var heading: Vector2 = Vector2.DOWN.rotated(_player.rotation) * PLAYER_ARROW_LENGTH
	draw_line(_center, _center + heading, PLAYER_COLOR, 1.0, false)
	# 6. Cream border (topmost) — matches the HP frame stroke.
	draw_arc(_center, SCREEN_RADIUS, 0.0, TAU, 64, BORDER_COLOR, BORDER_WIDTH, true)


func setup(player: CharacterBody2D) -> void:
	assert(player != null, "MinimapDisplay: player reference is null")
	_player = player


func _draw_group_entities(group_name: StringName, color: Color) -> void:
	for node: Node2D in get_tree().get_nodes_in_group(group_name):
		if node is EnemyShip and node.is_destroyed():
			continue
		_draw_entity_dot(node, color)


func _draw_entity_dot(entity: Node2D, color: Color) -> void:
	var offset: Vector2 = entity.global_position - _player.global_position
	# World-fixed: no rotation applied — minimap matches screen orientation
	var radar_pos: Vector2 = offset * _radar_scale
	# Skip if beyond radar range (length_squared avoids sqrt)
	if radar_pos.length_squared() > RANGE_SQ:
		return
	draw_circle(_center + radar_pos, DOT_RADIUS, color)
