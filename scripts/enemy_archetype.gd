class_name EnemyArchetype
extends Resource

## Designer-tunable enemy ship template. Holds the per-archetype stats and
## visual identity that distinguish one enemy type from another. The plan's
## Phase 8 enemy decomposition splits enemy_ship.gd into a HealthComponent +
## HurtboxComponent + EnemyAIMovement set; this Resource is what the
## EnemyShip root reads at spawn time to configure them.
##
## Phase 2 Step 13 read scope: enemy_ship.gd consumes `hp` and `chase_speed`
## via the `archetype` slot. The fields without consumers yet (`sprite_region`,
## `score`, `ai_kind`, `weapon`) are forward declarations \u2014 the components
## that will read them are scheduled for Phase 4 / Phase 8. Default values
## match the current pre-refactor enemy_ship.gd @export defaults so any
## archetype not yet authored falls back to identical behavior.

@export var hp: int = 4
@export var chase_speed: float = 50.0
@export var circle_speed: float = 40.0
@export var turn_speed: float = 2.0
@export var circle_radius: float = 120.0
@export var broadside_cooldown: float = 2.0
@export var broadside_range: float = 130.0  # must be <= Cannonball.max_range
@export var sprite_region: Rect2 = Rect2()  # Phase 4 read site
@export var score: int = 100  # Phase 4 read site
@export var ai_kind: StringName = &"chase_and_circle"  # YAGNI: only one AI exists
@export var weapon: WeaponConfig
