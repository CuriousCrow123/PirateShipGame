extends Node2D
## Scene root — handles defensive ViewportTexture assignment for Godot 4.6
## compatibility (issue #115402: ViewportTexture can break after save/reload).


func _ready() -> void:
	var vt := ViewportTexture.new()
	vt.viewport_path = $WaterTrail/SubViewport.get_path()
	$WaterTrail/TrailSprite.texture = vt
