shader_type canvas_item;

// Light VHS / CRT overlay: one screen texture read per pixel (cheap on integrated GPUs).
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.03;
uniform float scanline_strength : hint_range(0.0, 0.3) = 0.05;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.40;
uniform float color_steps = 64.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float edge_dist = length(centered);

	// Occasional VHS tape jitter line
	float tape_band = smoothstep(0.996, 1.0, sin(uv.y * 14.0 - TIME * 1.35));
	uv.x += tape_band * 0.002 * (hash12(vec2(TIME, uv.y)) - 0.5);

	vec3 col = texture(screen_tex, uv).rgb;
	col = floor(col * color_steps + 0.5) / color_steps;

	// Scanlines
	float scan = sin(uv.y * 900.0) * 0.5 + 0.5;
	col *= 1.0 - scanline_strength * scan;

	// Grain
	float n = hash12(uv * vec2(1280.0, 720.0) + vec2(TIME * 67.0, TIME * 31.0)) - 0.5;
	col += n * grain_strength;

	// Vignette
	col *= 1.0 - smoothstep(0.32, 0.86, edge_dist) * vignette_strength;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
