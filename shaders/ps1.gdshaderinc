// Shared body of ps1.gdshader / ps1_double.gdshader (see ps1.gdshader for what it does).

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float uv_scale = 1.0;  // texture repeats per metre
uniform bool use_mesh_uv = false;  // true: use the model's own UVs (the monster) instead of box projection
uniform bool world_uv = false;  // true: texture is pinned to the world (walls, floors); false: to the object
uniform float affine : hint_range(0.0, 1.0) = 0.6;  // 0 = perspective-correct, 1 = full PS1 affine warp
uniform vec2 snap_grid = vec2(256.0, 144.0);  // vertex snapping resolution; 0 disables it
uniform float dirt : hint_range(0.0, 1.0) = 0.0;  // darkens towards floor and ceiling (world space)
uniform bool use_vertex_color = false;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.0;  // cut-out transparency (discard below this alpha)

varying vec3 affine_uv;  // (uv * w, w): lets the fragment shader undo perspective correction
varying vec2 persp_uv;
varying float world_y;

void vertex() {
	vec3 p = world_uv ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : VERTEX;
	vec3 n = abs(world_uv ? mat3(MODEL_MATRIX) * NORMAL : NORMAL);
	vec2 uv;
	if (n.y > n.x && n.y > n.z) {
		uv = p.xz;
	} else if (n.x > n.z) {
		uv = p.zy;
	} else {
		uv = p.xy;
	}
	persp_uv = use_mesh_uv ? UV : uv * uv_scale;
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;

	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	affine_uv = vec3(persp_uv * clip.w, clip.w);
	if (snap_grid.x > 0.0 && clip.w > 0.2) {
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * snap_grid * 0.5 + 0.5) / (snap_grid * 0.5);
		clip.xy = ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec2 uv = mix(persp_uv, affine_uv.xy / affine_uv.z, affine);
	vec4 tex = texture(albedo_tex, uv);
	if (tex.a * tint.a < alpha_cut) {
		discard;
	}
	vec3 col = tex.rgb * tint.rgb;
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	float grime = 1.0 - dirt * (smoothstep(0.9, 0.0, world_y) * 0.55 + smoothstep(2.2, 2.8, world_y) * 0.35);
	ALBEDO = col * grime;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	EMISSION = emission_color.rgb * emission_energy;
}
