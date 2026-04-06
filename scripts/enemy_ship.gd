class_name EnemyShip
extends CharacterBody2D
## Dummy enemy ship that drifts randomly and can be damaged by cannonballs.
## Takes 4 hits to destroy, with progressive hull damage visuals.

signal destroyed(ship: EnemyShip)

const SHAKE_DURATION: float = 0.3
const SHAKE_MAX_INTENSITY: float = 3.0

@export var drift_speed: float = 30.0
@export var turn_speed: float = 0.3
@export var max_health: int = 4

var _health: int = 0
var _is_destroyed: bool = false
var _is_shaking: bool = false
var _shake_timer: float = 0.0
var _original_hull_pos: Vector2 = Vector2.ZERO
var _flash_tween: Tween = null

@onready var _hull_sprite: Sprite2D = $HullSprite
@onready var _sail_sprite: Sprite2D = $SailSprite
@onready var _collision_shape: CollisionShape2D = $CollisionShape


func _ready() -> void:
	assert(_hull_sprite != null, "EnemyShip: HullSprite not found")
	assert(_sail_sprite != null, "EnemyShip: SailSprite not found")
	assert(_collision_shape != null, "EnemyShip: CollisionShape not found")
	_health = max_health
	_original_hull_pos = _hull_sprite.position
	_randomize_appearance()


func _physics_process(delta: float) -> void:
	rotation += randf_range(-turn_speed, turn_speed) * delta
	velocity = -transform.y * drift_speed
	move_and_slide()
	_process_shake(delta)


func take_damage(_from_direction: Vector2) -> void:
	if _is_destroyed:
		return
	_health -= 1
	if _health <= 0:
		_is_destroyed = true
		_destroy()
		return
	# Update hull damage variant (0=healthy, 3=heavily damaged)
	var damage_variant: int = max_health - _health
	_hull_sprite.region_rect = ShipConfig.get_hull_region(mini(damage_variant, 3))
	_start_shake()
	_flash_white()


func _destroy() -> void:
	# Kill any active flash tween to prevent conflict with fade-out
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	# Disable collision immediately (deferred for physics safety)
	_collision_shape.set_deferred("disabled", true)
	# Large destruction explosion — parented to get_parent() (Main) so it
	# survives this node's queue_free
	ExplosionEffect.create(get_parent(), global_position, Vector2.UP, 360, 1.5, 80.0, velocity)
	destroyed.emit(self)
	# Fade out then remove
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


func _start_shake() -> void:
	_is_shaking = true
	_shake_timer = SHAKE_DURATION


func _process_shake(delta: float) -> void:
	if not _is_shaking:
		return
	_shake_timer -= delta
	if _shake_timer <= 0.0:
		_is_shaking = false
		_hull_sprite.position = _original_hull_pos
		_sail_sprite.position = Vector2.ZERO
		return
	var intensity: float = _shake_timer / SHAKE_DURATION * SHAKE_MAX_INTENSITY
	# Snap to whole pixels for pixel-art consistency
	var offset: Vector2 = Vector2(
		roundf(randf_range(-intensity, intensity)), roundf(randf_range(-intensity, intensity))
	)
	_hull_sprite.position = _original_hull_pos + offset
	_sail_sprite.position = offset


func _flash_white() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color(3.0, 3.0, 3.0, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.15)


func _randomize_appearance() -> void:
	var sail_variant: int = randi_range(0, 23)
	_sail_sprite.region_rect = ShipConfig.get_sail_region(sail_variant)
	_hull_sprite.region_rect = ShipConfig.get_hull_region(0)
