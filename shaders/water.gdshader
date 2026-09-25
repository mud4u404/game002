shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float night_factor;
uniform sampler2D n1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D n2 : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv1 = wpos.xz * 0.018 + vec2(TIME * 0.008, TIME * 0.003);
	vec2 uv2 = wpos.xz * 0.041 - vec2(TIME * 0.004, -TIME * 0.009);
	NORMAL_MAP = normalize(texture(n1, uv1).rgb + texture(n2, uv2).rgb - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35;
	ALBEDO = mix(vec3(0.03, 0.07, 0.09), vec3(0.01, 0.02, 0.03), night_factor);
	// 夜间江面的城市灯光碎影
	float g1 = texture(n1, uv1 * vec2(0.6, 4.0)).r;
	float g2 = texture(n2, uv2 * vec2(0.5, 5.0)).g;
	float glint = smoothstep(0.62, 0.8, g1 * g2 * 1.6);
	vec3 city = mix(vec3(1.0, 0.7, 0.4), vec3(0.5, 0.8, 1.0), step(0.5, fract(wpos.x * 0.013)));
	EMISSION = city * glint * 0.8 * night_factor + vec3(0.025, 0.045, 0.075) * night_factor;
	ROUGHNESS = 0.03;
	METALLIC = 0.1;
	SPECULAR = 0.9;
}
