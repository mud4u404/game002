class_name EnvironmentRig
extends Node3D
## 昼夜循环：天空、日月光、雾、后处理，同步全局 night_factor。

var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var night := 1.0
var compat := false    # 网页版（Compatibility 渲染器）需要额外提亮


func _ready() -> void:
	compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, [0.0, 0.6, 1.0, 0.9, 0.7, 0.4, 0.0][i])
	env.ssao_enabled = true
	env.ssao_radius = 2.5
	env.ssao_intensity = 0.8
	env.ssao_power = 1.4
	env.ssr_enabled = false
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 1.6
	env.fog_enabled = false
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.6
	env.fog_aerial_perspective = 0.15
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 1100.0
	sun.shadow_blur = 1.5
	add_child(sun)
	apply(GameState.time_of_day())


static func night_amount(h: float) -> float:
	# 18:00→20:00 入夜，05:00→07:00 天亮
	if h >= 20.0 or h < 5.0:
		return 1.0
	if h >= 18.0:
		return smoothstep(18.0, 20.0, h)
	if h < 7.0:
		return 1.0 - smoothstep(5.0, 7.0, h)
	return 0.0


func apply(h: float) -> void:
	night = night_amount(h)
	RenderingServer.global_shader_parameter_set("night_factor", night)
	var dusk := clampf(1.0 - absf(night - 0.5) * 2.0, 0.0, 1.0)

	var day_top := Color(0.24, 0.45, 0.72)
	var day_hor := Color(0.66, 0.74, 0.82)
	var dusk_top := Color(0.14, 0.16, 0.34)
	var dusk_hor := Color(0.95, 0.46, 0.25)
	var night_top := Color(0.006, 0.01, 0.022)
	var night_hor := Color(0.07, 0.06, 0.085)
	var top := day_top.lerp(night_top, night).lerp(dusk_top, dusk * 0.8)
	var hor := day_hor.lerp(night_hor, night).lerp(dusk_hor, dusk * 0.85)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.5)
	sky_mat.sun_curve = 0.1

	# 太阳 06:00 升起，18:00 落下；夜间换为月光
	var sun_t := (h - 6.0) / 12.0
	var elev := 18.0 + sin(clampf(sun_t, 0.0, 1.0) * PI) * 52.0
	var az := lerpf(-110.0, 110.0, clampf(sun_t, 0.0, 1.0))
	if night > 0.5:
		elev = 40.0
		az = 150.0
	sun.rotation_degrees = Vector3(-maxf(elev, 8.0), az, 0)
	var day_col := Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.62, 0.38), dusk)
	sun.light_color = day_col.lerp(Color(0.7, 0.76, 0.9), night)
	sun.light_energy = lerpf(0.95, 0.2, night) * (1.0 - dusk * 0.4)
	sun.shadow_opacity = lerpf(0.32, 0.25, night)

	env.ambient_light_color = Color(0.55, 0.6, 0.68).lerp(Color(0.2, 0.25, 0.38), night)
	env.ambient_light_energy = lerpf(0.3, 0.55, night)
	env.fog_light_color = Color(0.68, 0.74, 0.82).lerp(Color(0.06, 0.055, 0.08), night).lerp(Color(0.8, 0.5, 0.35), dusk * 0.5)
	env.fog_density = lerpf(0.0007, 0.0013, night)
	env.glow_intensity = lerpf(0.0, 0.18, night)
	env.tonemap_exposure = lerpf(0.82, 1.15, night) * (lerpf(1.1, 1.6, night) if compat else 1.0)
	if compat:
		env.ambient_light_energy *= lerpf(1.0, 1.5, night)
