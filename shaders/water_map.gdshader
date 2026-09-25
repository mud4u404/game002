shader_type spatial;
render_mode unshaded;

global uniform float night_factor;
uniform sampler2D n1 : filter_linear_mipmap, repeat_enable;
uniform sampler2D n2 : filter_linear_mipmap, repeat_enable;
uniform vec4 play_rect = vec4(-420.0, -300.0, 840.0, 600.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.01 + vec2(TIME * 0.006, TIME * 0.002);
	float n = texture(n1, uv1).r;
	vec3 col = vec3(0.012, 0.05, 0.16) + vec3(0.004, 0.012, 0.03) * n;
	// 细密水纹线
	float lines = smoothstep(0.92, 1.0, sin(wpos.z * 0.9 + wpos.x * 0.05 + TIME * 0.4 + n * 6.0));
	col += vec3(0.02, 0.06, 0.16) * lines * 0.6;
	vec2 a = play_rect.xy;
	vec2 b = play_rect.xy + play_rect.zw;
	vec2 s = smoothstep(a - 2.0, a + 2.0, wpos.xz) * (1.0 - smoothstep(b - 2.0, b + 2.0, wpos.xz));
	col = mix(col * 0.55, col, s.x * s.y);
	col *= mix(1.0, 0.85, night_factor);
	ALBEDO = col;
}
