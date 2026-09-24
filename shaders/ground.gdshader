shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// kind: 0 路段  1 路口  2 人行道  3 草地  4 地面  5 停车场
global uniform float night_factor;
uniform int kind = 0;
uniform float road_w = 14.0;
uniform sampler2D lightmap : source_color, filter_linear, repeat_disable;
uniform vec4 lm_rect = vec4(-600.0, -600.0, 1200.0, 0.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float x, float c, float w) {
	return step(abs(x - c), w);
}

void fragment() {
	float nz = texture(noise_tex, wpos.xz * 0.012).r;
	float nz2 = texture(noise_tex, wpos.xz * 0.13).r;
	vec3 col;
	float rough = 0.9;
	float spec = 0.5;
	float paint = 0.0;
	vec3 paint_c = vec3(0.85);

	if (kind == 0 || kind == 1) {
		col = vec3(0.055, 0.06, 0.068) * (0.75 + 0.5 * nz2);
		rough = 0.8;
		spec = 0.3;
		if (kind == 0) {
			float x = (UV.x - 0.5) * road_w;
			float y = UV.y;
			float L = UV2.x;
			float hw = road_w * 0.5;
			float zebra = step(y, 5.0) + step(L - 5.0, y);
			if (zebra > 0.5) {
				paint = step(fract(x / 1.3), 0.55) * step(abs(x), hw - 0.8) * step(0.8, min(y, L - y));
			} else {
				float yellow = line(abs(x), 0.2, 0.08);
				float dash = line(abs(x), hw * 0.5, 0.08) * step(fract(y / 9.0), 0.5);
				float edge = line(abs(x), hw - 0.55, 0.08);
				float stop = step(abs(y - 6.0), 0.25) + step(abs(y - (L - 6.0)), 0.25);
				stop *= step(0.3, abs(x)) * step(abs(x), hw - 0.5);
				paint = clamp(dash + edge + stop, 0.0, 1.0);
				paint_c = mix(vec3(0.85), vec3(0.9, 0.62, 0.1), yellow);
				paint = max(paint, yellow);
			}
			paint *= 0.55 + 0.45 * nz2;
		}
	} else if (kind == 2) {
		vec2 t = fract(wpos.xz / 1.6);
		float grout = step(t.x, 0.04) + step(t.y, 0.04);
		col = vec3(0.26, 0.26, 0.25) * (0.85 + 0.3 * nz2) * (1.0 - 0.25 * clamp(grout, 0.0, 1.0));
		rough = 0.85;
	} else if (kind == 3) {
		col = mix(vec3(0.04, 0.075, 0.035), vec3(0.07, 0.11, 0.05), nz) * (0.8 + 0.4 * nz2);
		rough = 0.95;
	} else if (kind == 5) {
		col = vec3(0.07, 0.075, 0.08) * (0.8 + 0.4 * nz2);
		vec2 bay = fract(wpos.xz / vec2(3.2, 11.0));
		paint = step(bay.x, 0.04) * step(0.25, bay.y);
	} else {
		col = vec3(0.07, 0.07, 0.068) * (0.7 + 0.6 * nz);
	}

	vec3 alb = mix(col, paint_c, paint);
	alb *= (kind == 2 || kind == 4) ? 0.8 : 1.0;
	vec2 luv = (wpos.xz - lm_rect.xy) / lm_rect.z;
	vec3 lm = texture(lightmap, luv).rgb;

	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = spec;
	float road = (kind == 0 || kind == 1) ? 1.0 : 0.0;
	EMISSION = alb * lm * night_factor * 5.0 + lm * night_factor * (0.03 + 0.14 * road);
}
