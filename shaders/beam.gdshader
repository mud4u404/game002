shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform float intensity = 2.0;
uniform float height = 60.0;

varying float hy;

void vertex() {
	hy = VERTEX.y / height + 0.5;
}

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float fade = pow(1.0 - clamp(hy, 0.0, 1.0), 2.2);
	float flick = 0.85 + 0.15 * sin(TIME * 6.0);
	ALBEDO = color.rgb * intensity;
	ALPHA = clamp(fade * (0.25 + 0.75 * fres) * 0.55 * flick, 0.0, 1.0);
}
