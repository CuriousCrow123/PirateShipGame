class_name Cannonball
extends Area2D
## Projectile fired from a cannon. Travels a randomized distance
## then impacts with an explosion effect. Hits the opposing team's ship.

signal water_impacted(pos: Vector2)
signal hit_registered  ## Emitted when a PLAYER-owned ball hits an EnemyShip.

# Layer/mask bit math (Godot layers are 1-indexed in UI, 0-indexed for `1 << n`).
const LAYER_PLAYER_BALL: int = 1 << 2  # layer 3 = player_projectiles
const LAYER_ENEMY_BALL: int = 1 << 4  # layer 5 = enemy_projectiles
# Phase 8 Step 39: both teams now hit hurtbox Area2Ds rather than the
# CharacterBody2D directly. Player balls mask the enemy_hurtbox layer
# (layer 7); enemy balls mask the player_hurtbox layer (layer 6).
const MASK_ENEMY_HURTBOX: int = 1 << 6  # layer 7 = enemy_hurtbox
const MASK_PLAYER_HURTBOX: int = 1 << 5  # layer 6 = player_hurtbox

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
	area_entered.connect(_on_area_entered)


func setup(pos: Vector2, dir: Vector2, from_enemy: bool = false) -> void:
	global_position = pos
	_direction = dir.normalized()
	rotation = _direction.angle()
	is_enemy_owned = from_enemy
	if from_enemy:
		collision_layer = LAYER_ENEMY_BALL
		collision_mask = MASK_PLAYER_HURTBOX
		modulate = ENEMY_TINT
	else:
		collision_layer = LAYER_PLAYER_BALL
		collision_mask = MASK_ENEMY_HURTBOX
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


func _on_area_entered(area: Area2D) -> void:
	if _impacted:
		return
	# Phase 8 Step 39: both teams hit hurtbox Area2Ds. Resolve the entity
	# root from the area's owner and forward to its public take_damage entry.
	var entity: Node = HurtboxComponent.resolve_entity(area)
	if is_enemy_owned:
		var ship: Ship = entity as Ship
		if ship == null:
			return
		_impacted = true
		ship.take_damage(_direction)
	else:
		var enemy: EnemyShip = entity as EnemyShip
		if enemy == null:
			return
		_impacted = true
		enemy.take_damage(_direction)
		hit_registered.emit()
	water_impacted.emit(global_position)
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
