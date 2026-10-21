// Chão e paredes: cor com variação por ruído na posição do mundo (sem texturas).
// color_a/color_b: tons principais; color_c: manchas (terra no gramado, musgo na pedra).
shader_type spatial;

uniform vec3 color_a : source_color = vec3(0.28, 0.40, 0.24);
uniform vec3 color_b : source_color = vec3(0.38, 0.50, 0.28);
uniform vec3 color_c : source_color = vec3(0.45, 0.38, 0.26);
uniform float scale = 0.35;
uniform float patch_amount = 0.25;
uniform float roughness_value = 0.95;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Mistura xz com y para as laterais das paredes também variarem.
	vec2 p = (world_pos.xz + vec2(world_pos.y * 0.7, -world_pos.y * 0.4)) * scale;
	float n = noise(p) * 0.6 + noise(p * 2.7) * 0.3 + noise(p * 7.0) * 0.1;
	vec3 color = mix(color_a, color_b, n);
	float patches = smoothstep(1.0 - patch_amount, 1.0, noise(p * 0.35 + vec2(17.0, 3.0)));
	color = mix(color, color_c, patches * 0.8);
	ALBEDO = color;
	ROUGHNESS = roughness_value;
}
