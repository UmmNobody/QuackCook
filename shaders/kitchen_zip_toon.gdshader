shader_type spatial;
render_mode cull_disabled;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform bool use_texture = false;
uniform bool use_vertex_color = false;
uniform bool vertex_is_srgb = false;
uniform bool floor_tiles = false;
uniform sampler2D floor_pattern : repeat_enable, filter_linear_mipmap;
uniform vec4 tile_color : source_color = vec4(0.68, 0.72, 0.70, 1.0);
uniform vec4 grout_color : source_color = vec4(0.62, 0.66, 0.64, 1.0);
uniform float tile_size = 0.85;
varying vec3 world_position;
varying vec3 world_normal;


group_uniforms Shader.Albedo;
uniform vec4 albedo_color : source_color  = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float albedo_affect : hint_range(0.0, 1.0, 0.05) = 0.0;

group_uniforms Shader.Light;
uniform bool use_stepped = true;
uniform float steps = 3.0;
uniform float step_smoothness : hint_range(0.0, 1.0, 0.05) = 0.3;
uniform vec4 shadow_tint : source_color;
uniform float shadow_tint_amount : hint_range(0.0, 1.0, 0.1) = 0.4;

group_uniforms Shader.Specular;
uniform float specular : hint_range(0.0, 1.0, 0.05) = 0.0;

group_uniforms Shader.Normal;
uniform float normal_strength : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform sampler2D normal_texture : hint_normal;

group_uniforms Shader.Rim;
uniform bool use_rim = true;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_amount = 2.0;
uniform float rim_smoothness = 0.2;
uniform float rim_mask_shadow : hint_range(0.0, 1.0, 0.05) = 1.0;
uniform float rim_blend : hint_range(0.0, 1.0, 0.05) = 1.0;

group_uniforms Shader.Pattern;
uniform bool use_pattern = true;
uniform sampler2D pattern_texture;
uniform int pattern_uv_mode : hint_enum("UV", "Screen", "Local Screen") = 2;
uniform float pattern_tiling = 32.0;
uniform float pattern_amount : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform float pattern_smoothness : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform float pattern_blend : hint_range(0.0, 1.0, 0.05) = 0.2;

varying vec4 node_position;

float fresnel(float amount, vec3 normal, vec3 view)
{
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0 )), amount);
}

vec2 pattern_uv(vec2 uv, vec2 screen_uv){
	vec2 p_uv = uv;
	if(pattern_uv_mode == 1) { p_uv = screen_uv; }
	if(pattern_uv_mode == 2) { p_uv = (screen_uv * 2.0 - 1.0) * node_position.w - node_position.xy; }
	return p_uv;
}

float shape_value(float value, vec2 uv, vec2 screen_size){
	float aspect = screen_size.y / screen_size.x;
	vec2 pattern_uv = uv * pattern_tiling * vec2(1.0, aspect);
	float shadow_pattern = texture(pattern_texture, pattern_uv).r;
	shadow_pattern = clamp(smoothstep(shadow_pattern - pattern_smoothness, shadow_pattern + pattern_smoothness, value + pattern_amount), 0.0, value + pattern_amount);
	return shadow_pattern;
}

void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	 node_position = (PROJECTION_MATRIX * vec4(NODE_POSITION_VIEW, 1.0));
}

void fragment() {
    vec2 uv = UV * uv_scale.xy + uv_offset.xy;
    vec3 color = albedo_color.rgb;
    if (use_texture) { color *= texture(albedo_texture, uv).rgb; }
    if (use_vertex_color) {
        vec3 vc = COLOR.rgb;
        if (vertex_is_srgb && !OUTPUT_IS_SRGB) {
            vc = mix(vc / 12.92, pow((vc + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), vc));
        }
        color *= vc;
    }
    if (floor_tiles) {
        float grout = texture(floor_pattern, world_position.xz / (tile_size * 2.0)).r;
        color = mix(tile_color.rgb, grout_color.rgb, grout * step(0.7, abs(world_normal.y)));
    }
    ALBEDO = color;
    ROUGHNESS = 0.85;
    NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_texture, uv).rgb, normal_strength);
    SPECULAR = specular;
}

void light () {
	float ndotl = clamp(dot(NORMAL,LIGHT),0.0,1.0) * ATTENUATION;

	float light = ndotl;

	if(use_stepped){
		float light_mult = light * steps;
		float step_base = floor(light_mult);
		float light_factor = light_mult - step_base;

		light_factor = smoothstep(0.5 - step_smoothness, 0.5 + step_smoothness, light_factor);
		light = (step_base + light_factor) / steps;
	}

	if(use_pattern){
		vec2 p_uv = pattern_uv(UV, SCREEN_UV);

		light = mix(light, shape_value(light, p_uv, VIEWPORT_SIZE), pattern_blend);
	}

	vec3 diffuse = vec3(pow(light, 1.0)) * (LIGHT_COLOR / PI);
	diffuse = mix(diffuse, diffuse * shadow_tint.rgb, (1.0 - light) * shadow_tint_amount);

	if(use_rim){
		float rim_value = fresnel(rim_amount, NORMAL, VIEW);
		rim_value = smoothstep(0.5 - (rim_smoothness / 2.0), 0.5 + (rim_smoothness / 2.0), rim_value);
		rim_value = mix(rim_value, rim_value * light, rim_mask_shadow);

		diffuse += rim_color.rgb * rim_value * rim_blend;
	}

	DIFFUSE_LIGHT += mix(diffuse, ALBEDO * diffuse, albedo_affect);
	SPECULAR_LIGHT += (LIGHT_COLOR / PI) * pow(light, 50.0) * specular;
}
