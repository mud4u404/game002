shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 社会车辆：车身色来自实例颜色；前照灯 / 尾灯由局部坐标生成
global uniform float night_factor;
uniform float half_len = 2.2;

varying vec3 lp;
varying vec3 ln;
varying vec3 body_c;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	body_c = COLOR.rgb;
}

void fragment() {
	float cabin = step(0.92, lp.y);
	vec3 col = mix(body_c, vec3(0.35, 0.38, 0.42), cabin * 0.6);
	float front = step(0.8, -ln.z) * step(0.35, lp.y) * step(lp.y, 0.7) * step(0.45, abs(lp.x));
	float rear = step(0.8, ln.z) * step(0.4, lp.y) * step(lp.y, 0.75) * step(0.45, abs(lp.x));
	float on = 0.25 + 0.75 * night_factor;
	ALBEDO = col;
	ROUGHNESS = mix(0.3, 0.05, cabin);
	METALLIC = mix(0.5, 0.2, cabin);
	EMISSION = front * vec3(1.0, 0.95, 0.85) * 8.0 * on + rear * vec3(1.0, 0.04, 0.02) * 5.0 * on;
}
