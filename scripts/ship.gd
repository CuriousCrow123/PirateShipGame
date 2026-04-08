class_name Ship
extends CharacterBody2D
## Player-controlled ship with floaty, momentum-based movement.
## Thrust accumulates velocity; viscous drag decays it exponentially.
## Brake (S key) decelerates to zero via move_toward.
## Broadside cannons fire perpendicular to the ship (Q = port, E = starboard).
## Space dashes the ship forward with a tunable feel mode (see DashStats).

signal cannon_fired(pos: Vector2, dir: Vector2)
signal mine_dropped(pos: Vector2)
signal health_changed(current: int, maximum: int)
signal lives_changed(current: int, maximum: int)
signal died
signal respawned
signal game_over
signal invincibility_changed(active: bool)

const HIT_TRAUMA: float = 0.85
const HIT_FLASH_DURATION: float = 0.35
const HIT_SHAKE_DURATION: float = 0.6
const HIT_SHAKE_MAX_INTENSITY: float = 5.0
const HIT_IFRAME_DURATION: float = 1.2
const RESPAWN_IFRAME_DURATION: float = 2.5
const IFRAME_BLINK_INTERVAL: float = 0.08  # seconds per on/off cycle

@export var config: ShipConfig
@export var dash_stats: DashStats
@export var stats: ShipStats

var _port_cooldown: float = 0.0
var _starboard_cooldown: float = 0.0
var _mine_cooldown_left: float = 0.0
var _dash_ready: bool = true
var _dash_active: bool = false
var _dash_remaining: float = 0.0
var _next_ghost_in: float = 0.0
var _ghost_additive_material: CanvasItemMaterial
var _hit_flash_tween: Tween = null
var _hit_shake_timer: float = 0.0
var _hull_original_pos: Vector2 = Vector2.ZERO
var _sail_original_pos: Vector2 = Vector2.ZERO
var _health: int = 0
var _lives: int = 0
var _iframes_left: float = 0.0
var _is_dead: bool = false
var _input_locked: bool = false
var _spawn_position: Vector2 = Vector2.ZERO
var _spawn_rotation: float = 0.0
var _blink_tween: Tween = null
var _invincible: bool = false

@onready var _hull_sprite: Sprite2D = $HullSprite
@onready var _sail_sprite: Sprite2D = $SailSprite
@onready var _cannon_slots: Node2D = $CannonSlots
@onready var _fire_effect: DashFireEffect = $SternMarker/DashFireEffect
@onready var _player_input: PlayerInputComponent = $PlayerInput
@onready var _ghost_sources: Array[Sprite2D] = [$HullSprite, $PoleSprite, $SailSprite]
@onready var _ghost_container: Node2D = get_parent() as Node2D


func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	assert(_hull_sprite != null, "Ship: HullSprite node is missing")
	assert(_sail_sprite != null, "Ship: SailSprite node is missing")
	assert(_cannon_slots != null, "Ship: CannonSlots node is missing")
	assert(_fire_effect != null, "Ship: SternMarker/DashFireEffect node is missing")
	assert(_player_input != null, "Ship: PlayerInput node is missing")
	assert(_ghost_container != null, "Ship: parent must be a Node2D world container")
	assert(config != null, "Ship: config Resource is missing")
	assert(dash_stats != null, "Ship: dash_stats Resource is missing")
	assert(stats != null, "Ship: stats (ShipStats) Resource is missing")
	# Cached additive material reused across all ghost spawns (Godot does NOT
	# fork CanvasItemMaterial on assignment — all ghosts share the same RID
	# and batch together).
	_ghost_additive_material = CanvasItemMaterial.new()
	_ghost_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_hull_original_pos = _hull_sprite.position
	_sail_original_pos = _sail_sprite.position
	_spawn_position = global_position
	_spawn_rotation = rotation
	_health = stats.max_health
	_lives = stats.max_lives
	_apply_config()
	# Defer so Main has time to wire signals in its own _ready before the
	# initial health_changed / lives_changed emit.
	call_deferred("_emit_initial_status")


func _emit_initial_status() -> void:
	health_changed.emit(_health, stats.max_health)
	lives_changed.emit(_lives, stats.max_lives)


