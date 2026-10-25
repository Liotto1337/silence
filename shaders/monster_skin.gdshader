shader_type spatial;
// Aged skin / bone / rust for the monster. Everything is procedural in the part's own (model)
// space, so the wear sticks to the body while it animates: low-frequency grime darkens it, thin
// vertical scuffs and scratches show paler, small specks of dried blood and dirt, and the
// roughness follows the grime. A rim term keeps the dark silhouette readable in the flashlight.
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.12, 0.12, 0.14, 1.0);
uniform float wear : hint_range(0.0, 1.0) = 1.0;
uniform float scale = 9.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

varying vec3 obj_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	vec3 p = obj_pos * scale;
	float grime = smoothstep(0.38, 0.72, fbm(p * 0.6));
	// Long thin scuffs running down the limbs, plus finer cross scratches.
	float scuff = smoothstep(0.84, 0.9, noise(obj_pos * vec3(60.0, 5.0, 60.0))) * smoothstep(0.35, 0.6, noise(p * 0.4 + 7.0));
	float scratch = smoothstep(0.9, 0.93, noise(obj_pos * vec3(9.0, 120.0, 14.0)));
	float specks = smoothstep(0.76, 0.8, noise(p * 4.5));
	vec3 c = albedo.rgb;
	c *= mix(1.0, 0.5, grime * wear);
	c = mix(c, c * 1.7 + vec3(0.035, 0.032, 0.03), max(scuff * 0.5, scratch * 0.35) * wear);
	c = mix(c, vec3(0.1, 0.018, 0.012), specks * 0.55 * wear);
	ALBEDO = c;
	ROUGHNESS = mix(0.42, 0.95, grime);
	METALLIC = metallic * (1.0 - grime);
	RIM = 0.6;
	RIM_TINT = 0.4;
}
