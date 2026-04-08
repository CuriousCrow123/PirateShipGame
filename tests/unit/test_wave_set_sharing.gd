# gdlint: disable = duplicated-load
extends GutTest

## Executable doctrine test for ADR 009 §8: Resources are shared-by-reference
## across loaders for the same path. Two WaveSets pointing at the same
## wave_03.tres get the SAME in-memory WaveConfig instance — so WaveDirector
## must NOT mutate fields on the loaded WaveConfig, or two concurrent
## directors would stomp each other's state. Runtime state lives in Node
## vars instead.
##
## This test documents the contract executably: any future change that
## causes WaveConfig to grow a runtime-state field will cause this test
## to fail, because Godot's Resource cache would propagate the mutation
## across loaders.
##
## `duplicated-load` is disabled at the file level because the test is
## specifically exercising the Resource cache's load-same-path-twice
## behavior. Every load() call on this path is intentional.


func test_same_path_yields_same_instance() -> void:
	var a: Resource = load("res://features/waves/configs/wave_03.tres")
	var b: Resource = load("res://features/waves/configs/wave_03.tres")
	assert_not_null(a, "wave_03.tres must exist at the canonical path")
	assert_not_null(b)
	# Identity check: Godot caches Resources by path. The same load() call
	# returns the same in-memory instance the second time.
	assert_same(a, b, "Resource loader must return the same instance for the same .tres path")


func test_same_path_from_different_waveset_shares_instance() -> void:
	# Build two WaveSets that both reference wave_03.tres — identity must
	# still hold. This is the doctrine's load-bearing assertion: if a future
	# refactor accidentally .duplicate()s on WaveSet load, this test fails
	# AND the "mutable WaveConfig stomping" bug resurfaces.
	const WaveSetClass: GDScript = preload("res://features/waves/wave_set.gd")
	var wave_03: WaveConfig = load("res://features/waves/configs/wave_03.tres") as WaveConfig
	var ws_a: Object = WaveSetClass.new()
	var arr_a: Array[WaveConfig] = [wave_03]
	ws_a.waves = arr_a
	var ws_b: Object = WaveSetClass.new()
	var arr_b: Array[WaveConfig] = [load("res://features/waves/configs/wave_03.tres") as WaveConfig]
	ws_b.waves = arr_b
	assert_same(
		ws_a.get_wave(0),
		ws_b.get_wave(0),
		"WaveSets referencing the same .tres must share the WaveConfig instance"
	)


func test_wave_config_has_no_mutable_runtime_fields() -> void:
	# Belt-and-suspenders: walk the property list and confirm no field names
	# that smell like runtime state. Mirrors the check in test_wave_config.gd
	# but focused on the identity-shared scenario this file exercises.
	var wc: Resource = load("res://features/waves/configs/wave_03.tres")
	assert_not_null(wc)
	var props: Array = wc.get_property_list()
	var banned: Array[String] = [
		"enemies_remaining",
		"alive_count",
		"spawned_count",
		"wave_timer",
		"_current_spawn_index",
	]
	var names: Array[String] = []
	for p: Dictionary in props:
		names.append(str(p.name))
	for b: String in banned:
		assert_does_not_have(
			names, b, "WaveConfig must not expose runtime-state field '%s' (see ADR 009)" % b
		)