func _exit_tree() -> void:
	# Defensive: if a time_dip lambda failed mid-burst (freed instance, etc.),
	# make sure we never leave the engine in scaled time when the ship leaves.
	if not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0


func _physics_process(delta: float) -> void:
	if _iframes_left > 0.0:
		_iframes_left -= delta
		if _iframes_left <= 0.0:
			_end_blink()
	if _is_dead:
		return
	if _port_cooldown > 0.0:
		_port_cooldown -= delta
	if _starboard_cooldown > 0.0:
		_starboard_cooldown -= delta
	if _mine_cooldown_left > 0.0:
		_mine_cooldown_left -= delta

	if _input_locked:
		move_and_slide()
		return

	var is_braking: bool = _player_input.is_brake_pressed()

	if _dash_active:
		_dash_remaining -= delta
		if _dash_remaining <= 0.0:
			_end_dash()
			_apply_normal_movement(delta, is_braking)
			return

		var turn_input: float = _player_input.get_turn_axis()

		match dash_stats.feel_mode:
			DashStats.FeelMode.LOCKED_HEADING:
				velocity *= stats.linear_drag
				# stats.thrust + steering ignored during locked-heading burst
			DashStats.FeelMode.STEERABLE:
				if not is_braking and _player_input.is_thrust_pressed():
					velocity += transform.y * stats.thrust * delta
				velocity *= stats.linear_drag
				rotation += turn_input * stats.turn_speed * delta
			DashStats.FeelMode.VELOCITY_ALIGNED:
				velocity *= stats.linear_drag
				rotation += turn_input * stats.turn_speed * delta
			DashStats.FeelMode.OVERSPEED_CAP:
				if not is_braking and _player_input.is_thrust_pressed():
					velocity += transform.y * stats.thrust * delta
				velocity *= dash_stats.overspeed_drag
				rotation += turn_input * stats.turn_speed * delta

		move_and_slide()
		_process_collision_pushback(dash_stats.collision_pushback_scale)
		return

	_apply_normal_movement(delta, is_braking)


func _apply_normal_movement(delta: float, is_braking: bool) -> void:
	if not is_braking and _player_input.is_thrust_pressed():
		velocity += transform.y * stats.thrust * delta

	if is_braking:
		velocity = velocity.move_toward(Vector2.ZERO, stats.brake_decel * delta)
	else:
		velocity *= stats.linear_drag

	var turn_input: float = _player_input.get_turn_axis()
	rotation += turn_input * stats.turn_speed * delta

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
			var enemy: EnemyShip = collider as EnemyShip
			# Mutual ram damage; iframes on both sides guard multi-hits across
			# physics sub-steps. Return after the first collision to ensure one
			# collision event → at most one damage application per frame.
			# Ship uses its regular iframe system; enemy uses take_ram_damage so
			# cannonball DPS stays unaffected by ram iframes. Damage is mutual
			# only when the player is NOT invincible — an invincible player
			# should just bounce off without harming the enemy either.
			if _iframes_left <= 0.0 and not _is_dead:
				take_damage(-collision.get_normal())
				enemy.take_ram_damage(collision.get_normal())
			return


func _process(delta: float) -> void:
	# Visuals run on render frames so the burst animates smoothly on
	# high-refresh displays. Motion stays in _physics_process.
	if _dash_active:
		_tick_dash_visuals(delta)
	_process_hit_shake(delta)


