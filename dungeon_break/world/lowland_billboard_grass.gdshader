shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform float sway_strength : hint_range(0.0, 0.5, 0.01) = 0.22;
uniform float sway_speed : hint_range(0.1, 3.0, 0.01) = 1.2;
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform vec3 tint : source_color = vec3(0.86, 1.0, 0.86);

void vertex() {
	// Keep the base anchored while the upper blades sway.
	float h = clamp(UV.y, 0.0, 1.0);
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = (world_pos.x * 0.11) + (world_pos.z * 0.09) + TIME * sway_speed;
	float sway = sin(phase) * sway_strength * h;
	VERTEX.x += sway;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * tint;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
