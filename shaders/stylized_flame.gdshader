shader_type spatial;
// Stylized flame ported from godotshaders.com/shader/stylized-flame/
// (free contribution, no license header in source).
//
// Single-mesh fresnel-banded flame: bands the dot(NORMAL, VIEW) result into
// 4 discrete colour layers, with noise displacement for motion. Apply to a
// 3D mesh (sphere or smooth shape) with the +Y axis pointing along the
// flame direction.
//
// Uniform names converted to PascalCase per project convention. Default
// values match the reference exactly (the comment-said "orange" Color1 is
// actually purple in the source — preserved as-is).
//
// Diverged from godotshaders.com reference: switched render_mode from
// blend_add to blend_mix and write per-band ALPHA so the flame is properly
// translucent (you can see what's behind the flame through it). The Opacity
// uniform multiplies the per-band alpha so the overall transparency is
// dialable from script / Inspector.
render_mode cull_disabled, blend_mix, unshaded, depth_draw_never, depth_test_disabled;

uniform float TimeSpeed = 1.0;
uniform float Spin = 0.0;
uniform float FlameBrightness = 0.6;
uniform float ColorIntensity = 0.0;
uniform float HorizontalFrequency = 1.0;
uniform float VerticalFrequency = 1.0;
uniform float Size = -0.3;
uniform float CoreSize = 1.0;
uniform float Opacity : hint_range(0.0, 1.0) = 0.7;
// Dissolve: 0 = full flame, 1 = fully gone. Driven by dash_fire_effect.gd over
// _DISSOLVE_DURATION after stop() so the burst dissipates instead of snapping
// off. Tail tip (UV.y near 0 in DashFlameLathe) erodes first because its
// per-pixel survival threshold is biased low.
uniform float Dissolve : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D NoiseTexture : hint_default_white, filter_linear, repeat_enable;
uniform vec4 Color1 : source_color = vec4(0.286, 0.22, 0.733, 1.0);
uniform vec4 Color2 : source_color = vec4(0.98, 0.38, 0.34, 1.0);
uniform vec4 Color3 : source_color = vec4(0.98, 0.95, 0.53, 1.0);
uniform vec4 Color4 : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	float time = TIME * TimeSpeed;

	float normal_facing = dot(NORMAL, VIEW);

	float noise_value = texture(
		NoiseTexture,
		vec2(
			UV.x * HorizontalFrequency + Spin * (time / 2.0),
			(UV.y * VerticalFrequency) + time
		)
	).r;
	normal_facing += (noise_value - 0.5 + Size) * 0.3;

	float band = normal_facing * 3.0 * CoreSize;
	vec4 flame_color = vec4(0.0);
	float band_alpha = 0.0;

	if (band <= 1.5) {
		band_alpha = 0.0;
	} else if (band <= 2.0) {
		flame_color = mix(Color1, Color2, -0.01 / (band - 2.01));
		// Outer dim band — fade in from invisible at band=1.5 to ~0.5 at band=2.0.
		band_alpha = (band - 1.5) * 1.0;
	} else if (band <= 2.5) {
		flame_color = mix(Color2, Color3, -0.01 / (band - 2.51));
		band_alpha = 0.65;
	} else if (band <= 2.9) {
		flame_color = mix(Color3, Color4, -0.01 / (band - 2.91));
		band_alpha = 0.85;
	} else if (band >= 0.0) {
		flame_color = Color4;
		band_alpha = 1.0;
	}

	ALBEDO = (
		FlameBrightness
		* (vec3(1.0) - (flame_color.xyz * -ColorIntensity))
		* flame_color.xyz
	);

	// Dissolve: clean alpha fade. Tail tip (UV.y near 0) loses opacity slightly
	// faster than the dome via a small UV.y bias on the fade ramp, but the
	// silhouette stays intact — just dissipates.
	float fade = 1.0 - smoothstep(UV.y * 0.35, UV.y * 0.35 + 0.65, Dissolve);
	ALPHA = clamp(band_alpha * Opacity * fade, 0.0, 1.0);
}
