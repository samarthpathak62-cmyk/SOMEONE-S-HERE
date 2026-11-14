shader_type spatial;
render_mode cull_back, specular_disabled;

// PSX / Fears-to-Fathom look for the station meshes.
// Cheap on integrated GPUs: one texture read, vertex snapping, quantized light.

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
// Vertex snapping grid (lower = more wobble, more PSX)
uniform vec2 snap_resolution = vec2(240.0, 135.0);
// Colour banding steps per channel
uniform float color_steps = 14.0;
// Light bands (lit / shadow sides become flat steps)
uniform float light_steps = 4.0;

void vertex() {
	// Classic PS1 vertex jitter: snap the clip-space position to a coarse grid
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip = PROJECTION_MATRIX * view_pos;
	vec3 ndc = clip.xyz / clip.w;
	ndc.xy = floor(ndc.xy * snap_resolution) / snap_resolution;
	clip.xyz = ndc * clip.w;
	POSITION = clip;
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb * albedo_tint.rgb;
	ALBEDO = floor(col * color_steps + 0.5) / color_steps;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float band = floor(ndl * light_steps + 0.5) / light_steps;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * band;
}
