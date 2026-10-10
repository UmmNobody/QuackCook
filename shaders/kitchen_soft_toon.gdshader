shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, hint_default_white;
uniform bool use_texture = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float roughness_value = 0.8;
uniform float metal_amount = 0.0;
uniform float specular_amount = 0.10;
uniform float band_softness = 0.10;
uniform bool use_vertex_color = false;
uniform bool vertex_is_srgb = false;
uniform sampler2D normal_texture : hint_normal;
uniform bool use_normal = false;
uniform float normal_amount = 1.0;

void fragment() {
    vec2 uv = UV * uv_scale.xy + uv_offset.xy;
    vec3 color = base_color.rgb;
    if (use_texture) { color *= texture(base_texture, uv).rgb; }
    if (use_vertex_color) {
        vec3 vertex_color = COLOR.rgb;
        if (vertex_is_srgb && !OUTPUT_IS_SRGB) {
            vertex_color = mix(vertex_color / 12.92, pow((vertex_color + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), vertex_color));
        }
        color *= vertex_color;
    }
    ALBEDO = color;
    ROUGHNESS = roughness_value;
    SPECULAR = 0.0;
    METALLIC = 0.0;
    if (use_normal) {
        NORMAL_MAP = texture(normal_texture, uv).rgb;
        NORMAL_MAP_DEPTH = normal_amount;
    }
}

void light() {
    float ndl = max(dot(NORMAL, LIGHT), 0.0);
    // Three plateaus; distance and cast-shadow attenuation remain continuous.
    float bands = 0.5 * smoothstep(0.24 - band_softness, 0.24 + band_softness, ndl);
    bands += 0.5 * smoothstep(0.70 - band_softness, 0.70 + band_softness, ndl);
    DIFFUSE_LIGHT += (LIGHT_COLOR / PI) * bands * ATTENUATION;
    vec3 half_vector = normalize(LIGHT + VIEW);
    float shine = smoothstep(0.93, 0.98, max(dot(NORMAL, half_vector), 0.0));
    SPECULAR_LIGHT += mix(vec3(1.0), ALBEDO, metal_amount) * (LIGHT_COLOR / PI) * shine * specular_amount * ATTENUATION;
}
