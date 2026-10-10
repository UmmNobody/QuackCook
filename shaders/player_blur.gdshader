shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float radius : hint_range(0.0, 12.0) = 6.0;

void fragment() {
	vec2 offset = SCREEN_PIXEL_SIZE * radius * 0.25;
	vec3 color = vec3(0.0);
	float total_weight = 0.0;
	// A portable Gaussian kernel, including Compatibility renderer (no mipmaps needed).
	for (int x = -4; x <= 4; x++) {
		for (int y = -4; y <= 4; y++) {
			float weight = exp(-float(x * x + y * y) / 8.0);
			color += texture(screen_texture, SCREEN_UV + vec2(float(x), float(y)) * offset).rgb * weight;
			total_weight += weight;
		}
	}
	COLOR = vec4(color / total_weight * 0.8, 1.0);
}
