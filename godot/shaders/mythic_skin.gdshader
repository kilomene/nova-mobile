shader_type spatial;

// NOVA mythic skin shader: procedural animated surface detail per theme.
// pattern: 0 = molten cracks, 1 = frost crystals, 2 = void nebula,
//          3 = circuitry, 4 = energy flow.
// evolve: 0..1 kill-evolution — intensifies glow and pattern coverage.

uniform int pattern = 0;
uniform vec4 col_primary : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform vec4 col_secondary : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float evolve = 0.0;
uniform float glow_strength = 1.4;
uniform float anim_speed = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * anim_speed;
	float pat = 0.0;
	if (pattern == 0) {
		// Molten cracks: ridged fbm, slowly creeping.
		float n = fbm(uv * 5.0 + vec2(t * 0.08, -t * 0.05));
		float r = 1.0 - abs(2.0 * n - 1.0);
		pat = pow(clamp(r * 1.4 - 0.55, 0.0, 1.0), 1.5);
	} else if (pattern == 1) {
		// Frost crystals: streaky high-frequency noise; coverage grows with evolve.
		float n = fbm(vec2(uv.x * 7.0, uv.y * 22.0) + vec2(0.0, t * 0.03));
		float cover = 0.45 + 0.35 * evolve + 0.08 * sin(t * 0.3);
		pat = smoothstep(cover, cover + 0.25, n);
	} else if (pattern == 2) {
		// Void nebula: domain-warped swirl.
		vec2 c = uv - 0.5;
		float ang = atan(c.y, c.x) + t * 0.25 + fbm(uv * 3.0) * 4.0;
		float rad = length(c) * 3.0;
		pat = 0.5 + 0.5 * sin(ang * 2.0 + rad * 4.0 - t * 0.6);
		pat = smoothstep(0.35, 0.9, pat);
	} else if (pattern == 3) {
		// Circuitry: grid lines with traveling pulses.
		vec2 g = abs(fract(uv * 10.0) - 0.5);
		float line = smoothstep(0.44, 0.5, max(g.x, g.y));
		float pulse = 0.5 + 0.5 * sin((uv.x + uv.y) * 12.0 - t * 3.0);
		pat = line * (0.35 + 0.65 * pulse);
	} else {
		// Energy flow: diagonal bands over fbm warp.
		float b = sin((uv.x * 0.7 + uv.y) * 9.0 - t * 2.2 + fbm(uv * 4.0) * 3.0);
		pat = smoothstep(0.1, 0.9, 0.5 + 0.5 * b);
	}
	float glow = glow_strength * (0.55 + 0.85 * evolve + 0.22 * sin(t * 1.7));
	vec3 base = vec3(0.05, 0.05, 0.07);
	ALBEDO = mix(base, col_primary.rgb * 0.35, pat * 0.6);
	EMISSION = mix(col_primary.rgb * 0.35, col_secondary.rgb, pat) * glow;
	METALLIC = 0.55;
	ROUGHNESS = 0.38;
}
