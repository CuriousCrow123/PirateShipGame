class_name EnemyShip
extends CharacterBody2D
## Enemy ship — Phase 8 thin orchestrator. Reuses the same components the
## player Ship does (HealthComponent, HurtboxComponent, HitFeedbackComponent,
## BroadsideComponent, Cannon, AudioEmitterComponent, ShipFSM) plus a
## bespoke EnemyAIMovement (Step 40) for chase-and-circle behavior.
##
## Public surface kept for SpawnService / wake bookkeeping:
##   * destroyed(ship, by_mine) — terminal death signal (HealthComponent.died)
##   * cannon_fired(pos, dir)   — re-emitted from BroadsideComponent
##   * setup(target)            — inject the player ship as the AI target
##   * apply_wave_modifiers(speed_mult, cooldown_mult) — per-wave scaling
##   * is_destroyed()           — alive/dead check used by SpawnService
##                                + WaterEffectsManager
##   * consume_wake_distance() / get_wake_ring_position() — wake bookkeeping
##   * take_damage(direction, by_mine) — sea_mine still calls this directly
##                                       via its physics shape query

signal destroyed(ship: EnemyShip, by_mine: bool)
signal cannon_fired(pos: Vector2, dir: Vector2)

const WAKE_RING_INTERVAL: float = 24.0  # px between wake-ring stamps

@export var archetype: EnemyArchetype

var _is_destroyed: bool = false
var _target: Node2D = null
var _by_mine_flag: bool = false  # carried from take_damage to died handler
var _wake_accum: float = 0.0
var _last_wake_pos: Vector2 = Vector2.ZERO

@onready var _hull_sprite: Sprite2D = $HullSprite
@onready var _sail_sprite: Sprite2D = $SailSprite
@onready var _collision_shape: CollisionShape2D = $CollisionShape
@onready var _cannon_slots: Node2D = $CannonSlots
@onready var _fsm: ShipFSM = $FSM
@onready var _health: HealthComponent = $Health
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _hit_feedback: HitFeedbackComponent = $HitFeedback
@onready var _broadside: BroadsideComponent = $Broadside
@onready var _ai_movement: EnemyAIMovement = $AIMovement
@onready var _audio: AudioEmitterComponent = $AudioEmitter


func _ready() -> void:
	assert(_hull_sprite != null, "EnemyShip: HullSprite not found")
	assert(_sail_sprite != null, "EnemyShip: SailSprite not found")
	assert(_collision_shape != null, "EnemyShip: CollisionShape not found")
	assert(_cannon_slots != null, "EnemyShip: CannonSlots not found")
	assert(_fsm != null, "EnemyShip: FSM not found")
	assert(_health != null, "EnemyShip: Health not found")
	assert(_hurtbox != null, "EnemyShip: Hurtbox not found")
	assert(_hit_feedback != null, "EnemyShip: HitFeedback not found")
	assert(_broadside != null, "EnemyShip: Broadside not found")
	assert(_ai_movement != null, "EnemyShip: AIMovement not found")
	assert(_audio != null, "EnemyShip: AudioEmitter not found")
	assert(archetype != null, "EnemyShip: archetype Resource is missing")

	_last_wake_pos = global_position

	# Mute the player-only Shift+5 invincibility cheat on enemy FSMs — the
	# cheat handler lives in ShipFSM._unhandled_input and would otherwise
	# fire on every enemy instance simultaneously.
	_fsm.set_process_unhandled_input(false)

	# Component wiring (FSM-first, then components that subscribe to it).
	_health.respawnable = false
	_hit_feedback.shake_on_hit = false
	_health.setup(archetype.hp, 1, 0.0, _fsm)
	_hurtbox.connect_fsm(_fsm)
	_hit_feedback.setup(self, _hull_sprite, _sail_sprite)
	_fsm.iframes_started.connect(_hit_feedback.start_blink)
	_fsm.iframes_ended.connect(_hit_feedback.end_blink)
	_broadside.setup(_cannon_slots, archetype.broadside_cooldown)
	_broadside.cannon_fired.connect(_on_broadside_cannon_fired)
	_ai_movement.setup(self, archetype)
	_ai_movement.connect_fsm(_fsm)
	_ai_movement.broadside_fire_requested.connect(_on_broadside_fire_requested)
	_audio.setup(self)
	_health.died.connect(_on_health_died)
	_hurtbox.hit_taken.connect(_on_hurtbox_hit_taken)

	_randomize_appearance()
	add_to_group("enemy_ships")


