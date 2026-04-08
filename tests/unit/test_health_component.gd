extends GutTest

## Unit suite for HealthComponent. Plan Phase 11 Step 45a.
##
## HealthComponent is a damage store + respawn cooldown; ShipFSM owns iframes
## and the DEAD state transition. Tests wire a real ShipFSM (not a double)
## because (a) the surface is small and (b) FSM bugs that break the gate
## should fail loudly here rather than silently pass through a mock.
const HealthComponentClass: GDScript = preload("res://features/ship/components/health_component.gd")
const ShipFSMClass: GDScript = preload("res://features/ship/ship_fsm.gd")


func _build_pair(max_hp: int = 4, max_lives: int = 2, respawn_delay: float = 0.05) -> Dictionary:
	# Return a dict so both refs are addressable from the test. The nodes are
	# parented under the test's auto-free owner so _ready() fires and any
	# transient _process channels can tick naturally during the test.
	var fsm: Node = ShipFSMClass.new()
	var health: Node = HealthComponentClass.new()
	add_child_autofree(fsm)
	add_child_autofree(health)
	health.setup(max_hp, max_lives, respawn_delay, fsm)
	# Let the deferred initial-status emit flush.
	await get_tree().process_frame
	return {"fsm": fsm, "health": health}


func test_setup_emits_initial_status() -> void:
	var fsm: Node = ShipFSMClass.new()
	var health: Node = HealthComponentClass.new()
	add_child_autofree(fsm)
	add_child_autofree(health)
	watch_signals(health)
	health.setup(4, 2, 0.05, fsm)
	await get_tree().process_frame
	assert_signal_emitted(health, "health_changed")
	assert_signal_emitted(health, "lives_changed")
	assert_eq(health.get_hp(), 4)
	assert_eq(health.get_lives(), 2)


func test_apply_damage_decrements_hp_and_emits_health_changed() -> void:
	var pair: Dictionary = await _build_pair()
	var health: Node = pair.health
	watch_signals(health)
	var landed: bool = health.apply_damage()
	assert_true(landed, "damage to a vulnerable ship should land")
	assert_eq(health.get_hp(), 3, "HP should decrement by 1 per hit (current contract)")
	assert_signal_emitted(health, "health_changed")


func test_apply_damage_while_invulnerable_noops() -> void:
	var pair: Dictionary = await _build_pair()
	var fsm: Node = pair.fsm
	var health: Node = pair.health
	# Force iframes. FSM's start_iframes also flips the FSM state to IFRAME.
	fsm.start_iframes(10.0)
	assert_false(fsm.is_vulnerable(), "sanity: iframes should make the ship invulnerable")
	var landed: bool = health.apply_damage()
	assert_false(landed, "damage should not land while iframes are active")
	assert_eq(health.get_hp(), 4, "HP must not drop on a gated hit")


func test_lethal_damage_emits_died_and_decrements_lives() -> void:
	var pair: Dictionary = await _build_pair(1, 2)
	var fsm: Node = pair.fsm
	var health: Node = pair.health
	watch_signals(health)
	health.apply_damage()
	assert_eq(health.get_hp(), 0)
	assert_eq(health.get_lives(), 1, "lives should decrement on lethal hit")
	assert_signal_emitted(health, "died")
	assert_signal_emitted(health, "lives_changed")
	assert_true(fsm.is_dead(), "FSM should be in DEAD state after lethal hit")


func test_lethal_damage_out_of_lives_emits_game_over() -> void:
	var pair: Dictionary = await _build_pair(1, 1)
	var health: Node = pair.health
	watch_signals(health)
	health.apply_damage()
	assert_signal_emitted(health, "died")
	assert_signal_emitted(
		health, "game_over", "last-life death must emit game_over (respawnable=true path)"
	)


func test_non_respawnable_skips_game_over() -> void:
	# Enemy configuration: single life, non-respawnable. Lethal damage must
	# emit died WITHOUT tripping the player game_over path (Phase 8 contract).
	var fsm: Node = ShipFSMClass.new()
	var health: Node = HealthComponentClass.new()
	health.respawnable = false
	add_child_autofree(fsm)
	add_child_autofree(health)
	health.setup(1, 1, 0.0, fsm)
	await get_tree().process_frame
	watch_signals(health)
	health.apply_damage()
	assert_signal_emitted(health, "died")
	assert_signal_not_emitted(
		health, "game_over", "non-respawnable entities must NOT emit game_over"
	)


func test_non_lethal_damage_starts_iframes_via_fsm() -> void:
	var pair: Dictionary = await _build_pair()
	var fsm: Node = pair.fsm
	var health: Node = pair.health
	assert_true(fsm.is_vulnerable(), "sanity: fresh ship is vulnerable")
	health.apply_damage()
	assert_true(fsm.has_iframes(), "non-lethal hit should start iframes via fsm.start_iframes")


func test_hit_iframes_disabled_skips_iframe_grant() -> void:
	# Enemy configuration: hit_iframes_enabled=false so rapid cannonball
	# follow-ups and ram collisions land cleanly without a grace window.
	var fsm: Node = ShipFSMClass.new()
	var health: Node = HealthComponentClass.new()
	health.hit_iframes_enabled = false
	add_child_autofree(fsm)
	add_child_autofree(health)
	health.setup(4, 1, 0.0, fsm)
	await get_tree().process_frame
	assert_true(fsm.is_vulnerable(), "sanity: fresh HP>1 entity is vulnerable")
	health.apply_damage()
	assert_eq(health.get_hp(), 3, "hit landed, HP decremented")
	assert_false(
		fsm.has_iframes(),
		"hit_iframes_enabled=false must skip fsm.start_iframes on non-lethal damage"
	)
	# And a second hit in the same frame still lands because no grace window.
	health.apply_damage()
	assert_eq(health.get_hp(), 2, "second hit lands without iframe gating")


func test_respawn_ready_fires_after_cooldown() -> void:
	# Short respawn delay so the test is quick. The transient _process
	# channel polls the wall-clock Cooldown and emits respawn_ready.
	var pair: Dictionary = await _build_pair(1, 2, 0.05)
	var health: Node = pair.health
	watch_signals(health)
	health.apply_damage()
	# Wait longer than the respawn delay.
	await get_tree().create_timer(0.15).timeout
	assert_signal_emitted(
		health, "respawn_ready", "respawn_ready should emit after the respawn cooldown elapses"
	)


func test_reset_for_respawn_refills_hp_and_returns_via_fsm() -> void:
	# Use 1 HP so a single hit kills — otherwise post-hit iframes would gate
	# the subsequent apply_damage calls needed to reach HP 0.
	var pair: Dictionary = await _build_pair(1, 2, 0.05)
	var fsm: Node = pair.fsm
	var health: Node = pair.health
	health.apply_damage()
	assert_true(fsm.is_dead(), "sanity: 1-HP ship should be dead after one hit")
	watch_signals(health)
	health.reset_for_respawn()
	assert_eq(health.get_hp(), 1, "HP should refill on reset_for_respawn")
	assert_false(fsm.is_dead(), "FSM should leave DEAD after respawn")
	assert_true(fsm.has_iframes(), "respawn should grant iframes")
	assert_signal_emitted(health, "health_changed")
