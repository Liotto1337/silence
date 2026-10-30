shader_type canvas_item;
// Cold in the vent ducts. As `cold` grows the picture turns grey-blue, frost creeps in from the
// screen edges (blocky, on the same 240-line grid as the PS1 pass) and bends the image behind it,
// the view starts to shiver, and near the end the edges and then the whole screen go dark.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float cold : hint_range(0.0, 1.0) = 0.0;  // 0 = warm, 1 = frozen to death
uniform float lines = 240.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = screen_px.x / screen_px.y;
	vec2 res = vec2(lines * aspect, lines);
	vec2 cell = floor(SCREEN_UV * res);
	vec2 uv = (cell + 0.5) / res;

	// Distance to the nearest screen edge (in screen heights), roughened so the frost line is jagged.
	float edge = min(min(uv.x, 1.0 - uv.x) * aspect, min(uv.y, 1.0 - uv.y));
	float rough = fbm(cell * 0.06);
	float reach = pow(cold, 1.5) * 0.42;  // slow at first, closing in fast at the end
	float frost = smoothstep(reach, reach - 0.12, edge + (rough - 0.5) * 0.18);
	frost *= smoothstep(0.0, 0.08, cold);

	// Shivering: whole-pixel jumps that get stronger past a third of the way.
	float shiver = smoothstep(0.35, 1.0, cold);
	vec2 jitter = (vec2(hash(vec2(floor(TIME * 24.0), 1.3)), hash(vec2(floor(TIME * 24.0), 7.1))) - 0.5) * shiver * 3.0 / res;
	// The frost refracts what is behind it.
	vec2 bend = (vec2(fbm(cell * 0.21), fbm(cell * 0.21 + 31.0)) - 0.5) * 0.02 * frost;
	vec3 col = texture(screen_texture, uv + jitter + bend).rgb;

	// Grey-blue chill.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma) * vec3(0.78, 0.9, 1.12), smoothstep(0.0, 0.6, cold) * 0.75);

	// Ice crystals: a pale, streaky pattern inside the frosted area, dimmer where the scene is dark
	// (so in an unlit duct it doesn't glow).
	float crystals = fbm(cell * vec2(0.35, 0.12) + rough * 4.0);
	vec3 ice = mix(vec3(0.42, 0.52, 0.62), vec3(0.8, 0.88, 0.96), smoothstep(0.35, 0.75, crystals));
	ice *= 0.32 + min(luma * 2.5, 0.68);
	col = mix(col, ice, frost * 0.7);

	// Closing in: dark edges, then the whole picture fades out.
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	col *= 1.0 - smoothstep(0.55, 1.0, cold) * smoothstep(0.25, 0.85, length(c)) * 0.9;
	col *= 1.0 - smoothstep(0.85, 1.0, cold) * 0.7;
	COLOR = vec4(col, 1.0);
}
