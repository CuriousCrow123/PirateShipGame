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
var _next_ghost_in: float = 0.0
var _shake_trauma: float = 0.0
var _ghost_additive_material: CanvasItemMaterial

@onready var _hull_sprite: Sprite2D = $HullSprite
@onready var _sail_sprite: Sprite2D = $SailSprite
@onready var _cannon_slots: Node2D = $CannonSlots
@onready var _fire_effect: DashFireEffect = $SternMarker/DashFireEffect
@onready var _camera: Camera2D = $Camera2D
@onready var _ghost_sources: Array[Sprite2D] = [$HullSprite, $SailSprite]
@onready var _ghost_container: Node2D = get_parent() as Node2D


func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	assert(_hull_sprite != null, "Ship: HullSprite node is missing")
	assert(_sail_sprite != null, "Ship: SailSprite node is missing")
	assert(_cannon_slots != null, "Ship: CannonSlots node is missing")
	assert(_fire_effect != null, "Ship: SternMarker/DashFireEffect node is missing")
	assert(_camera != null, "Ship: Camera2D node is missing")
	assert(_ghost_container != null, "Ship: parent must be a Node2D world container")
	assert(config != null, "Ship: config Resource is missing")
	assert(dash_config != null, "Ship: dash_config Resource is missing")
	# Cached additive material reused across all ghost spawns (Godot does NOT
	# fork CanvasItemMaterial on assignment — all ghosts share the same RID
	# and batch together).
	_ghost_additive_material = CanvasItemMaterial.new()
	_ghost_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_apply_config()


func _exit_tree() -> void:
	# Defensive: if a time_dip lambda failed mid-burst (freed instance, etc.),
	# make sure we never leave the engine in scaled time when the ship leaves.
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0


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


func _process(delta: float) -> void:
	# Visuals run on render frames so the burst animates smoothly on
	# high-refresh displays. Motion stays in _physics_process.
	if _dash_active:
		_tick_dash_visuals(delta)
	_process_camera_shake(delta)


func _tick_dash_visuals(delta: float) -> void:
	var t: float = 1.0 - clampf(_dash_remaining / dash_config.duration, 0.0, 1.0)
	var dash_strength: float = 1.0
	if dash_config.intensity_curve != null:
		dash_strength = dash_config.intensity_curve.sample_baked(t)
	_fire_effect.set_dash_strength(dash_strength)
	# Ghost trail spawn ticker.
	if dash_config.ghost_count > 0:
		_next_ghost_in -= delta
		if _next_ghost_in <= 0.0:
			_spawn_ghost()
			_next_ghost_in = dash_config.ghost_spawn_interval


func _process_camera_shake(delta: float) -> void:
	# Trauma-squared model (Eiserloh, GDC 2016): offset = trauma^2 * mag.
	# Linear decay of trauma. Pixel-snapped via roundf for the 640x360
	# integer-scale viewport. Writes Camera2D.offset (NOT position) so the
	# existing position_smoothing_enabled doesn't swallow the shake.
	if _shake_trauma <= 0.0:
		if _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO
		return
	_shake_trauma = maxf(0.0, _shake_trauma - dash_config.shake_trauma_decay * delta)
	var amplitude: float = _shake_trauma * _shake_trauma * dash_config.shake_magnitude_px
	_camera.offset = Vector2(
		roundf(randf_range(-amplitude, amplitude)), roundf(randf_range(-amplitude, amplitude))
	)


func _spawn_ghost() -> void:
	if _ghost_container == null:
		return
	for src: Sprite2D in _ghost_sources:
		if src == null:
			continue
		var ghost: Sprite2D = Sprite2D.new()
		ghost.texture = src.texture
		ghost.region_enabled = src.region_enabled
		ghost.region_rect = src.region_rect
		ghost.centered = src.centered
		ghost.offset = src.offset
		ghost.global_transform = src.global_transform
		ghost.modulate = dash_config.ghost_start_tint
		ghost.z_index = src.z_index - 1
		if dash_config.ghost_additive:
			ghost.material = _ghost_additive_material
		_ghost_container.add_child(ghost)
		var tw: Tween = ghost.create_tween()
		tw.tween_property(
			ghost, "modulate", dash_config.ghost_end_tint, dash_config.ghost_fade_duration
		)
		tw.tween_callback(ghost.queue_free)


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

	# Push current fire-config uniforms onto the 3D effect and start emitting.
	# The effect renders into a 32x64 SubViewport for pixel-art crunch and
	# composites back into 2D via SubViewportContainer.
	_fire_effect.start(dash_config)

	# Reset ghost spawn timer so the first ghost spawns next render tick.
	_next_ghost_in = 0.0

	# Bump shake trauma. max() so a re-trigger can never reduce in-flight shake.
	_shake_trauma = maxf(_shake_trauma, dash_config.shake_trauma_initial)

	# Optional zoom punch.
	if dash_config.zoom_punch_duration > 0.0:
		var base_zoom: Vector2 = Vector2(1.2, 1.2)
		var punch_zoom: Vector2 = Vector2(
			dash_config.zoom_punch_target, dash_config.zoom_punch_target
		)
		var zoom_tween: Tween = create_tween()
		zoom_tween.tween_property(
			_camera, "zoom", punch_zoom, dash_config.zoom_punch_duration * 0.4
		)
		zoom_tween.tween_property(_camera, "zoom", base_zoom, dash_config.zoom_punch_duration * 0.6)

	# Optional Celeste-style freeze frames at burst start.
	if dash_config.freeze_frames > 0:
		var freeze_seconds: float = float(dash_config.freeze_frames) / 60.0
		Engine.time_scale = 0.0
		# process_always=true, ignore_time_scale=true so the timer fires in
		# real time even with Engine.time_scale = 0.
		get_tree().create_timer(freeze_seconds, true, false, true).timeout.connect(
			func() -> void:
				if is_instance_valid(self):
					Engine.time_scale = 1.0
		)
	# Optional time-scale dip (mutually exclusive in practice with freeze; if
	# both are set, freeze wins because it sets time_scale = 0 first).
	elif dash_config.time_dip_value < 1.0 and dash_config.time_dip_duration > 0.0:
		Engine.time_scale = dash_config.time_dip_value
		get_tree().create_timer(dash_config.time_dip_duration, true, false, true).timeout.connect(
			func() -> void:
				if is_instance_valid(self):
					Engine.time_scale = 1.0
		)

	get_tree().create_timer(dash_config.cooldown).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				_dash_ready = true
	)


func _end_dash() -> void:
	_dash_active = false
	_dash_remaining = 0.0
	# Effect resets DashStrength to 0 internally and schedules SubViewport
	# shutdown after particles fully die. In-flight particles still drift and
	# fade naturally during the tail.
	_fire_effect.stop()
	# Defensive: if a dip lambda hasn't fired yet (or won't), restore time
	# scale here so a stalled dip can't outlive the burst.
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0
