extends Node2D
## Scene root — wires the displacement SubViewport to the water shader,
## keeps the displacement viewport tracking the ship, spawns cannonballs,
## and manages enemy ship spawning/despawning.

const CannonballScene: PackedScene = preload("res://scenes/cannonball.tscn")
const EnemyShipScene: PackedScene = preload("res://scenes/enemy_ship.tscn")
const SeaMineScene: PackedScene = preload("res://scenes/sea_mine.tscn")

@export var max_enemies: int = 4
@export var spawn_interval: float = 8.0
@export var spawn_distance: float = 550.0
@export var despawn_distance: float = 1000.0

var _enemies: Array[EnemyShip] = []
var _mines: Array[SeaMine] = []
var _spawn_timer: float = 2.0
var _wake_distance: float = 0.0
var _last_wake_pos: Vector2 = Vector2.ZERO

@onready var _ship: CharacterBody2D = $Ship
@onready var _displacement_vp: SubViewport = $DisplacementViewport/SubViewport
@onready var _displacement_stamps: Node2D = $DisplacementViewport/SubViewport/Stamps


func _ready() -> void:
	assert(_ship != null, "Main: Ship node is missing")
	assert(_displacement_vp != null, "Main: DisplacementViewport/SubViewport not found")
	assert(_displacement_stamps != null, "Main: Stamps node not found")

	# Wire wake trail SubViewport texture to the TrailSprite display.
	$WaterTrail/TrailSprite.texture = $WaterTrail/SubViewport.get_texture()

	# Wire displacement SubViewport texture to the shared water material.
	# Intentionally shared: all water chunks use the same DisplacementMap.
	# NOT duplicated — uniform updates propagate to every chunk simultaneously.
	var water_mat: ShaderMaterial = $ChunkContainer.water_material as ShaderMaterial
	water_mat.set_shader_parameter("DisplacementMap", _displacement_vp.get_texture())
	water_mat.set_shader_parameter("WakeTrailMap", $WaterTrail/SubViewport.get_texture())

	_last_wake_pos = _ship.global_position
	_ship.cannon_fired.connect(_on_cannon_fired)
	_ship.mine_dropped.connect(_on_mine_dropped)


func _process(_delta: float) -> void:
	# WaterTrail follows ship so the Line2D trail renders correctly.
	$WaterTrail.global_position = _ship.global_position

	# Displacement viewport follows ship position so stamps stay centered.
	$DisplacementViewport.global_position = _ship.global_position

	# Update the water shader's displacement origin and speed-scaled wake strength.
	var water_mat: ShaderMaterial = $ChunkContainer.water_material as ShaderMaterial
	water_mat.set_shader_parameter("DisplacementOrigin", _ship.global_position)
	var speed_t: float = clampf(_ship.velocity.length() / 120.0, 0.0, 1.0)
	water_mat.set_shader_parameter("WakeTrailStrength", lerpf(2.0, 10.0, speed_t))

	# Wake expanding rings: spawn along the trail path at intervals
	_wake_distance += _ship.global_position.distance_to(_last_wake_pos)
	_last_wake_pos = _ship.global_position
	if _wake_distance >= 16.0 and _ship.velocity.length() > 5.0:
		_wake_distance = 0.0
		var wake_pos: Vector2 = _ship.global_position - _ship.transform.y * 12.0
		_displacement_stamps.spawn_wake_ring(wake_pos)

	# Mine idle bob displacement
	for mine: SeaMine in _mines:
		if mine._is_detonated:
			continue
		_displacement_stamps.spawn_bob(mine.global_position, mine.get_bob_phase())


func _physics_process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		_try_spawn_enemy()
	_despawn_distant_enemies()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_cannon_fired(pos: Vector2, dir: Vector2) -> void:
	var ball: Cannonball = CannonballScene.instantiate()
	ball.water_impacted.connect(_on_cannonball_water_impacted)
	add_child(ball)
	ball.setup(pos, dir)
	ExplosionEffect.create(self, pos, dir, 0, 0.25, 100, _ship.velocity * 0.75)


func _on_cannonball_water_impacted(impact_pos: Vector2) -> void:
	_displacement_stamps.spawn_impact(impact_pos, 64.0, 2.0)
	for mine: SeaMine in _mines.duplicate():
		mine.check_water_impact(impact_pos)


func _on_mine_dropped(pos: Vector2) -> void:
	var mine: SeaMine = SeaMineScene.instantiate()
	mine.destroyed.connect(_on_mine_destroyed)
	mine.tree_exiting.connect(_on_mine_tree_exiting.bind(mine))
	add_child(mine)
	mine.global_position = pos
	mine.reset_physics_interpolation()
	mine.setup()
	_mines.append(mine)


func _on_mine_destroyed(mine: SeaMine) -> void:
	_displacement_stamps.spawn_impact(mine.global_position, 128.0, 2.5)
	_mines.erase(mine)


func _on_mine_tree_exiting(mine: SeaMine) -> void:
	_mines.erase(mine)


func _try_spawn_enemy() -> void:
	if _enemies.size() >= max_enemies:
		return
	var angle: float = randf() * TAU
	var spawn_pos: Vector2 = _ship.global_position + Vector2.from_angle(angle) * spawn_distance
	var enemy: EnemyShip = EnemyShipScene.instantiate()
	enemy.rotation = randf() * TAU
	enemy.destroyed.connect(_on_enemy_destroyed)
	enemy.tree_exiting.connect(_on_enemy_tree_exiting.bind(enemy))
	add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.reset_physics_interpolation()
	enemy.setup(_ship)
	_enemies.append(enemy)


func _on_enemy_destroyed(enemy: EnemyShip) -> void:
	_enemies.erase(enemy)


func _on_enemy_tree_exiting(enemy: EnemyShip) -> void:
	_enemies.erase(enemy)


func _despawn_distant_enemies() -> void:
	for enemy: EnemyShip in _enemies.duplicate():
		if enemy._is_destroyed:
			continue
		if enemy.global_position.distance_to(_ship.global_position) > despawn_distance:
			_enemies.erase(enemy)
			enemy.queue_free()
