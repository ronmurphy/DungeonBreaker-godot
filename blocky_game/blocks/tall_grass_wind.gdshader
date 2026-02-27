shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_texture : filter_nearest, source_color;
uniform float sway_strength : hint_range(0.0, 1.0) = 0.3;
uniform float sway_speed : hint_range(0.1, 3.0) = 1.5;
uniform bool enable_sway = true;

void vertex() {
	if (enable_sway) {
		// Create wind-like sway based on world position and time
		// Use Y coordinate to make top sway more than bottom (like real grass)
		// 1.0 - UV.y so that top (1.0) becomes 0, bottom (0.0) becomes 1.0
		// Then we want the opposite, so use UV.y directly but invert the logic
		float height_factor = UV.y; // Top of grass is UV.y = 1.0, bottom = 0.0
		height_factor = clamp(height_factor, 0.0, 1.0); // Ensure 0-1 range
		
		// Use sin/cos for smooth wave motion
		// Invert height_factor so top sways more (1.0 at top becomes stronger effect)
		float top_sway = height_factor; // This gives us more sway at top (UV.y = 1.0)
		
		float sway_x = sin(VERTEX.y + TIME * sway_speed + VERTEX.x * 0.5) * top_sway * sway_strength;
		float sway_z = cos(VERTEX.y + TIME * sway_speed * 0.7 + VERTEX.z * 0.5) * top_sway * sway_strength;
		
		VERTEX.x += sway_x;
		VERTEX.z += sway_z;
	}
}

void fragment() {
	vec4 albedo = texture(albedo_texture, UV);
	ALBEDO = albedo.rgb;
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.6;
}
