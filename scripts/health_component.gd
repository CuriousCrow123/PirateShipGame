class_name HealthComponent
extends Node

## Owns HP, lives, and the respawn cooldown. Pure logic — no visual feedback,
## no scene-tree mutation. Ship root listens to the signals below and
## dispatches to siblings (HitFeedback, Hurtbox, FSM).
##
## Phase 4 Step 21: extracted from ship.gd. Cheat (A1) fused per Appendix A.
## Phase 5 Step 33: iframe ticking, _is_dead, _invincible, and the Shift+5
## cheat input handler all moved into ShipFSM. HealthComponent now queries
## the FSM for vulnerability and asks it to enter/exit DEAD on death/respawn.
##
## Respawn flow:
##   Ship.take_damage() → apply_damage() → _hp == 0 → fsm.enter_dead() →
##   emit died → Ship cleans up + listens for respawn_ready → teleport +
##   reset_for_respawn() → fsm.respawn(RESPAWN_IFRAME_DURATION).
## HealthComponent itself does NOT touch the scene tree; the Ship root owns
## the death/respawn cleanup so this component stays portable to EnemyShip.

signal health_changed(current: int, maximum: int)
signal lives_changed(current: int, maximum: int)
signal died
signal respawn_ready
signal game_over

const HIT_IFRAME_DURATION: float = 1.2
const RESPAWN_IFRAME_DURATION: float = 2.5

## Player ships respawn until lives run out; enemies will set this false in Phase 8.
@export var respawnable: bool = true

var _stats: ShipStats = null
var _fsm: ShipFSM = null
var _hp: int = 0
var _lives: int = 0
var _respawn_cooldown: Cooldown = Cooldown.new()
var _respawn_pending: bool = false


func _ready() -> void:
	# Default-off per component doctrine. Iframe ticking moved to ShipFSM.
	# _process is enabled transiently during the respawn cooldown so we can
	# poll the wall-clock Cooldown and emit respawn_ready exactly once.
	set_physics_process(false)
	set_process(false)


func _process(_delta: float) -> void:
	if _respawn_pending and _respawn_cooldown.is_ready():
		_respawn_pending = false
		set_process(false)
		respawn_ready.emit()


## Called by the entity root in its own _ready (after child _readys have run)
## to inject the Resource and emit the initial status. Stats is intentionally
## NOT an @export here because the player ship's stats Resource lives on the
## main.tscn ship instance — injecting it from the parent keeps that wiring
## centralized and avoids a parallel Health.stats override slot.
func setup(stats: ShipStats, fsm: ShipFSM) -> void:
	assert(stats != null, "HealthComponent.setup: stats Resource is null")
	assert(fsm != null, "HealthComponent.setup: ShipFSM is null")
	_stats = stats
	_fsm = fsm
	_hp = _stats.max_health
	_lives = _stats.max_lives
	# Defer initial emission so the entity root has a chance to wire up.
	call_deferred("_emit_initial_status")


func _emit_initial_status() -> void:
	health_changed.emit(_hp, _stats.max_health)
	lives_changed.emit(_lives, _stats.max_lives)


## Single damage entry point. Returns true if the hit landed.
func apply_damage(_amount: int = 1) -> bool:
	if not _fsm.is_vulnerable():
		return false
	_hp -= 1
	health_changed.emit(_hp, _stats.max_health)
	if _hp <= 0:
		_enter_death()
		return true
	_fsm.start_iframes(HIT_IFRAME_DURATION)
	return true


## Reset HP to full and start respawn iframes. Called by Ship root after
## the respawn_ready signal lands and the entity has been teleported.
func reset_for_respawn() -> void:
	_hp = _stats.max_health
	health_changed.emit(_hp, _stats.max_health)
	_fsm.respawn(RESPAWN_IFRAME_DURATION)


func get_hp() -> int:
	return _hp


func get_lives() -> int:
	return _lives


func is_dead() -> bool:
	return _fsm.is_dead()


func has_iframes() -> bool:
	return _fsm.has_iframes()


func is_invincible() -> bool:
	return _fsm.is_invincible()


func _enter_death() -> void:
	_fsm.enter_dead()
	_lives -= 1
	lives_changed.emit(_lives, _stats.max_lives)
	died.emit()
	if _lives <= 0:
		game_over.emit()
		return
	if not respawnable:
		return
	# Phase 6 Step 34a: wall-clock Cooldown + _process poll replaces the old
	# SceneTreeTimer lambda. Contract is identical — respawn_ready emits once
	# after respawn_delay elapses.
	_respawn_cooldown.start(_stats.respawn_delay)
	_respawn_pending = true
	set_process(true)