func _tick_dash_visuals(delta: float) -> void:
	var t: float = 1.0 - clampf(_dash_remaining / dash_stats.duration, 0.0, 1.0)
	var dash_strength: float = 1.0
	if dash_stats.intensity_curve != null:
		dash_strength = dash_stats.intensity_curve.sample_baked(t)
	_fire_effect.set_dash_strength(dash_strength)
	# Ghost trail spawn ticker.
	if dash_stats.ghost_count > 0:
		_next_ghost_in -= delta
		if _next_ghost_in <= 0.0:
			_spawn_ghost()
			_next_ghost_in = dash_stats.ghost_spawn_interval


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
		ghost.modulate = dash_stats.ghost_start_tint
		# Render ghosts above the ship (ship.z_index = 2). Absolute z since the
		# ghost is reparented to the world container, not the ship.
		ghost.z_as_relative = false
		ghost.z_index = 10
		if dash_stats.ghost_additive:
			ghost.material = _ghost_additive_material
		_ghost_container.add_child(ghost)
		var tw: Tween = ghost.create_tween()
		tw.tween_property(
			ghost, "modulate", dash_stats.ghost_end_tint, dash_stats.ghost_fade_duration
		)
		tw.tween_callback(ghost.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	# Secret Invincible cheat (Shift+5). Checked BEFORE the input_locked
	# guard so the cheat still toggles during respawn iframes / death.
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event
		if key_event.shift_pressed and key_event.physical_keycode == KEY_5:
			_toggle_invincibility()
			return
	if _input_locked:
		return
	if _player_input.is_fire_port_just_pressed(event) and _port_cooldown <= 0.0:
		_fire_broadside("port")
	elif _player_input.is_fire_starboard_just_pressed(event) and _starboard_cooldown <= 0.0:
		_fire_broadside("starboard")
	elif _player_input.is_drop_mine_just_pressed(event) and _mine_cooldown_left <= 0.0:
		_drop_mine()
	elif _player_input.is_dash_just_pressed(event) and _dash_ready and not _dash_active:
		_start_dash()


## 0.0 = just dropped (fully on cooldown), 1.0 = ready to drop again.
func get_mine_cooldown_progress() -> float:
	if stats.mine_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - (_mine_cooldown_left / stats.mine_cooldown), 0.0, 1.0)


func _toggle_invincibility() -> void:
	_invincible = not _invincible
	invincibility_changed.emit(_invincible)


## Takes a single hit. Respects iframes; decrements HP; fires visual feedback;
## triggers death at zero. This is the sole public damage entry point.
func take_damage(_from_direction: Vector2) -> void:
	if _is_dead or _iframes_left > 0.0 or _invincible:
		return
	_health -= 1
	_apply_hit_feedback()
	_update_hull_variant()
	health_changed.emit(_health, stats.max_health)
	if _health <= 0:
		_enter_death()
		return
	_start_iframes(HIT_IFRAME_DURATION)


func _update_hull_variant() -> void:
	var variant: int = clampi(stats.max_health - _health, 0, 3)
	_hull_sprite.region_rect = ShipConfig.get_hull_region(variant)


func _start_iframes(duration: float) -> void:
	_iframes_left = duration
	_start_blink_tween()


func _start_blink_tween() -> void:
	if _blink_tween and _blink_tween.is_valid():
		_blink_tween.kill()
	_blink_tween = create_tween().set_loops()
	_blink_tween.tween_property(self, "modulate:a", 0.35, IFRAME_BLINK_INTERVAL)
	_blink_tween.tween_property(self, "modulate:a", 1.0, IFRAME_BLINK_INTERVAL)


func _end_blink() -> void:
	if _blink_tween and _blink_tween.is_valid():
		_blink_tween.kill()
	_blink_tween = null
	modulate.a = 1.0


func _enter_death() -> void:
	_is_dead = true
	_input_locked = true
	if _dash_active:
		_end_dash()
	_end_blink()
	velocity = Vector2.ZERO
	visible = false
	# Disable collisions without tearing down the node so Main's signal
	# wiring survives the death → respawn cycle.
	set_collision_layer_value(1, false)
	set_collision_mask_value(2, false)  # enemies
	set_collision_mask_value(5, false)  # enemy projectiles
	ExplosionSprite.create(
		get_parent(), global_position, "enemy_destruction", Vector2.ZERO, Vector2.ZERO
	)
	_lives -= 1
	lives_changed.emit(_lives, stats.max_lives)
	died.emit()
	if _lives <= 0:
		# Terminal death — no respawn. Main listens for game_over and shows
		# the stats screen.
		game_over.emit()
		return
	get_tree().create_timer(stats.respawn_delay).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				_respawn()
	)


