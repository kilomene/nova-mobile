shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 wall_color : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform float scroll_speed = 0.35;

void fragment() {
	// Vertical scan bands scrolling upward + soft edge fade.
	float bands = smoothstep(0.35, 0.65, fract(UV.y * 24.0 - TIME * scroll_speed));
	float a = 0.10 + bands * 0.22;
	// Fade near top/bottom of the cylinder.
	a *= smoothstep(0.0, 0.08, UV.y) * smoothstep(1.0, 0.92, UV.y);
	ALBEDO = wall_color.rgb;
	ALPHA = a;
}
