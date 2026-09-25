shader_type spatial;
render_mode unshaded;

// 战术图建筑：深蓝体块，屋顶略亮，墙面按朝向做简单明暗
global uniform float night_factor;
uniform sampler2D lightmap : source_color, filter_linear, repeat_disable;
uniform vec4 lm_rect = vec4(-560.0, -420.0, 1120.0, 840.0);
uniform vec4 play_rect = vec4(-420.0, -300.0, 840.0, 600.0);

varying vec3 wpos;
varying vec3 vcol;
varying vec3 wn;
varying vec2 info;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = pow(COLOR.rgb, vec3(2.2));
	info = UV;
}

void fragment() {
	vec3 c = vcol;
	float part = info.y;
	if (part < 0.5) {
		// 墙面
		float l = 0.55 + 0.25 * dot(wn, normalize(vec3(-0.4, 0.0, -0.8)));
		c *= l;
	} else if (part < 1.5) {
		c *= 1.45;   // 屋顶外沿亮边
	}
	vec2 a = play_rect.xy;
	vec2 b = play_rect.xy + play_rect.zw;
	vec2 s = smoothstep(a - 2.0, a + 2.0, wpos.xz) * (1.0 - smoothstep(b - 2.0, b + 2.0, wpos.xz));
	c = mix(c * 0.55, c, s.x * s.y);
	c *= mix(1.0, 0.82, night_factor);
	ALBEDO = c;
}
