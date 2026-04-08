class_name MineDropComponent
extends Node

## Owns the mine drop cooldown and the drop entry point. Emits
## mine_dropped(pos) so the Ship root can forward to main.gd's spawn
## handler, and mine_cooldown_changed(progress) so MineCooldownDisplay
## can read progress without polling.
##
## Phase 4 Step 28: extracted from ship.gd's _drop_mine and the
## get_mine_cooldown_progress() helper.

signal mine_dropped(pos: Vector2)
signal mine_cooldown_changed(progress: float)

const STERN_OFFSET: float = 24.0

var _stats: ShipStats = null
var _ship: Node2D = null
var _cooldown: Cooldown = Cooldown.new()
var _last_progress: float = 1.0


func _ready() -> void:
	# We tick to publish progress for the HUD; the cooldown itself is
	# wall-clock and doesn't need ticking to be queried.
	set_physics_process(true)
	set_process(false)


func setup(ship: Node2D, stats: ShipStats) -> void:
	assert(ship != null, "MineDropComponent.setup: ship is null")
	assert(stats != null, "MineDropComponent.setup: stats is null")
	_ship = ship
	_stats = stats


func try_drop() -> bool:
	if not _cooldown.is_ready():
		return false
	# Drop behind the stern so the mine lands clear of the ship's hull and
	# reads as "kicked off the back". transform.y is the ship's forward axis
	# (see the wake ring offset in main.gd which uses the same convention).
	var drop_pos: Vector2 = _ship.global_position - _ship.transform.y * STERN_OFFSET
	mine_dropped.emit(drop_pos)
	_cooldown.start(_stats.mine_cooldown)
	return true


## 0.0 = just dropped (fully on cooldown), 1.0 = ready to drop again.
func get_cooldown_progress() -> float:
	return _cooldown.progress() if _cooldown.duration() > 0.0 else 1.0


func _physics_process(_delta: float) -> void:
	var p: float = get_cooldown_progress()
	if not is_equal_approx(p, _last_progress):
		_last_progress = p
		mine_cooldown_changed.emit(p)
