shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 俯瞰地图建筑：顶点色为屋顶基色；UV.x = 风格，UV.y = 部位（0 墙 / 1 屋顶外沿 / 2 屋顶）
global uniform float night_factor;
uniform sampler2D lightmap : source_color, filter_linear, repeat_disable;
uniform vec4 lm_rect = vec4(-560.0, -420.0, 1120.0, 840.0);
uniform vec4 play_rect = vec4(-420.0, -300.0, 840.0, 600.0);

varying vec3 wpos;
varying vec3 vcol;
varying vec2 info;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR.rgb;
	info = UV;
}

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float inside_play(vec2 p) {
	vec2 a = play_rect.xy;
	vec2 b = play_rect.xy + play_rect.zw;
	vec2 s = smoothstep(a - 2.0, a + 2.0, p) * (1.0 - smoothstep(b - 2.0, b + 2.0, p));
	return s.x * s.y;
}

void fragment() {
	vec3 c = vcol;
	int style = int(info.x + 0.5);
	float part = info.y;
	float rough = 0.85;
	float metal = 0.0;
	if (part > 1.5) {
		float g = h12(floor(wpos.xz * 2.0));
		c *= 0.97 + 0.05 * g;
		if (style == 1) {
			// 青瓦屋面：细密瓦垄
			c *= 0.94 + 0.08 * h12(floor(wpos.xz * 0.7));
		}
		if (style == 3) {
			rough = 0.35;
			metal = 0.25;
		}
	}
	float ip = inside_play(wpos.xz);
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(mix(vec3(lum), c, 0.3) * 0.62, c, ip);
	vec2 luv = (wpos.xz - lm_rect.xy) / lm_rect.zw;
	vec3 lm = texture(lightmap, luv).rgb;
	vec3 emi = c * lm * night_factor * 0.9 * exp(-max(wpos.y - 0.2, 0.0) / 6.0);
	// 夜间零星屋顶灯
	if (part > 1.5 && style != 1) {
		vec2 cell = floor(wpos.xz / 5.0);
		vec2 f = fract(wpos.xz / 5.0);
		float dotm = step(length(f - 0.5), 0.09) * step(h12(cell), 0.05);
		emi += dotm * vec3(1.0, 0.8, 0.55) * 1.5 * night_factor * ip;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emi;
}
