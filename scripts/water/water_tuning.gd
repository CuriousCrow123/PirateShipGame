class_name WaterTuning
extends Resource

## Phase 9 Step 43 — Tunable constants for the water displacement / wake
## trail subsystem. Extracted from magic numbers previously inline in
## water_effects_manager.gd and water_chunks.gd.
##
## Hot-reload policy: WaterEffectsManager reads these fields per-frame in
## _process, so editing this resource in the inspector while the game is
## running propagates live without a restart (matches the
## default_ship_stats.tres hot-reload acceptance criterion).

# --- Player wake ring spawning ---

## Distance the ship travels between wake ring spawns (pixels).
@export var wake_ring_spacing: float = 16.0

## Minimum player speed (px/sec) to spawn wake rings.
@export var wake_ring_speed_threshold: float = 5.0

## Perpendicular offset from ship center to wake ring spawn point (pixels).
@export var wake_ring_offset: float = 12.0

# --- Water shader WakeTrailStrength mapping ---

## Player speed (px/sec) mapped to the maximum WakeTrailStrength value.
@export var wake_speed_cap: float = 120.0

## WakeTrailStrength at idle (player speed = 0).
@export var wake_strength_idle: float = 2.0

## WakeTrailStrength at wake_speed_cap and above.
@export var wake_strength_max: float = 10.0

# --- Cannonball water-impact displacement pulse ---

@export var cannonball_impact_radius: float = 64.0
@export var cannonball_impact_duration: float = 2.0

# --- Mine-destruction displacement pulse ---

@export var mine_explosion_impact_radius: float = 128.0
@export var mine_explosion_impact_duration: float = 2.5
