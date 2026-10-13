shader_type canvas_item;
render_mode unshaded;

uniform float feather_pixels : hint_range(1.0, 200.0) = 90.0;

void fragment() {
	// Screen-space feather keeps the border equally soft on all four sides.
	vec2 uv_per_pixel = max(fwidth(UV), vec2(0.000001));
	vec2 distance_to_edge = min(UV, vec2(1.0) - UV) / uv_per_pixel;
	vec2 fade = smoothstep(vec2(0.0), vec2(feather_pixels), distance_to_edge);
	COLOR.a *= fade.x * fade.y;
}