func is_destroyed() -> bool:
	return _is_destroyed


func setup(target: Node2D) -> void:
	_target = target
	_ai_movement.set_target(target)


func apply_wave_modifiers(speed_mult: float, cooldown_mult: float) -> void:
	## Per-wave difficulty scaling. Called by SpawnService right after
	## setup() so the modifiers stack onto the archetype defaults rather
	## than baseline constants.
	_ai_movement.apply_wave_modifiers(speed_mult)
	_broadside.fire_rate_mult = 1.0 / cooldown_mult


func consume_wake_distance(traveled: float) -> bool:
	## Returns true (and resets) when the enemy has moved >=
	## WAKE_RING_INTERVAL since the last wake ring. WaterEffectsManager
	## calls this each frame from its per-enemy loop.
	_wake_accum += traveled
	if _wake_accum >= WAKE_RING_INTERVAL:
		_wake_accum = 0.0
		return true
	return false


func get_wake_ring_position() -> Vector2:
	return global_position - transform.y * 12.0


## Public damage entry point. Cannonballs hit the HurtboxComponent.Area2D
## and resolve to this method via the entity root; sea_mine still uses a
## physics shape query against bodies and routes through here as well.
## The `_amount` parameter is currently ignored — HealthComponent always
## applies 1 HP per hit. Per-source damage scaling is a Phase 11+ task.
func take_damage(_from_direction: Vector2, _amount: int = 1, by_mine: bool = false) -> void:
	if _is_destroyed:
		return
	_by_mine_flag = by_mine
	_hurtbox.process_hit(self)


func _on_hurtbox_hit_taken(_source: Node) -> void:
	if _is_destroyed:
		return
	if _health.apply_damage(1):
		_hit_feedback.play_hit()
		_apply_hull_damage_variant()


func _apply_hull_damage_variant() -> void:
	# 0=healthy, 3=heavily damaged. HealthComponent emits health_changed
	# but enemies don't subscribe to it; the variant update only matters
	# right after a hit lands, so do it inline.
	var damage_variant: int = archetype.hp - _health.get_hp()
	_hull_sprite.region_rect = ShipConfig.get_hull_region(mini(damage_variant, 3))


func _on_health_died() -> void:
	_is_destroyed = true
	# Disable collision immediately (deferred for physics safety).
	_collision_shape.set_deferred("disabled", true)
	# Large destruction explosion — parented to get_parent() (Main) so it
	# survives this node's queue_free.
	ExplosionSprite.create(
		get_parent(), global_position, "enemy_destruction", Vector2.ZERO, velocity
	)
	destroyed.emit(self, _by_mine_flag)
	# Fade out then remove.
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


func _on_broadside_cannon_fired(pos: Vector2, dir: Vector2) -> void:
	cannon_fired.emit(pos, dir)


func _on_broadside_fire_requested(starboard: bool) -> void:
	if _is_destroyed:
		return
	if starboard:
		_broadside.fire_starboard()
	else:
		_broadside.fire_port()


func _randomize_appearance() -> void:
	var sail_variant: int = randi_range(0, 23)
	_sail_sprite.region_rect = ShipConfig.get_sail_region(sail_variant)
	_hull_sprite.region_rect = ShipConfig.get_hull_region(0)
