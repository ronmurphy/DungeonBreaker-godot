shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform sampler2D mask_texture : source_color;
uniform vec4 color : source_color = vec4(1.5, 1.1, 0.6, 1.0);
uniform float speed : hint_range(0.0, 5.0) = 3.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.8;
uniform float threshold : hint_range(0.0, 1.0) = 0.30;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Billboard: face the camera, preserving scale
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float sz = length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * sx, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * sy, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * sz, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 uv = UV;
	uv.x = fract(uv.x + TIME * speed);
	float mask = texture(mask_texture, uv).r;
	float alpha = smoothstep(threshold, threshold + 0.30, mask);
	ALBEDO = color.rgb * intensity;
	ALPHA = alpha * color.a * fade;
}
