extends CharacterBody2D
## Player-controlled ship with floaty, momentum-based movement.
## Thrust accumulates velocity; viscous drag decays it exponentially.
## Brake (S key) decelerates to zero via move_toward.
## Broadside cannons fire perpendicular to the ship (Q = port, E = starboard).
## Space dashes the ship forward with a tunable feel mode (see DashConfig).

signal cannon_fired(pos: Vector2, dir: Vector2)
signal mine_dropped(pos: Vector2)

@export var config: ShipConfig
@export var dash_config: DashConfig
@export var thrust: float = 80.0
@export var turn_speed: float = 2.5
@export var linear_drag: float = 0.97
@export var brake_decel: float = 120.0
@export var broadside_cooldown: float = 0.5
@export var mine_cooldown: float = 2.5

var _port_ready: bool = true
var _starboard_ready: bool = true
var _mine_ready: bool = true
var _dash_ready: bool = true
var _dash_active: bool = false
var _dash_remaining: float = 0.0

@onready var _hull_sprite: Sprite2D = $HullSprite
@onready var _sail_sprite: Sprite2D = $SailSprite
@onready var _cannon_slots: Node2D = $CannonSlots


func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	assert(_hull_sprite != null, "Ship: HullSprite node is missing")
	assert(_sail_sprite != null, "Ship: SailSprite node is missing")
	assert(_cannon_slots != null, "Ship: CannonSlots node is missing")
	assert(config != null, "Ship: config Resource is missing")
	assert(dash_config != null, "Ship: dash_config Resource is missing")
	_apply_config()


func _physics_process(delta: float) -> void:
	var is_braking: bool = Input.is_action_pressed("move_back")

	if _dash_active:
		_dash_remaining -= delta
		if _dash_remaining <= 0.0:
			_end_dash()
			_apply_normal_movement(delta, is_braking)
			return

		var turn_input: float = Input.get_axis("turn_left", "turn_right")

		match dash_config.feel_mode:
			DashConfig.FeelMode.LOCKED_HEADING:
				velocity *= linear_drag
				# thrust + steering ignored during locked-heading burst
			DashConfig.FeelMode.STEERABLE:
				if not is_braking and Input.is_action_pressed("move_forward"):
					velocity += transform.y * thrust * delta
				velocity *= linear_drag
				rotation += turn_input * turn_speed * delta
			DashConfig.FeelMode.VELOCITY_ALIGNED:
				velocity *= linear_drag
				rotation += turn_input * turn_speed * delta
			DashConfig.FeelMode.OVERSPEED_CAP:
				if not is_braking and Input.is_action_pressed("move_forward"):
					velocity += transform.y * thrust * delta
				velocity *= dash_config.overspeed_drag
				rotation += turn_input * turn_speed * delta

		move_and_slide()
		_process_collision_pushback(dash_config.collision_pushback_scale)
		return

	_apply_normal_movement(delta, is_braking)


func _apply_normal_movement(delta: float, is_braking: bool) -> void:
	if not is_braking and Input.is_action_pressed("move_forward"):
		velocity += transform.y * thrust * delta

	if is_braking:
		velocity = velocity.move_toward(Vector2.ZERO, brake_decel * delta)
	else:
		velocity *= linear_drag

	var turn_input: float = Input.get_axis("turn_left", "turn_right")
	rotation += turn_input * turn_speed * delta

	move_and_slide()
	_process_collision_pushback(1.0)


func _process_collision_pushback(pushback_scale: float) -> void:
	if pushback_scale <= 0.0:
		return
	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider is EnemyShip:
			var push: Vector2 = collision.get_normal() * 50.0 * pushback_scale
			velocity += push


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fire_port") and _port_ready:
		_fire_broadside("port")
	elif event.is_action_pressed("fire_starboard") and _starboard_ready:
		_fire_broadside("starboard")
	elif event.is_action_pressed("drop_mine") and _mine_ready:
		_drop_mine()
	elif event.is_action_pressed("dash") and _dash_ready and not _dash_active:
		_start_dash()


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
		_port_ready = false
		get_tree().create_timer(broadside_cooldown).timeout.connect(
			func() -> void:
				if is_instance_valid(self):
					_port_ready = true
		)
	else:
		_starboard_ready = false
		get_tree().create_timer(broadside_cooldown).timeout.connect(
			func() -> void:
				if is_instance_valid(self):
					_starboard_ready = true
		)


func _drop_mine() -> void:
	mine_dropped.emit(global_position)
	_mine_ready = false
	get_tree().create_timer(mine_cooldown).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				_mine_ready = true
	)


func _start_dash() -> void:
	_dash_ready = false
	_dash_active = true
	_dash_remaining = dash_config.duration

	# Apply initial impulse based on feel mode.
	match dash_config.feel_mode:
		DashConfig.FeelMode.VELOCITY_ALIGNED:
			if velocity.length() < 1.0:
				velocity += transform.y * dash_config.impulse_speed
			else:
				velocity += velocity.normalized() * dash_config.impulse_speed
		_:
			velocity += transform.y * dash_config.impulse_speed

	get_tree().create_timer(dash_config.cooldown).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				_dash_ready = true
	)


func _end_dash() -> void:
	_dash_active = false
	_dash_remaining = 0.0
