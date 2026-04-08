class_name WeaponConfig
extends Resource

## Designer-tunable weapon stats. Shared shape between cannon-fired
## cannonballs and sea mines, even though each consumes a different
## subset (mines never move, so `speed` and `lifetime` are zero for
## the mine .tres).
##
## Phase 2 Step 12: data layer only. The full read sites land in Phase 4
## when Cannon / SeaMine / Cannonball get their component-style rewrites.
## For now:
##   - sea_mine.gd reads `damage` and `explosion_kind`.
##   - cannon.gd holds the slot but does not read it yet (cannonball
##     spawn parameters still live on cannonball.gd; that migration is
##     scheduled for Phase 4 Step 26 alongside Cannon component
##     extraction).

@export var damage: int = 1
@export var speed: float = 0.0
@export var lifetime: float = 0.0
@export var explosion_kind: StringName = &""
@export var fire_sound: StringName = &""
