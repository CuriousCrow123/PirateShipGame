extends Node2D
## Scene root — wires the WaterTrail SubViewport texture and keeps the
## trail node tracking the ship's position each frame.


func _ready() -> void:
	$WaterTrail/TrailSprite.texture = $WaterTrail/SubViewport.get_texture()


func _process(_delta: float) -> void:
	# WaterTrail must follow ship position (not rotation) so trails.gd's
	# to_local() produces axis-aligned SubViewport coordinates.
	$WaterTrail.global_position = $Ship.global_position
