class_name Cannonball
extends Area2D
## Projectile fired from a cannon. Travels in a straight line and
## despawns after its lifetime expires.

@export var speed: float = 200.0
@export var lifetime: float = 2.0

var _direction: Vector2 = Vector2.ZERO
var _time_alive: float = 0.0


func setup(pos: Vector2, dir: Vector2) -> void:
	global_position = pos
	_direction = dir.normalized()
	rotation = _direction.angle()


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()
