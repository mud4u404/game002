shader_type canvas_item;
// 轻微暗角，让视线集中在地图中央

uniform float strength = 0.28;

void fragment() {
	vec2 d = SCREEN_UV - 0.5;
	float v = smoothstep(0.45, 0.95, length(d * vec2(1.25, 1.0)));
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
