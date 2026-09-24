extends Node3D
## 主菜单：夜间城市俯瞰作背景，指挥系统开机界面。

var city: CityBuilder
var env: EnvironmentRig
var cam: RTSCamera
var ui: Control
var _fade: ColorRect
var _boot: Label
var _boot_lines := [
	"江城市公安局 110 指挥调度系统 v0.1",
	"> 地理信息平台 ········· 已加载",
	"> 350MHz 集群通信 ······ 在线",
	"> 视频监控网（天网）··· 在线",
	"> 警力定位（北斗）····· 14 组在线",
	"> 夜班交接 ············· 待指挥长确认",
]
var _t := 0.0
var _pan_dir := Vector3(1, 0, -0.35).normalized()
var _clock: Label


func _ready() -> void:
	GameState.reset()
	GameState.minutes = 21.5 * 60.0
	city = CityBuilder.new()
	add_child(city)
	city.build(Game.SEED)
	env = EnvironmentRig.new()
	add_child(env)
	var traffic := Traffic.new()
	add_child(traffic)
	traffic.setup(city.graph, 220, Game.SEED)
	cam = RTSCamera.new()
	cam.input_enabled = false
	add_child(cam)
	cam.set_view(Vector3(-120, 0, 40), 420, 0)
	env.apply(GameState.time_of_day())
	_build_ui()


func _process(delta: float) -> void:
	_t += delta
	cam.focus_on(cam.target + _pan_dir * delta * 6.0)
	var n := clampi(int(_t * 2.2), 0, _boot_lines.size())
	_boot.text = "\n".join(_boot_lines.slice(0, n)) + ("_" if fmod(_t, 0.8) < 0.4 else " ")
	_clock.text = Time.get_datetime_string_from_system(false, true).replace("T", "  ")
	ui.queue_redraw()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.theme()
	ui.draw.connect(_draw_bg)
	layer.add_child(ui)

	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/ui_vignette.gdshader")
	vm.set_shader_parameter("strength", 0.8)
	vig.material = vm
	ui.add_child(vig)

	var logo := Control.new()
	logo.position = Vector2(120, 150)
	logo.size = Vector2(700, 320)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.draw.connect(_draw_logo.bind(logo))
	ui.add_child(logo)

	var menu := VBoxContainer.new()
	menu.position = Vector2(120, 520)
	menu.add_theme_constant_override("separation", 6)
	ui.add_child(menu)
	var items := [
		["01", "开始值班", "START SHIFT", true, _start],
		["02", "沙盒模式", "SANDBOX · 即将开放", false, Callable()],
		["03", "系统设置", "SETTINGS · 即将开放", false, Callable()],
		["04", "退出系统", "EXIT", true, func(): get_tree().quit()],
	]
	for it in items:
		menu.add_child(_menu_item(it[0], it[1], it[2], it[3], it[4]))

	var boot_bg := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.01, 0.02, 0.04, 0.82)
	bsb.border_color = UIKit.with_alpha(UIKit.CYAN, 0.25)
	bsb.border_width_left = 2
	boot_bg.add_theme_stylebox_override("panel", bsb)
	boot_bg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	boot_bg.position = Vector2(-540, -270)
	boot_bg.size = Vector2(500, 200)
	boot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(boot_bg)
	_boot = UIKit.label("", 14, UIKit.with_alpha(UIKit.CYAN, 0.8), "mono")
	_boot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_boot.position = Vector2(-520, -250)
	_boot.size = Vector2(480, 200)
	ui.add_child(_boot)

	_clock = UIKit.label("", 16, UIKit.TEXT_DIM, "num")
	_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock.position = Vector2(-300, 40)
	ui.add_child(_clock)

	var foot := UIKit.label("原型版本 v0.1 · 江城为虚构城市，所有人物与情节均为虚构", 13, UIKit.TEXT_DIM)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(120, -60)
	ui.add_child(foot)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.2)


