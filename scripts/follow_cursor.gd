extends Node2D
## Drives this node's position to follow the mouse cursor each frame.
## Uses _process (not _physics_process) — this is a visual-only system.
## Uses global_position — works correctly regardless of parent transform.


func _process(_delta: float) -> void:
	global_position = get_global_mouse_position()
