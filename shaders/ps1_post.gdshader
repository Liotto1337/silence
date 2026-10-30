shader_type canvas_item;
// PS1 screen pass: renders the 3D view at a fixed low line count (nearest-neighbour upscale),
// then cuts the colour depth to 5 bits per channel with an ordered 4x4 dither, like the console's
// 15-bit framebuffer. Sits below the HUD so text stays crisp.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float lines = 240.0;
uniform float levels = 32.0;
uniform float dither_strength = 1.0;
uniform float contrast = 1.08;

const mat4 BAYER = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0));

void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 res = vec2(lines * screen_px.x / screen_px.y, lines);
	vec2 cell = floor(SCREEN_UV * res);
	vec3 col = texture(screen_texture, (cell + 0.5) / res).rgb;
	col = (col - 0.5) * contrast + 0.5;
	ivec2 b = ivec2(mod(cell, 4.0));
	float d = BAYER[b.x][b.y] / 16.0 - 0.5;
	col = floor(col * (levels - 1.0) + 0.5 + d * dither_strength) / (levels - 1.0);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
