shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 俯瞰地图风格的建筑屋顶。
// INSTANCE_CUSTOM: r=seed  g=style  b=lit_ratio  a=未用
// style: 0 CBD  1 住宅  2 老城  3 商业  4 工业  5 公安设施  6 屋顶设备  7 地标
global uniform float night_factor;
uniform sampler2D lightmap : source_color, filter_linear, repeat_disable;
uniform vec4 lm_rect = vec4(-600.0, -600.0, 1200.0, 0.0);

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 lpos;
varying vec3 bsize;
varying vec4 cdata;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
	bsize = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	cdata = INSTANCE_CUSTOM;
}

vec3 palette(int style, float t) {
	if (style == 0) return mix(vec3(0.30, 0.34, 0.40), vec3(0.36, 0.40, 0.46), t);
	if (style == 1) return mix(vec3(0.46, 0.44, 0.41), vec3(0.52, 0.50, 0.47), t);
	if (style == 2) return mix(vec3(0.42, 0.36, 0.32), vec3(0.48, 0.42, 0.37), t);
	if (style == 3) return mix(vec3(0.38, 0.40, 0.42), vec3(0.46, 0.46, 0.47), t);
	if (style == 4) return mix(vec3(0.36, 0.40, 0.42), vec3(0.42, 0.45, 0.46), t);
	if (style == 5) return vec3(0.72, 0.76, 0.84);
	if (style == 7) return vec3(0.34, 0.38, 0.46);
	return mix(vec3(0.30, 0.31, 0.32), vec3(0.40, 0.40, 0.40), t);
}

void fragment() {
	float seed = cdata.r;
	int style = int(cdata.g + 0.5);
	float lit_ratio = cdata.b;
	vec3 n = normalize(wnrm);
	float night = night_factor;
	vec3 base = palette(style, h12(vec2(seed * 13.0, 2.1)));

	vec2 luv = (wpos.xz - lm_rect.xy) / lm_rect.z;
	vec3 lm = texture(lightmap, luv).rgb;

	vec3 alb;
	vec3 emi = vec3(0.0);
	float rough = 0.85;

	if (n.y > 0.5) {
		// 屋顶：外沿女儿墙 + 内部纹理
		vec2 half_sz = bsize.xz * 0.5;
		vec2 d = half_sz - abs(lpos.xz) * bsize.xz;
		float edge = min(d.x, d.y);
		float parapet = 1.0 - smoothstep(0.35, 0.6, edge);
		float inner_line = smoothstep(0.9, 1.0, edge) * (1.0 - smoothstep(1.0, 1.15, edge));
		float grain = h12(floor(wpos.xz * 1.5)) * 0.06;
		alb = base * (0.92 + grain);
		alb = mix(alb, base * 1.35, parapet);
		alb = mix(alb, base * 0.7, inner_line);
		if (style == 5) {
			// 公安设施：蓝色屋顶标识带
			float band = step(abs(lpos.z * bsize.z + half_sz.y * 0.55), 1.2);
			alb = mix(alb, vec3(0.1, 0.3, 0.8), band * (1.0 - parapet));
			emi += band * vec3(0.1, 0.35, 1.0) * 0.6 * night;
		}
		if (style == 1 || style == 2) {
			// 住宅屋顶：夜间零星的天井 / 楼梯间灯光
			vec2 cell = floor(wpos.xz / 4.0);
			vec2 f = fract(wpos.xz / 4.0);
			float dotm = step(length(f - 0.5), 0.14) * step(h12(cell + seed), lit_ratio * 0.35);
			emi += dotm * vec3(1.0, 0.75, 0.45) * 1.6 * night * step(1.2, edge);
		}
		if (style == 0 || style == 7) {
			// 高层屋顶设备与直升机坪般的几何线
			float ring = abs(length(lpos.xz * bsize.xz) - min(half_sz.x, half_sz.y) * 0.45);
			alb = mix(alb, base * 0.75, (1.0 - smoothstep(0.15, 0.3, ring)));
			emi += (1.0 - parapet) * 0.0 + parapet * vec3(0.4, 0.8, 1.0) * 0.35 * night * step(0.5, h12(vec2(seed, 9.0)));
		}
	} else {
		// 侧面（俯视时基本不可见，仅在阴影 / 边缘处体现）
		alb = base * 0.55;
		float shop = step(wpos.y, 1.6) * step(0.3, h12(floor(wpos.xz / 6.0) + seed));
		emi += shop * lm * 1.2 * night;
	}

	// 路灯光晕照亮屋顶边缘
	emi += alb * lm * night * 0.9;
	// 夜间整体压暗、偏冷
	alb *= mix(0.74, 0.5, night);

	ALBEDO = alb;
	ROUGHNESS = rough;
	EMISSION = emi;
}
