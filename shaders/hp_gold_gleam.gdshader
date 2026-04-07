// Shiny gold gleam overlay for the HP frame when the secret Invincible
// cheat is active. Rendered as a ColorRect overlay on top of the HP
// PanelContainer; outputs transparent everywhere except a moving gold
// highlight concentrated near the frame border.
shader_type canvas_item;

uniform float Intensity : hint_range(0.0, 1.0) = 0.0;
uniform float Speed = 1.1;
// Border width as a fraction of UV (0..1). Larger = thicker gold ring.
uniform float BorderWidth : hint_range(0.0, 0.5) = 0.14;
uniform vec4 GoldColor : source_color = vec4(1.0, 0.82, 0.22, 1.0);
uniform vec4 GoldHighlight : source_color = vec4(1.0, 0.98, 0.78, 1.0);

void fragment() {
	// Distance (in UV) from the nearest edge → border mask.
	float d = min(min(UV.x, UV.y), min(1.0 - UV.x, 1.0 - UV.y));
	float border = 1.0 - smoothstep(0.0, BorderWidth, d);

	// Diagonal sweeping band.
	float band = UV.x - UV.y;
	float gleam = 0.5 + 0.5 * sin((band * 3.0 - TIME * Speed) * 6.2831);
	gleam = pow(gleam, 3.0);

	vec3 gold_rgb = mix(GoldColor.rgb, GoldHighlight.rgb, gleam);
	// Small amount of gold fill inside the frame for a "lit up" feel.
	float inner_fill = (1.0 - border) * 0.08;
	float alpha = (border * (0.55 + 0.45 * gleam) + inner_fill) * Intensity;
	COLOR = vec4(gold_rgb, alpha);
}
