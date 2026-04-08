extends GutTest

## Unit suite for WaveConfig + WaveSet. Plan Phase 11 Step 45c.
##
## Validates the static contract of the wave data Resources — default
## field values, WaveSet.is_final_wave boundary behavior, and
## WaveSet.get_wave clamp-on-overflow (the defensive safety net that
## main.gd no longer exercises after Phase 3.5 shipped the Victory
## transition, but stays in place per the Phase 2 retro).
const WaveConfigClass: GDScript = preload("res://features/waves/wave_config.gd")
const WaveSetClass: GDScript = preload("res://features/waves/wave_set.gd")


func test_wave_config_default_fields() -> void:
	var wc: Object = WaveConfigClass.new()
	# Defaults match pre-refactor wave 1 tuning (parent plan wave_config.gd header).
	assert_eq(wc.enemies_to_spawn, 3)
	assert_eq(wc.max_concurrent, 3)
	assert_eq(wc.spawn_interval, 2.0)
	assert_eq(wc.speed_mult, 1.0)
	assert_eq(wc.cooldown_mult, 1.0)
	assert_eq(wc.intermission_duration, 4.0)


func test_wave_config_has_no_runtime_state_fields() -> void:
	# Doctrine check: runtime state (enemies_remaining, wave timer, etc.)
	# lives on WaveDirector Node vars, NOT on WaveConfig. See ADR 009.
	var wc: Object = WaveConfigClass.new()
	var props: Array = wc.get_property_list()
	var names: Array[String] = []
	for p: Dictionary in props:
		names.append(str(p.name))
	assert_does_not_have(
		names, "enemies_remaining", "WaveConfig must not carry runtime state — see ADR 009"
	)
	assert_does_not_have(
		names, "alive_count", "WaveConfig must not carry runtime state — see ADR 009"
	)


func test_wave_set_empty_returns_null() -> void:
	var ws: Object = WaveSetClass.new()
	var empty: Array[WaveConfig] = []
	ws.waves = empty
	assert_null(ws.get_wave(0), "empty WaveSet should return null")
	assert_null(ws.get_wave(5))


func test_wave_set_get_wave_in_range() -> void:
	var wc0: WaveConfig = WaveConfigClass.new()
	wc0.enemies_to_spawn = 10
	var wc1: WaveConfig = WaveConfigClass.new()
	wc1.enemies_to_spawn = 20
	var ws: Object = WaveSetClass.new()
	var arr: Array[WaveConfig] = [wc0, wc1]
	ws.waves = arr
	assert_eq(ws.get_wave(0).enemies_to_spawn, 10)
	assert_eq(ws.get_wave(1).enemies_to_spawn, 20)


func test_wave_set_get_wave_clamps_on_overflow() -> void:
	# Phase 2 retro: defensive clamp stays even after Phase 3.5's victory
	# transition means overflow is unreachable in gameplay. The clamp is
	# the safety net; this test documents the contract.
	var wc0: WaveConfig = WaveConfigClass.new()
	wc0.enemies_to_spawn = 1
	var wc_last: WaveConfig = WaveConfigClass.new()
	wc_last.enemies_to_spawn = 99
	var ws: Object = WaveSetClass.new()
	var arr: Array[WaveConfig] = [wc0, wc_last]
	ws.waves = arr
	# Past the end returns the final wave.
	assert_eq(ws.get_wave(2).enemies_to_spawn, 99, "overflow should clamp to last wave")
	assert_eq(ws.get_wave(100).enemies_to_spawn, 99, "far-overflow clamps to last wave")


func test_wave_set_get_wave_clamps_on_negative() -> void:
	var wc0: WaveConfig = WaveConfigClass.new()
	wc0.enemies_to_spawn = 3
	var ws: Object = WaveSetClass.new()
	var arr: Array[WaveConfig] = [wc0]
	ws.waves = arr
	assert_eq(ws.get_wave(-1).enemies_to_spawn, 3, "negative index clamps to wave 0")


func test_wave_set_is_final_wave_boundary() -> void:
	var ws: Object = WaveSetClass.new()
	var arr: Array[WaveConfig] = [
		WaveConfigClass.new(), WaveConfigClass.new(), WaveConfigClass.new()
	]
	ws.waves = arr
	# 0-indexed contract (parent plan line 1104-1110).
	assert_false(ws.is_final_wave(0), "wave 0 of 3 is not final")
	assert_false(ws.is_final_wave(1), "wave 1 of 3 is not final")
	assert_true(ws.is_final_wave(2), "wave 2 of 3 IS final (last index)")
	assert_true(ws.is_final_wave(3), "overflow is treated as final")


func test_wave_set_single_wave_is_always_final() -> void:
	var ws: Object = WaveSetClass.new()
	var arr: Array[WaveConfig] = [WaveConfigClass.new()]
	ws.waves = arr
	assert_true(ws.is_final_wave(0), "a single-entry set's only wave is the final one")
