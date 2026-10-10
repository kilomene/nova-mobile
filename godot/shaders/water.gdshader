shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 shallow_color : source_color = vec4(0.16, 0.46, 0.62, 0.9);
uniform vec4 deep_color : source_color = vec4(0.04, 0.18, 0.32, 0.92);

void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.45 + TIME * 1.2) * 0.09 + cos(VERTEX.z * 0.38 + TIME * 0.9) * 0.09;
}

void fragment() {
	float t = (sin(UV.x * 40.0 + TIME * 1.1) + cos(UV.y * 40.0 - TIME * 1.3)) * 0.25 + 0.5;
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, t * 0.4);
	ALPHA = 0.9;
	ROUGHNESS = 0.12;
	SPECULAR = 0.65;
}