func _respawn() -> void:
	global_position = _spawn_position
	rotation = _spawn_rotation
	velocity = Vector2.ZERO
	_health = stats.max_health
	_update_hull_variant()
	_is_dead = false
	_input_locked = false
	visible = true
	set_collision_layer_value(1, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(5, true)
	respawned.emit()
	health_changed.emit(_health, stats.max_health)
	_start_iframes(RESPAWN_IFRAME_DURATION)


## Visual-only hit feedback: camera shake + per-sprite shake + white flash.
func _apply_hit_feedback() -> void:
	Events.screen_shake_requested.emit(HIT_TRAUMA)
	_hit_shake_timer = HIT_SHAKE_DURATION
	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	modulate = Color(3.0, 3.0, 3.0, 1.0)
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(self, "modulate", Color.WHITE, HIT_FLASH_DURATION)


func _process_hit_shake(delta: float) -> void:
	if _hit_shake_timer <= 0.0:
		return
	_hit_shake_timer -= delta
	if _hit_shake_timer <= 0.0:
		_hull_sprite.position = _hull_original_pos
		_sail_sprite.position = _sail_original_pos
		return
	var intensity: float = _hit_shake_timer / HIT_SHAKE_DURATION * HIT_SHAKE_MAX_INTENSITY
	var offset: Vector2 = Vector2(
		roundf(randf_range(-intensity, intensity)), roundf(randf_range(-intensity, intensity))
	)
	_hull_sprite.position = _hull_original_pos + offset
	_sail_sprite.position = _sail_original_pos + offset


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
		_port_cooldown = stats.broadside_cooldown
	else:
		_starboard_cooldown = stats.broadside_cooldown


func _drop_mine() -> void:
	# Drop behind the stern so the mine lands clear of the ship's hull and
	# reads as "kicked off the back". transform.y is the ship's forward axis
	# (see the wake ring offset in main.gd which uses the same convention).
	var drop_pos: Vector2 = global_position - transform.y * 24.0
	mine_dropped.emit(drop_pos)
	_mine_cooldown_left = stats.mine_cooldown


func _start_dash() -> void:
	_dash_ready = false
	_dash_active = true
	_dash_remaining = dash_stats.duration

	# Apply initial impulse based on feel mode.
	match dash_stats.feel_mode:
		DashStats.FeelMode.VELOCITY_ALIGNED:
			if velocity.length() < 1.0:
				velocity += transform.y * dash_stats.impulse_speed
			else:
				velocity += velocity.normalized() * dash_stats.impulse_speed
		_:
			# Dash has three behaviors at once:
			# - Forward component is kept (so dashing while already moving
			#   forward stacks → actually goes faster).
			# - Backward component is discarded (reverse dash = clean reset,
			#   not an anemic trickle fighting prior momentum).
			# - Perpendicular component is discarded (sharp turn-dashes
			#   don't get dragged sideways by prior drift).
			var forward: Vector2 = transform.y
			var kept_forward_speed: float = maxf(velocity.dot(forward), 0.0)
			velocity = forward * (kept_forward_speed + dash_stats.impulse_speed)

	# Push current fire-config uniforms onto the 3D effect and start emitting.
	# The effect renders into a 32x64 SubViewport for pixel-art crunch and
	# composites back into 2D via SubViewportContainer.
	_fire_effect.start(dash_stats)

	# Reset ghost spawn timer so the first ghost spawns next render tick.
	_next_ghost_in = 0.0

	# Bump shake trauma via the bus — GameCamera owns the shake state now.
	Events.screen_shake_requested.emit(dash_stats.shake_trauma_initial)

	# Optional zoom punch — GameCamera's bus listener tweens its own zoom.
	if dash_stats.zoom_punch_duration > 0.0:
		Events.camera_zoom_punch_requested.emit(
			dash_stats.zoom_punch_target, dash_stats.zoom_punch_duration
		)

	# Optional Celeste-style freeze frames at burst start.
	if dash_stats.freeze_frames > 0:
		var freeze_seconds: float = float(dash_stats.freeze_frames) / 60.0
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
	elif dash_stats.time_dip_value < 1.0 and dash_stats.time_dip_duration > 0.0:
		Engine.time_scale = dash_stats.time_dip_value
		get_tree().create_timer(dash_stats.time_dip_duration, true, false, true).timeout.connect(
			func() -> void:
				if is_instance_valid(self):
					Engine.time_scale = 1.0
		)

	get_tree().create_timer(dash_stats.cooldown).timeout.connect(
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
