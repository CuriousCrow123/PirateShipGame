class_name EnemyShip
extends CharacterBody2D
## Enemy ship that chases the player and circles at broadside range.
## Takes 4 hits to destroy, with progressive hull damage visuals.
## Fires broadside cannons at the player when aligned and in range.

signal destroyed(ship: EnemyShip, by_mine: bool)
signal cannon_fired(pos: Vector2, dir: Vector2)

const SHAKE_DURATION: float = 0.3
const SHAKE_MAX_INTENSITY: float = 3.0
const WAKE_RING_INTERVAL: float = 24.0  # px between wake-ring stamps
const BROADSIDE_ALIGNMENT_THRESHOLD: float = 0.85  # |dot(starboard, to_target)|
const RAM_IFRAME_DURATION: float = 0.4  # multi-hit guard for ship-ship collisions

@export var chase_speed: float = 50.0
@export var circle_speed: float = 40.0
@export var turn_speed: float = 2.0
@export var circle_radius: float = 120.0
@export var max_health: int = 4
@export var broadside_cooldown: float = 2.0
@export var broadside_range: float = 130.0  # must be <= Cannonball.max_range

var _health: int = 0
var _is_destroyed: bool = false
var _is_shaking: bool = false
var _shake_timer: float = 0.0
var _original_hull_pos: Vector2 = Vector2.ZERO
var _flash_tween: Tween = null
var _target: Node2D = null
var _port_cooldown: float = 0.0
var _starboard_cooldown: float = 0.0
# Per-enemy wake state — owned by the enemy, not Main, so cleanup is automatic.
var _wake_accum: float = 0.0
var _last_wake_pos: Vector2 = Vector2.ZERO
var _iframes_left: float = 0.0
var _port_cannons: Array[Cannon] = []
var _starboard_cannons: Array[Cannon] = []

@onready var _hull_sprite: Sprite2D = $HullSprite
@onready var _sail_sprite: Sprite2D = $SailSprite
@onready var _collision_shape: CollisionShape2D = $CollisionShape
@onready var _cannon_slots: Node2D = $CannonSlots


func _ready() -> void:
	assert(_hull_sprite != null, "EnemyShip: HullSprite not found")
	assert(_sail_sprite != null, "EnemyShip: SailSprite not found")
	assert(_collision_shape != null, "EnemyShip: CollisionShape not found")
	assert(_cannon_slots != null, "EnemyShip: CannonSlots not found")
	# broadside_range MUST stay <= Cannonball.max_range (default 150) so balls
	# can actually reach the player at max firing distance.
	_health = max_health
	_original_hull_pos = _hull_sprite.position
	_last_wake_pos = global_position
	_cache_cannon_refs()
	_randomize_appearance()
	add_to_group("enemy_ships")


func _physics_process(delta: float) -> void:
	# Despawning enemies still get one extra physics tick before queue_free
	# completes — guard so they cannot fire a final invisible salvo.
	if is_queued_for_deletion():
		return

	if _iframes_left > 0.0:
		_iframes_left -= delta
	if _port_cooldown > 0.0:
		_port_cooldown -= delta
	if _starboard_cooldown > 0.0:
		_starboard_cooldown -= delta

	if not _is_destroyed and _target and is_instance_valid(_target):
		_steer_toward_target(delta)
		_try_fire_at_target()
	move_and_slide()
	_process_shake(delta)


func is_destroyed() -> bool:
	return _is_destroyed


func setup(target: Node2D) -> void:
	_target = target


func consume_wake_distance(traveled: float) -> bool:
	## Returns true (and resets) when the enemy has moved >= WAKE_RING_INTERVAL
	## since the last wake ring. Main calls this each frame.
	_wake_accum += traveled
	if _wake_accum >= WAKE_RING_INTERVAL:
		_wake_accum = 0.0
		return true
	return false


func get_wake_ring_position() -> Vector2:
	return global_position - transform.y * 12.0


