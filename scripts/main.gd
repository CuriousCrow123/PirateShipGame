extends Node2D
## Scene root — handles defensive ViewportTexture assignment for Godot 4.6
## compatibility (issue #115402: ViewportTexture can break after save/reload).


func _ready() -> void:
	$WaterTrail/TrailSprite.texture = $WaterTrail/SubViewport.get_texture()


func _process(_delta: float) -> void:
	$WaterTrail.global_position = $Ship.global_position
