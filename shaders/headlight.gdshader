shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 车头灯在路面上的光斑（UV.y: 0 车头 → 1 远端）
global uniform float night_factor;
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float intensity = 0.35;

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float y = UV.y;
	float cone = smoothstep(1.0, 0.0, abs(x) / (0.35 + 0.65 * y));
	float fall = smoothstep(1.0, 0.1, y) * smoothstep(0.0, 0.08, y);
	ALBEDO = color.rgb * intensity;
	ALPHA = clamp(cone * fall * night_factor, 0.0, 1.0);
}
