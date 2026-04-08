class_name HealthComponent
extends Node

## Owns HP, lives, iframes, the respawn cooldown, and the invincibility cheat.
## Pure logic — no visual feedback, no scene-tree mutation. Ship root listens
## to the signals below and dispatches to siblings (HitFeedback, Hurtbox, FSM).
##
## Phase 4 Step 21: extracted from ship.gd. Cheat (A1) fused per Appendix A.
## Iframes still tick here until Phase 5 promotes them into the FSM.
##
## Respawn flow:
##   Ship.take_damage() → apply_damage() → _hp == 0 → emit died →
##   Ship cleans up + listens for respawn_ready → teleport + restore.
## HealthComponent itself does NOT touch the scene tree; the Ship root owns
## the death/respawn cleanup so this component stays portable to EnemyShip.

signal health_changed(current: int, maximum: int)
signal lives_changed(current: int, maximum: int)
signal died
signal respawn_ready
signal game_over
signal invincibility_changed(active: bool)
signal iframes_started
signal iframes_ended

const HIT_IFRAME_DURATION: float = 1.2
const RESPAWN_IFRAME_DURATION: float = 2.5

## Player ships respawn until lives run out; enemies will set this false in Phase 8.
@export var respawnable: bool = true

var _stats: ShipStats = null
var _hp: int = 0
var _lives: int = 0
var _iframes_left: float = 0.0
var _invincible: bool = false
var _is_dead: bool = false


func _ready() -> void:
	# Default-on for physics process: iframes need to tick. Phase 5 will move
	# this into the FSM and flip the default off.
	set_physics_process(true)
	set_process(false)


## Called by the entity root in its own _ready (after child _readys have run)
## to inject the Resource and emit the initial status. Stats is intentionally
## NOT an @export here because the player ship's stats Resource lives on the
## main.tscn ship instance — injecting it from the parent keeps that wiring
## centralized and avoids a parallel Health.stats override slot.
func setup(stats: ShipStats) -> void:
	assert(stats != null, "HealthComponent.setup: stats Resource is null")
	_stats = stats
	_hp = _stats.max_health
	_lives = _stats.max_lives
	# Defer initial emission so the entity root has a chance to wire up.
	call_deferred("_emit_initial_status")


func _emit_initial_status() -> void:
	health_changed.emit(_hp, _stats.max_health)
	lives_changed.emit(_lives, _stats.max_lives)


func _physics_process(delta: float) -> void:
	if _iframes_left > 0.0:
		_iframes_left -= delta
		if _iframes_left <= 0.0:
			iframes_ended.emit()


func _unhandled_input(event: InputEvent) -> void:
	# Secret invincibility cheat (Shift+5). Debug builds only — exporting a
	# release strips this entire branch.
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event
		if key_event.shift_pressed and key_event.physical_keycode == KEY_5:
			_invincible = not _invincible
			invincibility_changed.emit(_invincible)
			Events.cheat_toggled.emit(&"invincibility", _invincible)


## Single damage entry point. Returns true if the hit landed.
func apply_damage(_amount: int = 1) -> bool:
	if _is_dead or _iframes_left > 0.0 or _invincible:
		return false
	_hp -= 1
	health_changed.emit(_hp, _stats.max_health)
	if _hp <= 0:
		_enter_death()
		return true
	_start_iframes(HIT_IFRAME_DURATION)
	return true


## Reset HP to full and start respawn iframes. Called by Ship root after
## the respawn_ready signal lands and the entity has been teleported.
func reset_for_respawn() -> void:
	_hp = _stats.max_health
	_is_dead = false
	health_changed.emit(_hp, _stats.max_health)
	_start_iframes(RESPAWN_IFRAME_DURATION)


func get_hp() -> int:
	return _hp


func get_lives() -> int:
	return _lives


func is_dead() -> bool:
	return _is_dead


func has_iframes() -> bool:
	return _iframes_left > 0.0


func is_invincible() -> bool:
	return _invincible


func _enter_death() -> void:
	_is_dead = true
	_iframes_left = 0.0
	iframes_ended.emit()
	_lives -= 1
	lives_changed.emit(_lives, _stats.max_lives)
	died.emit()
	if _lives <= 0:
		game_over.emit()
		return
	if not respawnable:
		return
	# Schedule respawn cooldown. Phase 6 Step 34a will replace this lambda with
	# a Cooldown helper instance; the contract (emit respawn_ready when the
	# delay elapses) stays identical.
	get_tree().create_timer(_stats.respawn_delay).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				respawn_ready.emit()
	)


func _start_iframes(duration: float) -> void:
	_iframes_left = duration
	iframes_started.emit()
