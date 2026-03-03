shader_type canvas_item;
// Screen-edge vignette for combat entry. Controlled via uniform "strength".

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float radius : hint_range(0.0, 2.0) = 0.75;
uniform float softness : hint_range(0.01, 1.0) = 0.45;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv * vec2(1.0, 0.7));  // slight vertical squeeze
	float vig = smoothstep(radius, radius + softness, dist);
	COLOR = vec4(color.rgb, vig * strength);
}
