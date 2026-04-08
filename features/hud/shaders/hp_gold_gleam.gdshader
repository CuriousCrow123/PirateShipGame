// Shiny gold gleam overlay for the HP frame when the secret Invincible
// cheat is active. Rendered as a ColorRect sized to match the HP
// PanelContainer's rect exactly. Uses a signed-distance function for a
// rounded rectangle so the gleam respects the stylebox's rounded corners
// and never extends past the visible frame boundary.
shader_type canvas_item;

uniform float Intensity : hint_range(0.0, 1.0) = 0.0;
uniform float Speed = 1.1;
// Size of the overlay rect in pixels — driven from hp_display.gd so the
// SDF runs in true pixel space regardless of frame size.
uniform vec2 RectSize = vec2(100.0, 40.0);
// Must match the stylebox corner_radius used by the HP frame.
uniform float CornerRadius = 4.0;
// How many pixels inward from the edge the gleam ring extends.
uniform float BorderPixels = 6.0;
uniform vec4 GoldColor : source_color = vec4(1.0, 0.82, 0.22, 1.0);
uniform vec4 GoldHighlight : source_color = vec4(1.0, 0.98, 0.78, 1.0);


// Signed distance to an axis-aligned rounded rect centered at origin.
// Negative inside, 0 on the edge, positive outside.
float sdf_rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}


void fragment() {
	vec2 half_size = RectSize * 0.5;
	vec2 p = (UV - 0.5) * RectSize;
	float d = sdf_rounded_box(p, half_size, CornerRadius);

	// Outside the rounded rect → fully transparent (no corner spill).
	if (d > 0.0) {
		COLOR = vec4(0.0);
	} else {
		// Near the edge (d close to 0) → strong gleam.
		// Deep inside (d < -BorderPixels) → faint inner fill.
		float border = 1.0 - smoothstep(0.0, BorderPixels, -d);

		// Diagonal sweeping band (in UV so it feels continuous).
		float band = UV.x - UV.y;
		float gleam = 0.5 + 0.5 * sin((band * 3.0 - TIME * Speed) * 6.2831);
		gleam = pow(gleam, 3.0);

		vec3 gold_rgb = mix(GoldColor.rgb, GoldHighlight.rgb, gleam);
		float inner_fill = (1.0 - border) * 0.08;
		float alpha = (border * (0.55 + 0.45 * gleam) + inner_fill) * Intensity;
		COLOR = vec4(gold_rgb, alpha);
	}
}
