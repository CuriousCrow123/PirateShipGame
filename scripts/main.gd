extends Node2D
## Scene root — wires the WaterTrail SubViewport texture, keeps the
## trail node tracking the ship's position, spawns cannonballs, and
## manages enemy ship spawning/despawning.

const CannonballScene: PackedScene = preload("res://scenes/cannonball.tscn")
const EnemyShipScene: PackedScene = preload("res://scenes/enemy_ship.tscn")

@export var max_enemies: int = 4
@export var spawn_interval: float = 8.0
@export var spawn_distance: float = 550.0
@export var despawn_distance: float = 1000.0

var _enemies: Array[EnemyShip] = []
var _spawn_timer: float = 2.0

@onready var _ship: CharacterBody2D = $Ship


func _ready() -> void:
	assert(_ship != null, "Main: Ship node is missing")
	$WaterTrail/TrailSprite.texture = $WaterTrail/SubViewport.get_texture()
	_ship.cannon_fired.connect(_on_cannon_fired)


func _process(_delta: float) -> void:
	# WaterTrail must follow ship position (not rotation) so trails.gd's
	# to_local() produces axis-aligned SubViewport coordinates.
	$WaterTrail.global_position = _ship.global_position


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
	add_child(ball)
	ball.setup(pos, dir)
	ExplosionEffect.create(self, pos, dir, 0, 0.25, 100, _ship.velocity * 0.75)


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
