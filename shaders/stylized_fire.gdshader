shader_type spatial;
// Stylized fire ported from GDQuest's stylized_fire.gdshader (BSD-licensed
// reference at https://github.com/gdquest-demos/godot-shaders).
// Adaptations for this project:
//   1. ColorRamp sampler2D replaces vertex COLOR.rgb so the fire colour can
//      be tuned via DashConfig.fire_color_ramp without per-particle setup.
//   2. DashStrength uniform (script-driven 0 -> 1 -> 0) replaces the
//      COLOR.a erosion term so the burst envelope is controlled by the
//      ship dash code, not particle lifetime — particles still spawn and
//      die, but they only become visible when the ship is mid-dash.
//   3. Instance lifetime (INSTANCE_CUSTOM.y) is multiplied INTO the
//      visibility so individual particles still fade out at end-of-life.
// Rendered into a 32x64 SubViewport for pixel-art crunch when displayed.
render_mode blend_mix;

uniform sampler2D NoiseTexture : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D MaskTexture : hint_default_white, filter_linear;
uniform sampler2D ColorRamp : hint_default_white, filter_linear;
uniform float EmissionIntensity : hint_range(0.0, 4.0) = 2.0;
uniform float TimeScale : hint_range(0.5, 8.0) = 3.0;
uniform vec2 TextureScale = vec2(1.0, 1.0);
uniform float EdgeSoftness : hint_range(0.0, 1.0) = 0.1;
// Script-driven envelope from the dash burst (0 = invisible, 1 = full).
uniform float DashStrength : hint_range(0.0, 1.0) = 0.0;

// TODO(post-mvp): wind direction uniform driving an additive UV offset.
// TODO(post-mvp): per-instance tint variation via INSTANCE_CUSTOM.zw.

varying vec3 world_coord;
varying float world_x_dot;
varying float instance_lifetime;

void vertex() {
	// Billboard the quad so it always faces the SubViewport's Camera3D.
	// Adapted from the GDQuest reference: build a world matrix that uses
	// the inverse view matrix's basis (camera-facing) but keeps the model
	// matrix's translation, then apply per-instance Z rotation from
	// INSTANCE_CUSTOM.x (set by ParticleProcessMaterial).
	mat4 mat_world = mat4(
			normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0]),
			normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[0]),
			normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2]),
			MODEL_MATRIX[3]);
	mat_world *= mat4(
			vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	world_coord = (mat_world * vec4(VERTEX, 1.0)).xyz;
	vec4 world_normal = (mat_world * vec4(NORMAL, 0.0));
	world_x_dot = abs(dot(normalize(world_normal.xyz), vec3(1.0, 0.0, 0.0)));
	// ParticleProcessMaterial sets INSTANCE_CUSTOM.y = normalized lifetime (0..1).
	instance_lifetime = INSTANCE_CUSTOM.y;
}

void fragment() {
	float mask = texture(MaskTexture, UV).r;

	// Sample noise from two world-space planes and blend by camera angle so
	// the flame reads consistently from all viewing angles. (Same trick as
	// the GDQuest reference.)
	vec2 time_pan = vec2(0.2, 1.0) * (-TIME * TimeScale);
	float noise_xy = texture(NoiseTexture, world_coord.xy * TextureScale + time_pan).r;
	float noise_zy = texture(NoiseTexture,
			world_coord.zy * TextureScale + time_pan + vec2(0.7, 0.3)).r;
	float noise = mix(noise_xy, noise_zy, clamp(world_x_dot, 0.0, 1.0));

	// Emission colour from the gradient ramp, sampled along V (bottom hot,
	// top cool). Multiplied by EmissionIntensity for HDR-ish brightness.
	vec3 ramp = texture(ColorRamp, vec2(1.0 - UV.y, 0.5)).rgb;
	ALBEDO = ramp;
	EMISSION = ramp * EmissionIntensity;

	// Erosion: noise * mask is the base; DashStrength rises the visibility
	// from invisible (-1) to fully realised (0); per-particle lifetime
	// fades the tail of each spawned quad. Both gates must be passed.
	float a = noise * mask;
	a += DashStrength - 1.0;
	a *= 1.0 - instance_lifetime;
	a = clamp(a, 0.0, 1.0);
	ALPHA = smoothstep(0.0, EdgeSoftness, a);
}
