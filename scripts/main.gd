extends Node2D
## Scene root — wires the WaterTrail SubViewport texture, keeps the
## trail node tracking the ship's position, and spawns cannonballs.

const CannonballScene: PackedScene = preload("res://scenes/cannonball.tscn")


func _ready() -> void:
	$WaterTrail/TrailSprite.texture = $WaterTrail/SubViewport.get_texture()
	$Ship.cannon_fired.connect(_on_cannon_fired)


func _process(_delta: float) -> void:
	# WaterTrail must follow ship position (not rotation) so trails.gd's
	# to_local() produces axis-aligned SubViewport coordinates.
	$WaterTrail.global_position = $Ship.global_position


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
	ExplosionEffect.create(self, pos)