func _draw_bg() -> void:
	var vs := ui.size
	# 左侧暗化渐变
	var cols := PackedColorArray([Color(0.005, 0.012, 0.025, 0.93), Color(0.005, 0.012, 0.025, 0.0)])
	ui.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vs.x * 0.62, 0), Vector2(vs.x * 0.62, vs.y), Vector2(0, vs.y)]),
		PackedColorArray([cols[0], cols[1], cols[1], cols[0]]))
	ui.draw_line(Vector2(80, 120), Vector2(80, vs.y - 90), UIKit.with_alpha(UIKit.CYAN, 0.35), 1.0)
	var y := 120.0 + fmod(_t * 60.0, vs.y - 210.0)
	ui.draw_rect(Rect2(78, y, 5, 40), UIKit.CYAN)


func _draw_logo(c: Control) -> void:
	var fb := UIKit.font("num_bold")
	var fz := UIKit.font("bold")
	var glow := 0.6 + 0.4 * sin(_t * 1.6)
	for k in range(6, 0, -1):
		c.draw_string_outline(fb, Vector2(0, 160), "110", HORIZONTAL_ALIGNMENT_LEFT, -1, 190, k * 6, UIKit.with_alpha(UIKit.CYAN, 0.025 * glow))
	c.draw_string(fb, Vector2(0, 160), "110", HORIZONTAL_ALIGNMENT_LEFT, -1, 190, Color(0.75, 0.97, 1.0))
	var x := 0.0
	for ch in "城市守夜人":
		c.draw_string(fz, Vector2(x + 6, 240), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color.WHITE)
		x += 78.0
	c.draw_string(UIKit.font("num"), Vector2(8, 285), "CITY WATCH  ·  江城市公安指挥调度模拟", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.with_alpha(UIKit.CYAN, 0.85))
	c.draw_rect(Rect2(8, 300, 60, 3), UIKit.CYAN)
	c.draw_rect(Rect2(76, 300, 14, 3), UIKit.RED)
	c.draw_rect(Rect2(96, 300, 14, 3), UIKit.BLUE)


func _menu_item(idx: String, zh: String, en: String, enabled: bool, cb: Callable) -> Control:
	var item := Control.new()
	item.custom_minimum_size = Vector2(560, 64)
	item.mouse_filter = Control.MOUSE_FILTER_STOP
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	item.set_meta("hover", 0.0)
	item.set_meta("h", false)
	item.mouse_entered.connect(func(): item.set_meta("h", true))
	item.mouse_exited.connect(func(): item.set_meta("h", false))
	item.gui_input.connect(func(e):
		if enabled and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			cb.call())
	item.draw.connect(func():
		var hv: float = item.get_meta("hover")
		var target := 1.0 if item.get_meta("h") and enabled else 0.0
		hv = lerpf(hv, target, 0.25)
		item.set_meta("hover", hv)
		var w := item.size.x
		if hv > 0.01:
			var pts := UIKit.chamfer_points(Rect2(0, 4, w * hv, 56), 0, 16, 0, 0)
			item.draw_colored_polygon(pts, UIKit.with_alpha(UIKit.CYAN, 0.14 * hv))
			item.draw_rect(Rect2(0, 4, 4, 56), UIKit.CYAN)
		var dim := 1.0 if enabled else 0.35
		item.draw_string(UIKit.font("num_bold"), Vector2(20 + hv * 10, 44), idx, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.with_alpha(UIKit.CYAN, dim))
		item.draw_string(UIKit.font("bold"), Vector2(70 + hv * 10, 44), zh, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UIKit.with_alpha(Color.WHITE, dim))
		item.draw_string(UIKit.font("num"), Vector2(210 + hv * 10, 43), en, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.with_alpha(UIKit.TEXT_DIM, dim))
		if hv > 0.5:
			var ax := w - 40.0
			item.draw_colored_polygon(PackedVector2Array([Vector2(ax, 24), Vector2(ax + 12, 32), Vector2(ax, 40)]), UIKit.CYAN)
		item.queue_redraw())
	return item


func _start() -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/game.tscn"))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and (e.keycode == KEY_ENTER or e.keycode == KEY_SPACE):
		_start()
