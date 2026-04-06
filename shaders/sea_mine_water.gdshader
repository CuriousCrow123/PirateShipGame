shader_type canvas_item;
render_mode blend_premul_alpha;

// Radial water line for top-down view: center = above water, edges = submerged
uniform float WaterRadius : hint_range(0.0, 0.5) = 0.12;
uniform float BobOffset : hint_range(-0.15, 0.15) = 0.0;
uniform float WaveAmplitude : hint_range(0.0, 0.05) = 0.02;
uniform float WaveFrequency : hint_range(0.0, 20.0) = 5.0;
uniform float WaveSpeed : hint_range(0.0, 5.0) = 1.5;
uniform float SubmergedMineOpacity : hint_range(0.0, 1.0) = 0.35;
uniform float FoamWidth : hint_range(0.0, 0.08) = 0.04;
uniform vec4 FoamColor : source_color = vec4(0.9, 0.95, 1.0, 0.7);
uniform float GlowIntensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 GlowColor : source_color = vec4(1.0, 0.15, 0.05, 1.0);

// Sample the water surface behind the mine
uniform sampler2D ScreenTexture : hint_screen_texture, filter_nearest;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec4 water = texture(ScreenTexture, SCREEN_UV);

	// Distance from center in UV space
	vec2 centered = UV - 0.5;
	float dist = length(centered);

	// Wavy radial water line
	float angle = atan(centered.y, centered.x);
	float wave = sin(angle * WaveFrequency + TIME * WaveSpeed) * WaveAmplitude;
	float effective_radius = WaterRadius + BobOffset + wave;

	// Only apply effects where the mine is actually rendered
	float mask = tex.a;

	// Apply red glow to the mine color BEFORE water blending
	// so the submerged glow still shows water through it
	vec3 mine_rgb = mix(tex.rgb, GlowColor.rgb, GlowIntensity);

	// Submersion blend: outside water radius, show water with glowing mine underneath
	float submerged = smoothstep(effective_radius - 0.03, effective_radius + 0.03, dist);
	vec3 underwater_mine = mix(water.rgb, mine_rgb, SubmergedMineOpacity);
	vec3 tinted = mix(mine_rgb, underwater_mine, submerged);

	// Foam ring at the water line
	float foam_dist = abs(dist - effective_radius);
	float foam = smoothstep(FoamWidth, 0.0, foam_dist) * mask;
	tinted = mix(tinted, FoamColor.rgb, foam * FoamColor.a);

	COLOR.rgb = tinted * mask;
	COLOR.a = mask;
}
