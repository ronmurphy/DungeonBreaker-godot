shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D cloud_noise : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(5.0, 3.5);
uniform vec2 wind_dir = vec2(0.015, 0.008);
uniform float cutoff : hint_range(0.0, 1.0, 0.01) = 0.56;
uniform float softness : hint_range(0.0, 0.5, 0.01) = 0.08;

void fragment() {
	vec2 uv = UV * uv_scale + wind_dir * TIME;
	float n = texture(cloud_noise, uv).r;
	float a = smoothstep(cutoff - softness, cutoff + softness, n);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
