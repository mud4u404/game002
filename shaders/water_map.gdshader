shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float night_factor;
uniform sampler2D n1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 play_rect = vec4(-420.0, -300.0, 840.0, 600.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.02 + vec2(TIME * 0.012, TIME * 0.004);
	vec2 uv2 = wpos.xz * 0.045 - vec2(TIME * 0.007, -TIME * 0.011);
	NORMAL_MAP = normalize(texture(n1, uv1).rgb + texture(n2, uv2).rgb - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.4;
	vec2 a = play_rect.xy;
	vec2 b = play_rect.xy + play_rect.zw;
	vec2 s = smoothstep(a - 2.0, a + 2.0, wpos.xz) * (1.0 - smoothstep(b - 2.0, b + 2.0, wpos.xz));
	float ip = s.x * s.y;
	vec3 day = vec3(0.24, 0.42, 0.5);
	vec3 col = mix(day, vec3(0.03, 0.06, 0.09), night_factor);
	col = mix(col * 0.65, col, ip);
	ALBEDO = col;
	ROUGHNESS = 0.22;
	SPECULAR = 0.35;
	float g1 = texture(n1, uv1 * vec2(0.6, 4.0)).r;
	float g2 = texture(n2, uv2 * vec2(0.5, 5.0)).g;
	float glint = smoothstep(0.62, 0.8, g1 * g2 * 1.6);
	EMISSION = vec3(1.0, 0.78, 0.5) * glint * 0.5 * night_factor + vec3(0.02, 0.04, 0.06) * night_factor;
}
