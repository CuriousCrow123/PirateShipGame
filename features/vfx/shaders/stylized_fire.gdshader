shader_type spatial;
// Stylized fire ported from the GDQuest reference at
// https://godotshaders.com/shader/stylized-fire-3d/ (BSD-licensed).
// Adapted to Godot 4: CAMERA_MATRIX -> INV_VIEW_MATRIX,
// INV_CAMERA_MATRIX -> VIEW_MATRIX, WORLD_MATRIX -> MODEL_MATRIX.
// All colour and alpha-erosion control flows from per-particle vertex
// COLOR (set by ParticleProcessMaterial.color_ramp), exactly like the
// reference — DO NOT replace this with a script-driven uniform, the
// per-particle lifetime fade depends on it.
//
// To toggle the burst on/off from script, set GPUParticles3D.emitting,
// not a shader uniform. The dash code does this in DashFireEffect.start/stop.
render_mode blend_mix;

uniform sampler2D NoiseTexture : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D MaskTexture : hint_default_white, filter_linear;
uniform float EmissionIntensity : hint_range(0.0, 4.0) = 2.0;
uniform float TimeScale : hint_range(0.5, 8.0) = 3.0;
uniform vec2 TextureScale = vec2(1.0, 1.0);
uniform float EdgeSoftness : hint_range(0.0, 1.0) = 0.1;

varying vec3 world_coord;
varying float world_x_dot;

void vertex() {
	mat4 mat_world = mat4(
			normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0]),
			normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[0]),
			normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2]),
			MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(
			vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;

	world_coord = (mat_world * vec4(VERTEX, 1.0)).xyz;
	vec4 world_normal = (mat_world * vec4(NORMAL, 0.0));
	world_x_dot = abs(dot(normalize(world_normal.xyz), vec3(1.0, 0.0, 0.0)));
}

void fragment() {
	float mask = texture(MaskTexture, UV).r;

	vec2 time_based_pan = vec2(0.2, 1.0) * (-TIME * TimeScale);
	float noise_xy = texture(NoiseTexture, world_coord.xy * TextureScale + time_based_pan).r;
	float noise_zy = texture(
		NoiseTexture, world_coord.zy * TextureScale + time_based_pan + vec2(0.7, 0.3)
	).r;

	float noise = mix(noise_xy, noise_zy, clamp(world_x_dot, 0.0, 1.0));

	ALBEDO = COLOR.rgb;
	EMISSION = ALBEDO * EmissionIntensity;

	float erosion_amount = 1.0 - COLOR.a;
	float alpha = (noise * mask) - erosion_amount;
	alpha = clamp(alpha, 0.0, 1.0);
	ALPHA = smoothstep(0.0, EdgeSoftness, alpha);
}
