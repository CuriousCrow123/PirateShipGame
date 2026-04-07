class_name Cannonball
extends Area2D
## Projectile fired from a cannon. Travels a randomized distance
## then impacts with an explosion effect. Hits the opposing team's ship.

signal water_impacted(pos: Vector2)

# Layer/mask bit math (Godot layers are 1-indexed in UI, 0-indexed for `1 << n`).
const LAYER_PLAYER_BALL: int = 1 << 2  # layer 3 = player_projectiles
const LAYER_ENEMY_BALL: int = 1 << 4  # layer 5 = enemy_projectiles
const MASK_ENEMIES: int = 1 << 1  # layer 2 = enemies (player balls hit enemies)
const MASK_PLAYER: int = 1 << 0  # layer 1 = player (enemy balls hit player)

const ENEMY_TINT: Color = Color(1.4, 0.7, 0.6)  # warm red so enemy shots are readable

@export var speed: float = 200.0
@export var max_range: float = 150.0
@export var range_randomness: float = 0.3

var is_enemy_owned: bool = false
var _direction: Vector2 = Vector2.ZERO
var _target_distance: float = 0.0
var _distance_traveled: float = 0.0
var _impacted: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func setup(pos: Vector2, dir: Vector2, from_enemy: bool = false) -> void:
	global_position = pos
	_direction = dir.normalized()
	rotation = _direction.angle()
	is_enemy_owned = from_enemy
	if from_enemy:
		collision_layer = LAYER_ENEMY_BALL
		collision_mask = MASK_PLAYER
		modulate = ENEMY_TINT
	else:
		collision_layer = LAYER_PLAYER_BALL
		collision_mask = MASK_ENEMIES
	var min_dist: float = max_range * (1.0 - range_randomness)
	_target_distance = randf_range(min_dist, max_range)


func _physics_process(delta: float) -> void:
	if _impacted:
		return
	var step: float = speed * delta
	global_position += _direction * step
	_distance_traveled += step
	if _distance_traveled >= _target_distance:
		_impact()


func _on_body_entered(body: Node2D) -> void:
	if _impacted:
		return
	if not is_enemy_owned and body is EnemyShip:
		_impacted = true
		(body as EnemyShip).take_damage(_direction)
		ExplosionSprite.create(get_parent(), global_position, "cannonball_impact", _direction)
		queue_free()
	elif is_enemy_owned and body is Ship:
		# Player HP is intentionally out of scope — visual hit only.
		_impacted = true
		ExplosionSprite.create(get_parent(), global_position, "cannonball_impact", _direction)
		queue_free()


func _impact() -> void:
	if _impacted:
		return
	_impacted = true
	# Both teams emit water_impacted so Main can spawn a displacement splash for parity.
	water_impacted.emit(global_position)
	ExplosionSprite.create(get_parent(), global_position, "cannonball_impact", _direction)
	queue_free()
