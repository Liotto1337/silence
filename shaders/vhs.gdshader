shader_type canvas_item;
// VHS tape look: line jitter, a rolling tracking band, chroma bleed, scanlines, grain, vignette.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float scanline_count = 240.0;
uniform float grain = 0.06;
uniform float chroma_offset = 0.0022;
uniform float vignette = 0.45;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;

	// Per-line horizontal wobble.
	float line = floor(uv.y * scanline_count);
	float wobble = (hash(vec2(line, floor(t * 24.0))) - 0.5) * 0.0016;

	// Slow rolling tracking band with stronger tearing.
	float band_y = fract(t * 0.06);
	float band = 1.0 - smoothstep(0.0, 0.035, abs(uv.y - band_y));
	wobble += band * (hash(vec2(t, line)) - 0.5) * 0.02;

	// Rare full-frame glitch.
	float glitch = step(0.995, hash(vec2(floor(t * 8.0), 3.7)));
	wobble += glitch * (hash(vec2(line, t)) - 0.5) * 0.03;

	uv.x += wobble * intensity;

	float ca = chroma_offset * intensity * (1.0 + band * 2.0);
	vec3 col;
	col.r = texture(screen_texture, uv + vec2(ca, 0.0)).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - vec2(ca, 0.0)).b;

	// Slight desaturation + warm tape tint.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), 0.18 * intensity) * vec3(1.03, 1.0, 0.95);

	// Scanlines.
	col *= 1.0 - 0.12 * intensity * (0.5 + 0.5 * sin(SCREEN_UV.y * scanline_count * 3.14159 * 2.0));

	// Band brightening and grain.
	col += band * 0.06 * intensity;
	col += (hash(SCREEN_UV * vec2(1920.0, 1080.0) + fract(t) * 100.0) - 0.5) * grain * intensity;

	// Vignette.
	vec2 v = SCREEN_UV - 0.5;
	col *= 1.0 - dot(v, v) * vignette * 2.0 * intensity;

	COLOR = vec4(col, 1.0);
}
