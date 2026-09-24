shader_type spatial;
render_mode unshaded, shadows_disabled;

// 航空障碍灯：INSTANCE_CUSTOM.r 为相位
global uniform float night_factor;
varying float phase;

void vertex() {
	phase = INSTANCE_CUSTOM.r;
}

void fragment() {
	float b = step(0.55, fract(TIME * 0.5 + phase));
	ALBEDO = vec3(1.0, 0.08, 0.05) * (0.3 + 6.0 * b) * (0.2 + 0.8 * night_factor);
}