func take_damage(_from_direction: Vector2, amount: int = 1, by_mine: bool = false) -> void:
	if _is_destroyed or is_queued_for_deletion():
		return
	_health -= amount
	if _health <= 0:
		_is_destroyed = true
		_destroy(by_mine)
		return
	# Update hull damage variant (0=healthy, 3=heavily damaged)
	var damage_variant: int = max_health - _health
	_hull_sprite.region_rect = ShipConfig.get_hull_region(mini(damage_variant, 3))
	_start_shake()
	_flash_white()


## Ram-damage entry point. Same as take_damage but adds a short iframe so
## ship-ship collisions can't apply damage across multiple physics sub-steps.
## Cannonball hits still go through take_damage and bypass this iframe.
func take_ram_damage(from_direction: Vector2) -> void:
	if _iframes_left > 0.0:
		return
	_iframes_left = RAM_IFRAME_DURATION
	take_damage(from_direction)


func _cache_cannon_refs() -> void:
	for slot: Node in _cannon_slots.get_children():
		if slot.get_child_count() == 0:
			continue
		var cannon: Cannon = slot.get_child(0) as Cannon
		if cannon == null:
			continue
		if String(slot.name).begins_with("Port"):
			_port_cannons.append(cannon)
		elif String(slot.name).begins_with("Starboard"):
			_starboard_cannons.append(cannon)


func _try_fire_at_target() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	if dist > broadside_range or dist < 0.001:
		return
	var dir_to_target: Vector2 = to_target / dist
	# Ship right (starboard) is +transform.x; left (port) is -transform.x.
	# transform.x has length == scale.x (0.5), so normalize before the dot
	# or the threshold (0.85) is unreachable.
	var starboard: Vector2 = transform.x.normalized()
	var dot: float = starboard.dot(dir_to_target)
	if dot >= BROADSIDE_ALIGNMENT_THRESHOLD and _starboard_cooldown <= 0.0:
		_fire_broadside(true)
	elif dot <= -BROADSIDE_ALIGNMENT_THRESHOLD and _port_cooldown <= 0.0:
		_fire_broadside(false)


func _fire_broadside(is_starboard: bool) -> void:
	var cannons: Array[Cannon] = _starboard_cannons if is_starboard else _port_cannons
	for cannon: Cannon in cannons:
		var result: Dictionary = cannon.fire()
		cannon_fired.emit(result["position"], result["direction"])
	if is_starboard:
		_starboard_cooldown = broadside_cooldown
	else:
		_port_cooldown = broadside_cooldown


func _destroy(by_mine: bool = false) -> void:
	# Kill any active flash tween to prevent conflict with fade-out
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	# Disable collision immediately (deferred for physics safety)
	_collision_shape.set_deferred("disabled", true)
	# Large destruction explosion — parented to get_parent() (Main) so it
	# survives this node's queue_free
	ExplosionSprite.create(
		get_parent(), global_position, "enemy_destruction", Vector2.ZERO, velocity
	)
	destroyed.emit(self, by_mine)
	# Fade out then remove
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


func _steer_toward_target(delta: float) -> void:
	var to_target: Vector2 = _target.global_position - global_position
	var dist: float = to_target.length()
	var desired_dir: Vector2

	if dist > circle_radius:
		# Chase: steer directly toward the player
		desired_dir = to_target.normalized()
	else:
		# Circle: steer perpendicular (clockwise) for broadside orbiting
		desired_dir = Vector2(to_target.y, -to_target.x).normalized()

	# Smoothly rotate toward desired heading (-transform.y is our forward)
	var forward: Vector2 = -transform.y
	var desired_angle: float = desired_dir.angle()
	var current_angle: float = forward.angle()
	var angle_diff: float = wrapf(desired_angle - current_angle, -PI, PI)
	rotation += clampf(angle_diff, -turn_speed * delta, turn_speed * delta)

	# Speed: full chase speed when far, circle speed when orbiting
	var speed: float = chase_speed if dist > circle_radius else circle_speed
	velocity = -transform.y * speed


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
