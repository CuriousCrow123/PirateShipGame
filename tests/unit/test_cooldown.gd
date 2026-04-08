extends GutTest

## Unit suite for Cooldown helper. Plan Phase 1 Step 9.
##
## Loads via preload() rather than the `Cooldown` class_name because the
## headless GUT runner's parse pass doesn't always pick up the global
## class index in time.
const CooldownClass: GDScript = preload("res://systems/cooldown.gd")
##
## Cooldown is wall-clock based, so the temporal assertions use real
## OS.delay_msec() rather than fake-tick. The waits are kept short (<300ms
## total) so the suite stays cheap to run after every commit.


func test_starts_inactive() -> void:
	var cd: Object = CooldownClass.new()
	assert_true(cd.is_ready(), "fresh Cooldown should be ready")
	assert_false(cd.is_active(), "fresh Cooldown should not be active")
	assert_eq(cd.duration(), 0.0, "fresh Cooldown duration should be 0")
	assert_eq(cd.remaining(), 0.0, "fresh Cooldown remaining should be 0")


func test_start_marks_active() -> void:
	var cd: Object = CooldownClass.new()
	cd.start(0.2)
	assert_false(cd.is_ready(), "Cooldown should be active immediately after start")
	assert_true(cd.is_active(), "is_active() should be true while running")
	assert_almost_eq(cd.duration(), 0.2, 0.001)
	# remaining() is positive but bounded by duration.
	assert_gt(cd.remaining(), 0.0)
	assert_lte(cd.remaining(), 0.2)


func test_progress_monotonic_increases_to_one() -> void:
	var cd: Object = CooldownClass.new()
	cd.start(0.1)
	var p0: float = cd.progress()
	OS.delay_msec(50)
	var p1: float = cd.progress()
	OS.delay_msec(80)  # well past expiry
	var p2: float = cd.progress()
	assert_gte(p1, p0, "progress should be monotonic non-decreasing")
	assert_gte(p2, p1, "progress should be monotonic non-decreasing")
	assert_lte(p2, 1.0, "progress must be clamped to <=1.0")
	# After expiry, progress() reaches 1.0 (left == 0).
	assert_almost_eq(p2, 1.0, 0.001)


func test_is_ready_after_duration_elapses() -> void:
	var cd: Object = CooldownClass.new()
	cd.start(0.05)
	OS.delay_msec(80)  # extra slack so flaky CI clocks still pass
	assert_true(cd.is_ready(), "Cooldown should be ready after duration elapses")
	assert_false(cd.is_active())
	assert_eq(cd.remaining(), 0.0, "remaining should clamp to 0 after expiry")


func test_reset_restores_initial_state() -> void:
	var cd: Object = CooldownClass.new()
	cd.start(5.0)
	assert_true(cd.is_active())
	cd.reset()
	assert_true(cd.is_ready(), "reset() should make Cooldown ready immediately")
	assert_false(cd.is_active())
	assert_eq(cd.duration(), 0.0)
	assert_eq(cd.remaining(), 0.0)


func test_zero_duration_is_immediately_ready() -> void:
	var cd: Object = CooldownClass.new()
	cd.start(0.0)
	assert_true(cd.is_ready(), "zero-duration cooldown should already be ready")
	assert_eq(cd.progress(), 1.0, "zero-duration progress() should short-circuit to 1.0")


func test_restart_extends_window() -> void:
	var cd: Object = CooldownClass.new()
	cd.start(0.05)
	OS.delay_msec(60)
	assert_true(cd.is_ready(), "first window should expire")
	cd.start(0.2)
	assert_false(cd.is_ready(), "restart should re-arm")
	assert_almost_eq(cd.duration(), 0.2, 0.001)
