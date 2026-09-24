shader_type canvas_item;
// 屏幕暗角 + 极细扫描线，营造监控大屏质感

uniform float strength = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float v = smoothstep(0.35, 0.85, length(d * vec2(1.2, 1.0)));
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159);
	COLOR = vec4(0.0, 0.01, 0.02, v * strength + scan * 0.025);
}
