class_name DashConfig
extends Resource
## Runtime-editable dash parameters, saved as res://resources/dash_config.tres.
## Open the .tres in the Godot editor while the game runs — changes propagate to the
## running game (shared Resource cache) AND persist to disk on save.
## Changes apply to the NEXT dash; an in-flight burst keeps the values it started with.
##
## IMPORTANT: never .duplicate() the top-level DashConfig — that severs the hot-reload
## link. Sub-resources (Curve, GradientTexture1D, Texture2D) only need duplication if
## the script mutates them; we only sample, so no duplication needed.

enum FeelMode { LOCKED_HEADING, STEERABLE, VELOCITY_ALIGNED, OVERSPEED_CAP }

# --- Core Motion ---
@export_group("Core Motion")
@export var feel_mode: FeelMode = FeelMode.LOCKED_HEADING
@export_range(50.0, 800.0, 5.0) var impulse_speed: float = 280.0
@export_range(0.05, 1.5, 0.01) var duration: float = 0.35
@export_range(0.1, 5.0, 0.05) var cooldown: float = 1.2
## OVERSPEED_CAP only — replaces ship's per-frame linear_drag (default 0.97).
## Closer to 1.0 = less decay during the burst.
@export_range(0.9, 1.0, 0.001) var overspeed_drag: float = 0.995
## Sampled over normalized burst time (0..1). Drives the fire shader's DashStrength
## envelope. Null = constant 1.0 fallback.
@export var intensity_curve: Curve
## Celeste-style freeze frames at burst start (0 = off). Each frame is real-time 1/60s.
@export_range(0, 8, 1) var freeze_frames: int = 0
## Multiplier on the existing collision pushback during dash (0.0 = suppress, 1.0 = normal).
@export_range(0.0, 1.0, 0.05) var collision_pushback_scale: float = 0.0

# --- Fire Shader (Phase 2) ---
@export_group("Fire Shader")
@export var fire_texture_scale: Vector2 = Vector2(1.0, 1.0)
@export_range(0.5, 8.0, 0.1) var fire_time_scale: float = 3.0
@export_range(0.0, 1.0, 0.01) var fire_edge_softness: float = 0.1
@export_range(0.0, 4.0, 0.05) var fire_emission_intensity: float = 2.0
@export var fire_noise_texture: Texture2D
@export var fire_mask_texture: Texture2D
## Bind directly to the shader's ColorRamp sampler2D uniform.
@export var fire_color_ramp: GradientTexture1D
@export_range(0.0, 2.0, 0.01) var fire_quad_length_scale: float = 1.0

# --- Ghost Trail (Phase 3) ---
@export_group("Ghost Trail")
@export_range(0, 16, 1) var ghost_count: int = 6
@export_range(0.01, 0.2, 0.005) var ghost_spawn_interval: float = 0.04
@export_range(0.05, 1.5, 0.01) var ghost_fade_duration: float = 0.45
@export var ghost_start_tint: Color = Color(1.0, 0.85, 0.5, 0.7)
@export var ghost_end_tint: Color = Color(0.6, 0.2, 0.1, 0.0)
@export var ghost_additive: bool = true

# --- Camera Feedback (Phase 3) ---
@export_group("Camera Feedback")
## Peak px offset at trauma=1.0. Pixel-snapped via roundf.
@export_range(0.0, 8.0, 0.5) var shake_magnitude_px: float = 3.0
## Initial trauma added on dash start (0..1). Offset = trauma^2 * magnitude.
@export_range(0.0, 1.0, 0.01) var shake_trauma_initial: float = 0.6
## Linear decay rate of trauma per second.
@export_range(0.5, 4.0, 0.05) var shake_trauma_decay: float = 2.0
## Camera2D zoom target during punch (base zoom is 1.2). Set duration > 0 to enable.
@export_range(0.5, 1.5, 0.01) var zoom_punch_target: float = 1.1
@export_range(0.0, 0.5, 0.01) var zoom_punch_duration: float = 0.0
## Engine.time_scale value during dip (1.0 = no dip). Set duration > 0 to enable.
@export_range(0.1, 1.0, 0.01) var time_dip_value: float = 1.0
@export_range(0.0, 0.4, 0.01) var time_dip_duration: float = 0.0
