shader_type spatial;
render_mode unshaded;

// 战术图地面：直接输出 2D 绘制的地图贴图（不受光照），辖区外压暗
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
	c = mix(vec3(0.004, 0.012, 0.04), c, in_world);
	float ip = inside_play(wpos.xz);
	c = mix(c * 0.5, c, ip);
	c *= mix(1.0, 0.85, night_factor);
	ALBEDO = c;
}
