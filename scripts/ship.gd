class_name Ship
extends CharacterBody2D
## Player-controlled ship — slim orchestrator that wires its child components
## together and re-emits their signals for legacy main.gd / HUD subscribers.
##
## Behavior lives in components:
##   PlayerInput  · Movement · Dash · Health · Hurtbox · HitFeedback
##
## Phase 4 Steps 21–25 + 32 extracted everything except cannon/broadside/mine
## drop wiring (Steps 26–28) and audio (Step 32). Ship still owns the legacy
## broadside/mine/respawn signals on the public surface so main.gd doesn't
## have to migrate this same commit; Step 27/28 will move those publishers.

signal cannon_fired(pos: Vector2, dir: Vector2)
signal mine_dropped(pos: Vector2)
signal health_changed(current: int, maximum: int)
signal lives_changed(current: int, maximum: int)
signal died
signal respawned
signal game_over
signal invincibility_changed(active: bool)

@export var config: ShipConfig
@export var dash_stats: DashStats
@export var stats: ShipStats

var _is_dead: bool = false
var _input_locked: bool = false
var _spawn_position: Vector2 = Vector2.ZERO
var _spawn_rotation: float = 0.0

@onready var _hull_sprite: Sprite2D = $HullSprite
@onready var _sail_sprite: Sprite2D = $SailSprite
@onready var _cannon_slots: Node2D = $CannonSlots
@onready var _fire_effect: DashFireEffect = $SternMarker/DashFireEffect
@onready var _player_input: PlayerInputComponent = $PlayerInput
@onready var _health_component: HealthComponent = $Health
@onready var _movement: MovementComponent = $Movement
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _hit_feedback: HitFeedbackComponent = $HitFeedback
@onready var _dash: DashComponent = $Dash
@onready var _broadside: BroadsideComponent = $Broadside
@onready var _mine_drop: MineDropComponent = $MineDrop
@onready var _audio: AudioEmitterComponent = $AudioEmitter
@onready var _ghost_sources: Array[Sprite2D] = [$HullSprite, $PoleSprite, $SailSprite]
@onready var _ghost_container: Node2D = get_parent() as Node2D


func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	assert(_hull_sprite != null, "Ship: HullSprite node is missing")
	assert(_sail_sprite != null, "Ship: SailSprite node is missing")
	assert(_cannon_slots != null, "Ship: CannonSlots node is missing")
	assert(_fire_effect != null, "Ship: SternMarker/DashFireEffect node is missing")
	assert(_player_input != null, "Ship: PlayerInput node is missing")
	assert(_health_component != null, "Ship: Health node is missing")
	assert(_movement != null, "Ship: Movement node is missing")
	assert(_hurtbox != null, "Ship: Hurtbox node is missing")
	assert(_hit_feedback != null, "Ship: HitFeedback node is missing")
	assert(_dash != null, "Ship: Dash node is missing")
	assert(_broadside != null, "Ship: Broadside node is missing")
	assert(_mine_drop != null, "Ship: MineDrop node is missing")
	assert(_audio != null, "Ship: AudioEmitter node is missing")
	assert(_ghost_container != null, "Ship: parent must be a Node2D world container")
	assert(config != null, "Ship: config Resource is missing")
	assert(dash_stats != null, "Ship: dash_stats Resource is missing")
	assert(stats != null, "Ship: stats (ShipStats) Resource is missing")
	_spawn_position = global_position
	_spawn_rotation = rotation
	_apply_config()
	_hit_feedback.setup(self, _hull_sprite, _sail_sprite)
	_health_component.health_changed.connect(_on_health_changed)
	_health_component.lives_changed.connect(_on_lives_changed)
	_health_component.died.connect(_on_health_died)
	_health_component.respawn_ready.connect(_on_health_respawn_ready)
	_health_component.game_over.connect(_on_health_game_over)
	_health_component.invincibility_changed.connect(_on_health_invincibility_changed)
	_health_component.iframes_started.connect(_hit_feedback.start_blink)
	_health_component.iframes_ended.connect(_hit_feedback.end_blink)
	_health_component.setup(stats)
	_movement.setup(self, stats, _player_input)
	_movement.rammed_enemy.connect(_on_movement_rammed_enemy)
	_hurtbox.hit_taken.connect(_on_hurtbox_hit_taken)
	_dash.setup(self, dash_stats, _player_input, _fire_effect, _ghost_sources, _ghost_container)
	_dash.dash_started.connect(_on_dash_started)
	_dash.dash_ended.connect(_on_dash_ended)
	_broadside.setup(_cannon_slots, stats)
	_broadside.cannon_fired.connect(_on_broadside_cannon_fired)
	_mine_drop.setup(self, stats)
	_mine_drop.mine_dropped.connect(_on_mine_drop_dropped)
	_audio.setup(self)
	# Wire local audio events. AudioManager is currently a no-op, but the
	# bus path is end-to-end testable: any clip added to the (future)
	# SoundLibrary against these StringNames will play immediately.
	_broadside.cannon_fired.connect(_on_audio_cannon_fired)
	_mine_drop.mine_dropped.connect(_on_audio_mine_dropped)
	_health_component.died.connect(_on_audio_died)
	_hurtbox.hit_taken.connect(_on_audio_hit_taken)


