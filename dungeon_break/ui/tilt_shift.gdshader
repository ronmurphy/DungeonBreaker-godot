shader_type canvas_item;
// Tilt-shift (miniature/diorama) effect for isometric view.
// Blurs top and bottom edges of the screen; keeps a focus band sharp.
// Reads the composited screen texture, so place on a CanvasLayer below UI.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// 0 = off, higher = more blur in the out-of-focus zones
uniform float blur_strength : hint_range(0.0, 4.0) = 2.0;

// Vertical centre of the sharp band (0 = top, 1 = bottom). 0.5 = screen middle.
uniform float focus_center : hint_range(0.0, 1.0) = 0.5;

// How tall the fully-sharp zone is (fraction of screen height, 0..1).
uniform float focus_width : hint_range(0.0, 1.0) = 0.3;

// How gradually focus falls off outside the band (higher = softer transition).
uniform float focus_falloff : hint_range(0.01, 1.0) = 0.25;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = SCREEN_PIXEL_SIZE;

	// Compute vertical distance from focus band edges
	float half_band = focus_width * 0.5;
	float dist_from_center = abs(uv.y - focus_center);
	float band_edge = max(0.0, dist_from_center - half_band);
	float blur_factor = smoothstep(0.0, focus_falloff, band_edge);
	float radius = blur_factor * blur_strength;

	if (radius < 0.001) {
		// Inside focus band — sharp pass-through, skip sampling
		COLOR = textureLod(screen_texture, uv, 0.0);
	} else {
		// Gaussian-ish weighted 9-tap vertical + horizontal blur
		// The kernel size scales with radius for a natural bokeh feel.
		vec4 sum = vec4(0.0);
		float total_weight = 0.0;

		// Weights for 9-tap (roughly Gaussian: 1 2 3 4 5 4 3 2 1)
		const int TAPS = 4;
		float weights[5] = float[](0.227, 0.194, 0.122, 0.054, 0.016);

		for (int i = -TAPS; i <= TAPS; i++) {
			for (int j = -TAPS; j <= TAPS; j++) {
				// Only sample primary axes + light diagonals to save taps
				if (abs(i) > 0 && abs(j) > 0 && abs(i) + abs(j) > TAPS) continue;

				vec2 offset = vec2(float(i), float(j)) * pixel * radius * 2.5;
				float w = weights[abs(i)] * weights[abs(j)];
				sum += textureLod(screen_texture, uv + offset, 0.0) * w;
				total_weight += w;
			}
		}
		COLOR = sum / total_weight;
	}
}
