extends GutTest

## Unit suite for RunStats. Plan Phase 11 Step 45e.
##
## RunStats is a plain Resource accumulator — no Nodes, no tree, no autoload
## dependencies. Tests exercise the public API surface that WaveDirector,
## SpawnService, and GameOverScreen actually consume.
const RunStatsClass: GDScript = preload("res://systems/run_stats.gd")


func test_fresh_instance_zeros_all_counters() -> void:
	var rs: Object = RunStatsClass.new()
	assert_eq(rs.kills, 0)
	assert_eq(rs.deaths, 0)
	assert_eq(rs.damage_taken, 0)
	assert_eq(rs.waves_cleared, 0)
	assert_eq(rs.enemies_destroyed_by_mine, 0)
	assert_eq(rs.player_shots_fired, 0)
	assert_eq(rs.player_shots_hit, 0)
	assert_eq(rs.final_wave, 0)
	assert_eq(rs.time_elapsed, 0.0)
	assert_eq(rs.wave_times.size(), 0, "wave_times starts empty")


func test_register_enemy_destroyed_increments_kills() -> void:
	var rs: Object = RunStatsClass.new()
	rs.register_enemy_destroyed()
	rs.register_enemy_destroyed()
	rs.register_enemy_destroyed()
	assert_eq(rs.kills, 3)
	# by_mine defaults to false; mine counter stays zero.
	assert_eq(rs.enemies_destroyed_by_mine, 0)


func test_register_enemy_destroyed_by_mine_bumps_both_counters() -> void:
	var rs: Object = RunStatsClass.new()
	rs.register_enemy_destroyed(true)
	assert_eq(rs.kills, 1, "by-mine kill still counts as a kill")
	assert_eq(rs.enemies_destroyed_by_mine, 1)


func test_register_shot_fired_and_hit_counters() -> void:
	var rs: Object = RunStatsClass.new()
	for i: int in range(5):
		rs.register_shot_fired()
	rs.register_shot_hit()
	rs.register_shot_hit()
	assert_eq(rs.player_shots_fired, 5)
	assert_eq(rs.player_shots_hit, 2)


func test_hit_rate_zero_shots_returns_zero() -> void:
	var rs: Object = RunStatsClass.new()
	assert_eq(rs.hit_rate(), 0.0, "hit_rate must be 0.0 with no shots fired (no div-by-zero)")


func test_hit_rate_is_hits_over_shots() -> void:
	var rs: Object = RunStatsClass.new()
	for i: int in range(4):
		rs.register_shot_fired()
	rs.register_shot_hit()
	assert_almost_eq(rs.hit_rate(), 0.25, 0.001)


func test_start_and_end_wave_appends_wave_time() -> void:
	var rs: Object = RunStatsClass.new()
	rs.start_wave(1)
	assert_eq(rs.final_wave, 1, "start_wave updates final_wave")
	OS.delay_msec(20)
	rs.end_wave()
	assert_eq(rs.waves_cleared, 1)
	assert_eq(rs.wave_times.size(), 1, "end_wave appends a wave time")
	assert_gt(rs.wave_times[0], 0.0, "recorded wave time should be positive")


func test_multiple_waves_accumulate() -> void:
	var rs: Object = RunStatsClass.new()
	rs.start_wave(1)
	rs.end_wave()
	rs.start_wave(2)
	rs.end_wave()
	rs.start_wave(3)
	rs.end_wave()
	assert_eq(rs.waves_cleared, 3)
	assert_eq(rs.wave_times.size(), 3)
	assert_eq(rs.final_wave, 3, "final_wave tracks the latest started wave")
