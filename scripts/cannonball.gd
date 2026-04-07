class_name Cannonball
extends Area2D
## Projectile fired from a cannon. Travels a randomized distance
## then impacts with an explosion effect. Detects enemy ship collisions.

signal water_impacted(pos: Vector2)

@export var speed: float = 200.0
@export var max_range: float = 150.0
@export var range_randomness: float = 0.3

var _direction: Vector2 = Vector2.ZERO
var _target_distance: float = 0.0
var _distance_traveled: float = 0.0
var _impacted: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func setup(pos: Vector2, dir: Vector2) -> void:
	global_position = pos
	_direction = dir.normalized()
	rotation = _direction.angle()
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
	if body is EnemyShip:
		_impacted = true
		body.take_damage(_direction)
		ExplosionSprite.create(get_parent(), global_position, "cannonball_impact", _direction)
		queue_free()


func _impact() -> void:
	if _impacted:
		return
	_impacted = true
	water_impacted.emit(global_position)
	ExplosionSprite.create(get_parent(), global_position, "cannonball_impact", _direction)
	queue_free()
