extends Node

## Global signal bus. Carries cross-system events only — parent/child within a
## single scene communicates via direct signal connections, NOT through this
## bus.
##
## Phase 9 revision: the pre-Phase-9 rule "high-frequency per-frame signals
## stay off the bus" was dropped. Measured cost of one listener on a typed
## value-type signal is negligible at the ~5 emits/frame water-displacement
## volume, and the uniformity win (one rule, no carve-outs) is worth more
## than the micro-optimization.
##
## Discipline rules (see plan section "Signal bus" + ADR 007 to come):
##   1. Components do NOT touch this bus directly. The entity root listens to
##      its own components and re-emits to the bus.
##   2. Bus payloads MUST be typed; no untyped Dictionary payloads.
##   3. Autoload registration order is Events \u2192 GameState \u2192 AudioManager.
##      Events is FIRST so any node connecting in its own _ready() finds the
##      signals already declared.
##   4. NO file-scope `preload()` of other autoloads from this script. Cross-
##      autoload references happen only inside `_ready()` or later.

# All signals on this bus are intentionally declared without an in-class
# emitter \u2014 they exist purely for external subscribers, so the
# "unused_signal" warning is wrong by design here.
@warning_ignore_start("unused_signal")

# --- Combat ---

signal player_damaged(amount: int, source: Node)
signal player_died
signal player_respawned
signal enemy_damaged(enemy: Node, amount: int, source: Node)
signal enemy_destroyed(enemy: Node, by_mine: bool)

# --- Waves ---

signal wave_announced(index: int)
signal wave_started(index: int, enemy_count: int)
signal wave_cleared(index: int, duration: float)
signal run_ended(stats: RunStats, victory: bool)

# --- World / VFX ---

signal explosion_requested(pos: Vector2, kind: StringName, dir: Vector2, vel: Vector2)
signal screen_shake_requested(trauma: float)
signal camera_zoom_punch_requested(scale_amount: float, duration: float)
signal mine_dropped(pos: Vector2)
signal cannonball_fired(pos: Vector2, dir: Vector2, by_player: bool)
signal cannonball_water_impact(pos: Vector2)

# --- Water displacement (Phase 9 Step 42) ---
# Listeners live in water_listener.gd. Publishers are WaterEffectsManager
# (per-frame wake/bob + cannonball impact re-emit) and SpawnService
# (mine-destruction impact).

signal displacement_impact_requested(pos: Vector2, radius_px: float, duration: float)
signal displacement_wake_ring_requested(pos: Vector2)
signal displacement_bob_requested(pos: Vector2, phase: float)

# --- Audio ---

# `sound_id` (not "name") to avoid shadowing Node.name.
signal sound_requested(sound_id: StringName, pos: Vector2)

# --- Meta / stats (typed per-stat signals; replaces generic stat_recorded) ---

signal kill_recorded
signal death_recorded
signal damage_recorded(amount: int)
signal wave_time_recorded(index: int, seconds: float)
# `cheat_id` (not "name") to avoid shadowing Node.name.
signal cheat_toggled(cheat_id: StringName, active: bool)

@warning_ignore_restore("unused_signal")


func _ready() -> void:
	# Empty bodies; this autoload exists purely to host the signals above.
	# Subscribers connect from their own _ready() (or later) callbacks.
	pass
