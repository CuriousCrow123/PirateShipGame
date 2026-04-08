class_name Cooldown
extends RefCounted

## Timestamp-based cooldown timer. Zero per-frame cost: no tick() callback,
## no _process subscription. Owners just call start() and is_ready().
##
## Wall-clock based (Time.get_ticks_msec()), so this is INDEPENDENT of
## Engine.time_scale. That makes it the wrong tool for freeze-frame /
## time-dip effects \u2014 those need a scaled timer; DashComponent has its
## own unscaled+wall-clock pair (see plan Phase 6 Step 34b/34c).
##
## Paused-scene caveat: Time.get_ticks_msec() continues across
## get_tree().paused = true, so cooldowns visibly drain during a paused
## game-over screen unless the owner snapshots remaining() on pause and
## restarts on unpause. Most gameplay cooldowns don't care because nothing
## fires during a paused game.
##
## Replaces 10 get_tree().create_timer() lambda sites (see plan section
## "Cooldown helper" + Phase 6 Step 34a\u2013j).

var _ready_at_msec: int = 0
var _duration_msec: int = 0


func start(duration: float) -> void:
	_duration_msec = int(duration * 1000.0)
	_ready_at_msec = Time.get_ticks_msec() + _duration_msec


func is_ready() -> bool:
	return Time.get_ticks_msec() >= _ready_at_msec


func is_active() -> bool:
	return Time.get_ticks_msec() < _ready_at_msec


func remaining() -> float:
	return maxf(0.0, float(_ready_at_msec - Time.get_ticks_msec()) / 1000.0)


func duration() -> float:
	return float(_duration_msec) / 1000.0


func progress() -> float:
	if _duration_msec <= 0:
		return 1.0
	var left: int = maxi(0, _ready_at_msec - Time.get_ticks_msec())
	return 1.0 - float(left) / float(_duration_msec)


func reset() -> void:
	_ready_at_msec = 0
	_duration_msec = 0
