class_name ExplosionConfig
extends Resource
## Runtime-editable explosion parameters, saved as res://resources/explosion_config.tres.
## Open the .tres in the Godot editor while the game runs — changes propagate to the
## running game (shared Resource cache) AND persist to disk on save.
## Changes apply to NEW spawns — in-flight explosions keep the values they started with.
##
## All values shown are the concrete defaults.
## Per-type groups: muzzle_flash, cannonball_impact, enemy_destruction, sea_mine.

## Keys that are set per-type via get_params() below.
const _TYPE_KEYS: PackedStringArray = [
	"lifetime",
	"cone_spread",
	"vert_velocity",
	"vert_amount",
	"horiz_amount",
	"horiz_velocity_min",
	"horiz_velocity_max",
	"vert_damping",
	"horiz_damping",
	"particle_scale",
	"turbulence_strength",
	"turbulence_influence",
	"dark_color",
	"fire_color",
	"bright_alpha_scale",
	"dark_alpha_scale",
	"smooth_step_edge",
	"bright_dissolve_scale",
	"dark_dissolve_scale",
]

# --- Muzzle Flash (cannon firing) ---
@export_group("Muzzle Flash")
@export var muzzle_flash_lifetime: float = 1.2
@export var muzzle_flash_cone_spread: float = 0.0
@export var muzzle_flash_vert_velocity: float = 100.0
@export var muzzle_flash_vert_amount: int = 12
@export var muzzle_flash_horiz_amount: int = 6
@export var muzzle_flash_horiz_velocity_min: float = 5.5
@export var muzzle_flash_horiz_velocity_max: float = 11.0
@export var muzzle_flash_vert_damping: float = 23.0
@export var muzzle_flash_horiz_damping: float = 30.0
@export var muzzle_flash_particle_scale: float = 2.0
@export var muzzle_flash_turbulence_strength: float = 3.0
@export var muzzle_flash_turbulence_influence: float = 0.25
@export var muzzle_flash_dark_color: Color = Color(0.55, 0.52, 0.48, 1)
@export var muzzle_flash_fire_color: Color = Color(1, 0.5, 0.08, 1)
@export_range(0.0, 2.0, 0.01) var muzzle_flash_bright_alpha_scale: float = 1.0
@export_range(0.0, 2.0, 0.01) var muzzle_flash_dark_alpha_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var muzzle_flash_smooth_step_edge: float = 0.71
@export_range(0.5, 2.0, 0.01) var muzzle_flash_bright_dissolve_scale: float = 1.95
@export_range(0.5, 2.0, 0.01) var muzzle_flash_dark_dissolve_scale: float = 0.8

# --- Cannonball Impact (water splash & enemy hit) ---
@export_group("Cannonball Impact")
@export var cannonball_impact_lifetime: float = 1.2
@export var cannonball_impact_cone_spread: float = 45.0
@export var cannonball_impact_vert_velocity: float = 15.0
@export var cannonball_impact_vert_amount: int = 15
@export var cannonball_impact_horiz_amount: int = 10
@export var cannonball_impact_horiz_velocity_min: float = 5.5
@export var cannonball_impact_horiz_velocity_max: float = 11.0
@export var cannonball_impact_vert_damping: float = 23.0
@export var cannonball_impact_horiz_damping: float = 30.0
@export var cannonball_impact_particle_scale: float = 2.0
@export var cannonball_impact_turbulence_strength: float = 3.0
@export var cannonball_impact_turbulence_influence: float = 0.25
@export var cannonball_impact_dark_color: Color = Color(0.9, 0.92, 0.94, 1)
@export var cannonball_impact_fire_color: Color = Color(0.55, 0.58, 0.62, 1)
@export_range(0.0, 2.0, 0.01) var cannonball_impact_bright_alpha_scale: float = 0.5
@export_range(0.0, 2.0, 0.01) var cannonball_impact_dark_alpha_scale: float = 0.1
@export_range(0.0, 1.0, 0.01) var cannonball_impact_smooth_step_edge: float = 0.71
@export_range(0.5, 2.0, 0.01) var cannonball_impact_bright_dissolve_scale: float = 1.95
@export_range(0.5, 2.0, 0.01) var cannonball_impact_dark_dissolve_scale: float = 0.8

