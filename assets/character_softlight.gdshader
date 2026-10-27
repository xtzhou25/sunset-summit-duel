shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
varying vec3 world_normal;
void vertex() { world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL); }
void fragment() {
 vec3 n = normalize(world_normal);
 float key = max(dot(n, normalize(vec3(-0.25, 0.7, 0.9))), 0.0);
 float fill = max(dot(n, normalize(vec3(0.45, 0.25, -0.8))), 0.0);
 float illumination = clamp(0.43 + 0.34 * key + 0.10 * fill, 0.40, 0.84);
 ALBEDO = base_color.rgb * illumination;
}
