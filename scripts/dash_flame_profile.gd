class_name DashFlameProfile
extends Resource
## Cubic-Bezier profile for the procedural dash-flame lathe (DashFlameLathe).
##
## Lives at res://resources/dash_flame_profile.tres so the test scene
## (scripts/stylized_flame_test.gd) and the in-game effect
## (scripts/dash_fire_effect.gd) tune the same instance via the shared resource
## cache. Live tweaks in the test scene save to disk via ResourceSaver and the
## next game run picks them up.

@export_range(0.1, 2.5, 0.05) var bulge_radius: float = 1.0
@export_range(0.1, 4.0, 0.05) var tail_length: float = 1.6
@export_range(0.1, 2.5, 0.05) var dome_radius: float = 0.85