# --- Enemy Destruction (ship blowing up) ---
@export_group("Enemy Destruction")
@export var enemy_destruction_lifetime: float = 1.2
@export var enemy_destruction_cone_spread: float = 360.0
@export var enemy_destruction_vert_velocity: float = 55.0
@export var enemy_destruction_vert_amount: int = 45
@export var enemy_destruction_horiz_amount: int = 30
@export var enemy_destruction_horiz_velocity_min: float = 5.5
@export var enemy_destruction_horiz_velocity_max: float = 11.0
@export var enemy_destruction_vert_damping: float = 23.0
@export var enemy_destruction_horiz_damping: float = 30.0
@export var enemy_destruction_particle_scale: float = 2.0
@export var enemy_destruction_turbulence_strength: float = 3.0
@export var enemy_destruction_turbulence_influence: float = 0.25
@export var enemy_destruction_dark_color: Color = Color(0.55, 0.52, 0.48, 1)
@export var enemy_destruction_fire_color: Color = Color(1, 0.5, 0.08, 1)
@export_range(0.0, 2.0, 0.01) var enemy_destruction_bright_alpha_scale: float = 1.0
@export_range(0.0, 2.0, 0.01) var enemy_destruction_dark_alpha_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var enemy_destruction_smooth_step_edge: float = 0.71
@export_range(0.5, 2.0, 0.01) var enemy_destruction_bright_dissolve_scale: float = 1.95
@export_range(0.5, 2.0, 0.01) var enemy_destruction_dark_dissolve_scale: float = 0.8

# --- Sea Mine (largest blast) ---
@export_group("Sea Mine")
@export var sea_mine_lifetime: float = 1.2
@export var sea_mine_cone_spread: float = 360.0
@export var sea_mine_vert_velocity: float = 80.0
@export var sea_mine_vert_amount: int = 60
@export var sea_mine_horiz_amount: int = 40
@export var sea_mine_horiz_velocity_min: float = 5.5
@export var sea_mine_horiz_velocity_max: float = 11.0
@export var sea_mine_vert_damping: float = 23.0
@export var sea_mine_horiz_damping: float = 30.0
@export var sea_mine_particle_scale: float = 2.0
@export var sea_mine_turbulence_strength: float = 3.0
@export var sea_mine_turbulence_influence: float = 0.25
@export var sea_mine_dark_color: Color = Color(0.55, 0.52, 0.48, 1)
@export var sea_mine_fire_color: Color = Color(1, 0.5, 0.08, 1)
@export_range(0.0, 2.0, 0.01) var sea_mine_bright_alpha_scale: float = 1.0
@export_range(0.0, 2.0, 0.01) var sea_mine_dark_alpha_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var sea_mine_smooth_step_edge: float = 0.71
@export_range(0.5, 2.0, 0.01) var sea_mine_bright_dissolve_scale: float = 1.95
@export_range(0.5, 2.0, 0.01) var sea_mine_dark_dissolve_scale: float = 0.8

# --- Global (shared by all types) ---
@export_group("Global")
@export var glow_enabled: bool = true
@export_range(0.0, 8.0, 0.1) var glow_intensity: float = 1.0
@export_range(0.0, 2.0, 0.05) var glow_strength: float = 0.6
@export_range(0.0, 1.0, 0.01) var glow_bloom: float = 0.3


## Returns a dict of params for the given type_name, ready to pass to
## ExplosionEffect.create(). Includes per-type params plus global glow.
func get_params(type_name: String) -> Dictionary:
	var params: Dictionary = {
		"glow_enabled": glow_enabled,
		"glow_intensity": glow_intensity,
		"glow_strength": glow_strength,
		"glow_bloom": glow_bloom,
	}
	for key: String in _TYPE_KEYS:
		params[key] = get("%s_%s" % [type_name, key])
	return params
