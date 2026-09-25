shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 俯瞰地图地面：采样 2D 绘制的高清地面贴图，叠加细节噪声与夜间路灯光照
global uniform float night_factor;
uniform sampler2D map_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D lightmap : source_color, filter_linear, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec4 world_rect = vec4(-560.0, -420.0, 1120.0, 840.0);
uniform vec4 play_rect = vec4(-420.0, -300.0, 840.0, 600.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float inside_play(vec2 p) {
	vec2 a = play_rect.xy;
	vec2 b = play_rect.xy + play_rect.zw;
	vec2 s = smoothstep(a - 2.0, a + 2.0, p) * (1.0 - smoothstep(b - 2.0, b + 2.0, p));
	return s.x * s.y;
}

void fragment() {
	vec2 uv = (wpos.xz - world_rect.xy) / world_rect.zw;
	vec3 c = texture(map_tex, clamp(uv, vec2(0.0005), vec2(0.9995))).rgb;
	float in_world = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	c = mix(vec3(0.5, 0.49, 0.46), c, in_world);
	float d1 = texture(detail, wpos.xz * 0.09).r;
	float d2 = texture(detail, wpos.xz * 0.013).r;
	c *= 0.93 + 0.1 * d1 + 0.1 * (d2 - 0.5);
	float ip = inside_play(wpos.xz);
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(mix(vec3(g), c, 0.3) * 0.6, c, ip);
	vec3 lm = texture(lightmap, clamp(uv, vec2(0.0), vec2(1.0))).rgb * in_world;
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
	EMISSION = c * lm * night_factor * 2.4 * mix(0.35, 1.0, ip);
}