func _on_health_changed(current: int, maximum: int) -> void:
	_update_hull_variant(current, maximum)
	health_changed.emit(current, maximum)


func _on_lives_changed(current: int, maximum: int) -> void:
	lives_changed.emit(current, maximum)


func _on_health_game_over() -> void:
	game_over.emit()


func _on_health_invincibility_changed(active: bool) -> void:
	invincibility_changed.emit(active)


func _on_dash_started() -> void:
	_movement.set_enabled(false)


func _on_dash_ended() -> void:
	_movement.set_enabled(true)


func _on_movement_rammed_enemy(enemy: Node, normal: Vector2) -> void:
	# Mutual ram damage; iframes guard multi-hits. Damage is mutual only when
	# the player is NOT invincible — an invincible player just bounces off.
	if _health_component.has_iframes() or _is_dead:
		return
	take_damage(-normal)
	(enemy as EnemyShip).take_ram_damage(normal)


func _unhandled_input(event: InputEvent) -> void:
	# Invincibility cheat now lives in HealthComponent (A1 fusion).
	if _input_locked:
		return
	if _player_input.is_fire_port_just_pressed(event):
		_broadside.fire_port()
	elif _player_input.is_fire_starboard_just_pressed(event):
		_broadside.fire_starboard()
	elif _player_input.is_drop_mine_just_pressed(event):
		_mine_drop.try_drop()
	elif _player_input.is_dash_just_pressed(event):
		_dash.try_start()


## 0.0 = just dropped (fully on cooldown), 1.0 = ready to drop again.
## Forwarded to MineDropComponent so existing HUD callers (set up via
## _mine_cooldown_display.setup(_ship)) keep working.
func get_mine_cooldown_progress() -> float:
	return _mine_drop.get_cooldown_progress()


## Legacy public damage entry. SeaMine still routes through here via a
## physics shape query; cannonball-on-hurtbox detection now flows through
## HurtboxComponent.area_entered → hit_taken. Both paths converge on
## HealthComponent.apply_damage via _apply_damage().
func take_damage(_from_direction: Vector2) -> void:
	_hurtbox.process_hit(self)


func _on_hurtbox_hit_taken(_source: Node) -> void:
	_apply_damage()


func _apply_damage() -> void:
	if _is_dead:
		return
	if _health_component.apply_damage(1):
		_hit_feedback.play_hit()


func _update_hull_variant(current: int, maximum: int) -> void:
	var variant: int = clampi(maximum - current, 0, 3)
	_hull_sprite.region_rect = ShipConfig.get_hull_region(variant)


## HealthComponent emitted `died` — clean up the scene presence. The component
## owns the respawn cooldown and re-emits `respawn_ready` when it elapses.
func _on_health_died() -> void:
	_is_dead = true
	_input_locked = true
	_movement.set_locked(true)
	_dash.stop()
	_hit_feedback.end_blink()
	velocity = Vector2.ZERO
	visible = false
	# Disable collisions without tearing down the node so Main's signal
	# wiring survives the death → respawn cycle.
	set_collision_layer_value(1, false)
	set_collision_mask_value(2, false)  # enemies
	set_collision_mask_value(5, false)  # enemy projectiles
	_hurtbox.set_active(false)
	ExplosionSprite.create(
		get_parent(), global_position, "enemy_destruction", Vector2.ZERO, Vector2.ZERO
	)
	died.emit()


func _on_health_respawn_ready() -> void:
	global_position = _spawn_position
	rotation = _spawn_rotation
	velocity = Vector2.ZERO
	_is_dead = false
	_input_locked = false
	_movement.set_locked(false)
	visible = true
	set_collision_layer_value(1, true)
	set_collision_mask_value(2, true)
	set_collision_mask_value(5, true)
	_hurtbox.set_active(true)
	respawned.emit()
	_health_component.reset_for_respawn()


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


func _on_broadside_cannon_fired(pos: Vector2, dir: Vector2) -> void:
	cannon_fired.emit(pos, dir)


func _on_audio_cannon_fired(_pos: Vector2, _dir: Vector2) -> void:
	_audio.play(&"cannon_fire")


func _on_audio_mine_dropped(_pos: Vector2) -> void:
	_audio.play(&"mine_drop")


func _on_audio_died() -> void:
	_audio.play(&"ship_destroyed")


func _on_audio_hit_taken(_source: Node) -> void:
	_audio.play(&"ship_hit")


func _on_mine_drop_dropped(pos: Vector2) -> void:
	mine_dropped.emit(pos)
