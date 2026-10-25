shader_type spatial;
// Overlay for quest hints: a slow warm pulse with a bright rim, drawn on top of everything
// so a toy under the bed or behind a door still shows.
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.3, 1.0);

void fragment() {
	float pulse = 0.5 + 0.5 * sin(TIME * 3.5);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = color.rgb * (0.15 + 0.35 * pulse + rim * (0.4 + 0.6 * pulse));
}
