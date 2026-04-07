class_name Ship
extends CharacterBody2D
## Player-controlled ship with floaty, momentum-based movement.
## Thrust accumulates velocity; viscous drag decays it exponentially.
## Brake (S key) decelerates to zero via move_toward.
## Broadside cannons fire perpendicular to the ship (Q = port, E = starboard).

signal cannon_fired(pos: Vector2, dir: Vector2)
signal mine_dropped(pos: Vector2)

@export var config: ShipConfig
@export var thrust: float = 80.0
@export var turn_speed: float = 2.5
@export var linear_drag: float = 0.97
@export var brake_decel: float = 120.0
@export var broadside_cooldown: float = 0.5
@export var mine_cooldown: float = 2.5

var _port_cooldown: float = 0.0
var _starboard_cooldown: float = 0.0
var _mine_cooldown_left: float = 0.0

@onready var _hull_sprite: Sprite2D = $HullSprite
@onready var _sail_sprite: Sprite2D = $SailSprite
@onready var _cannon_slots: Node2D = $CannonSlots


func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	assert(_hull_sprite != null, "Ship: HullSprite node is missing")
	assert(_sail_sprite != null, "Ship: SailSprite node is missing")
	assert(_cannon_slots != null, "Ship: CannonSlots node is missing")
	assert(config != null, "Ship: config Resource is missing")
	_apply_config()


func _physics_process(delta: float) -> void:
	if _port_cooldown > 0.0:
		_port_cooldown -= delta
	if _starboard_cooldown > 0.0:
		_starboard_cooldown -= delta
	if _mine_cooldown_left > 0.0:
		_mine_cooldown_left -= delta

	var is_braking: bool = Input.is_action_pressed("move_back")

	if not is_braking and Input.is_action_pressed("move_forward"):
		velocity += transform.y * thrust * delta

	if is_braking:
		velocity = velocity.move_toward(Vector2.ZERO, brake_decel * delta)
	else:
		velocity *= linear_drag

	var turn_input: float = Input.get_axis("turn_left", "turn_right")
	rotation += turn_input * turn_speed * delta

	move_and_slide()

	# Bounce off enemy ships on collision
	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider is EnemyShip:
			var push: Vector2 = collision.get_normal() * 50.0
			velocity += push


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fire_port") and _port_cooldown <= 0.0:
		_fire_broadside("port")
	elif event.is_action_pressed("fire_starboard") and _starboard_cooldown <= 0.0:
		_fire_broadside("starboard")
	elif event.is_action_pressed("drop_mine") and _mine_cooldown_left <= 0.0:
		_drop_mine()


## Applies a new ship configuration, updating sprites and cannon slots.
func set_config(new_config: ShipConfig) -> void:
	config = new_config
	_apply_config()


func _apply_config() -> void:
	_hull_sprite.region_rect = ShipConfig.get_hull_region(config.hull_variant)
	_sail_sprite.region_rect = ShipConfig.get_sail_region(config.sail_variant)

	var slot_names: Array[String] = [
		"PortCannon1", "PortCannon2", "StarboardCannon1", "StarboardCannon2"
	]
	for i: int in slot_names.size():
		var slot: Marker2D = _cannon_slots.get_node(slot_names[i])
		if slot.get_child_count() > 0:
			slot.get_child(0).visible = config.cannon_slots[i]


func _fire_broadside(side: String) -> void:
	var prefix: String = "Port" if side == "port" else "Starboard"
	for slot: Node in _cannon_slots.get_children():
		if not slot.name.begins_with(prefix):
			continue
		if slot.get_child_count() == 0:
			continue
		var cannon: Cannon = slot.get_child(0) as Cannon
		if cannon == null or not cannon.visible:
			continue
		var result: Dictionary = cannon.fire()
		cannon_fired.emit(result["position"], result["direction"])

	if side == "port":
		_port_cooldown = broadside_cooldown
	else:
		_starboard_cooldown = broadside_cooldown


func _drop_mine() -> void:
	mine_dropped.emit(global_position)
	_mine_cooldown_left = mine_cooldown
