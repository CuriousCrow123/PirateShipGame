shader_type canvas_item;
// 2D port of the GDQuest stylized fire recipe
// (https://github.com/gdquest-demos/godot-shaders, BSD-licensed reference).
// Original is shader_type spatial with billboarding + world-space noise sampling;
// this rewrite preserves the visual recipe (noise * mask + alpha erosion +
// edge softening + emissive ramp) for a flat 2D quad. DashStrength is driven
// from script (0 -> 1 -> 0 envelope) to start/end the burst.
render_mode blend_mix;

uniform sampler2D NoiseTexture : hint_default_white, filter_linear, repeat_enable;
uniform sampler2D MaskTexture : hint_default_white, filter_linear;
uniform sampler2D ColorRamp : hint_default_white, filter_linear;
uniform vec2 TextureScale = vec2(1.0, 1.0);
uniform float TimeScale : hint_range(0.5, 8.0) = 3.0;
uniform float EdgeSoftness : hint_range(0.0, 1.0) = 0.1;
uniform float EmissionIntensity : hint_range(0.0, 4.0) = 2.0;
// Script-driven envelope: 0 = no fire, 1 = full burst.
uniform float DashStrength : hint_range(0.0, 1.0) = 0.0;

// TODO(post-mvp): wind direction uniform driving an additive UV offset.
// TODO(post-mvp): fuel pulse uniform for breathing/throbbing.

void fragment() {
	float mask = texture(MaskTexture, UV).r;
	vec2 pan = vec2(0.2, 1.0) * (-TIME * TimeScale);
	float n = texture(NoiseTexture, UV * TextureScale + pan).r;

	// Alpha erosion: noise * mask is the base shape; DashStrength erodes from
	// invisible (-1) up to fully realised (0) as the burst peaks. Same trick
	// the GDQuest spatial shader uses with vertex COLOR.a, but driven from
	// uniform here so the script controls the envelope via intensity_curve.
	float a = n * mask;
	a += DashStrength - 1.0;
	a = clamp(a, 0.0, 1.0);
	a = smoothstep(0.0, EdgeSoftness, a);

	// Sample the colour ramp along V (bottom = hot/yellow, top = cool/red).
	vec3 ramp = texture(ColorRamp, vec2(1.0 - UV.y, 0.5)).rgb;
	COLOR = vec4(ramp * EmissionIntensity, a);
}
