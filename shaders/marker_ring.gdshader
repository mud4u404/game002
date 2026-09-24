shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform float intensity = 2.5;
uniform float speed = 0.6;
uniform float pulse = 1.0;
uniform float core = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float t = fract(TIME * speed);
	float ring = smoothstep(0.05, 0.0, abs(r - t)) * (1.0 - t) * pulse;
	float t2 = fract(TIME * speed + 0.5);
	ring += smoothstep(0.05, 0.0, abs(r - t2)) * (1.0 - t2) * pulse;
	float c = smoothstep(0.03, 0.0, abs(r - 0.32)) * core + smoothstep(0.32, 0.0, r) * 0.18 * core;
	float a = (ring + c) * step(r, 1.0);
	ALBEDO = color.rgb * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
