class_name EnemyArchetype
extends Resource

## Designer-tunable enemy ship template. Holds the per-archetype stats and
## visual identity that distinguish one enemy type from another. The plan's
## Phase 8 enemy decomposition splits enemy_ship.gd into a HealthComponent +
## HurtboxComponent + EnemyAIMovement set; this Resource is what the
## EnemyShip root reads at spawn time to configure them.
##
## Phase 8 Step 39 wired: hp, chase_speed, circle_speed, turn_speed,
## circle_radius, broadside_cooldown, broadside_range. Phase 11 Step 48c
## removed the four forward-declared fields (sprite_region, score, ai_kind,
## weapon) that never gained consumers — YAGNI cleanup. They can be
## re-added when a hull-variant system, scoring system, second AI strategy,
## or per-archetype weapon load lands.

@export var hp: int = 4
@export var chase_speed: float = 50.0
@export var circle_speed: float = 40.0
@export var turn_speed: float = 2.0
@export var circle_radius: float = 120.0
@export var broadside_cooldown: float = 2.0
@export var broadside_range: float = 130.0  # must be <= Cannonball.max_range
