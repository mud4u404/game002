extends Node3D
## 主菜单：傍晚的辖区地图缓慢平移作背景。

var city: CityMap
var env: EnvironmentRig
var cam: RTSCamera
var ui: Control
var _fade: ColorRect
var _t := 0.0
var _pan_dir := Vector3(1, 0, -0.3).normalized()


func _ready() -> void:
	GameState.reset()
	GameState.minutes = 18.6 * 60.0
	city = CityMap.new()
	add_child(city)
	env = EnvironmentRig.new()
	add_child(env)
	cam = RTSCamera.new()
	cam.input_enabled = false
	cam.bounds = Rect2(-2000, -2000, 4000, 4000)
	add_child(cam)
	cam.set_view(Vector3(-40, 0, 30), 480, 0)
	env.apply(GameState.time_of_day())
	_build_ui()
	await city.build(Game.SEED)



func _process(delta: float) -> void:
	_t += delta
	cam.focus_on(cam.target + _pan_dir * delta * 5.0)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UIKit.theme()
	layer.add_child(ui)

	# 左侧渐变遮罩，保证文字可读
	var shade := Control.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.draw.connect(func():
		var vs := shade.size
		var a := Color(0.05, 0.06, 0.08, 0.94)
		var b := Color(0.05, 0.06, 0.08, 0.0)
		shade.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x * 0.55, 0), Vector2(vs.x * 0.55, vs.y), Vector2(0, vs.y)]),
			PackedColorArray([a, b, b, a])))
	ui.add_child(shade)

	var col := VBoxContainer.new()
	col.position = Vector2(130, 170)
	col.add_theme_constant_override("separation", 0)
	ui.add_child(col)
	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 14)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(64, 64)
	badge.draw.connect(func():
		UIKit.draw_round_rect(badge, Rect2(0, 0, 64, 64), UIKit.NAVY, 14)
		UIKit.draw_icon(badge, "local_police", Vector2(32, 32), 40, Color.WHITE))
	badge_row.add_child(badge)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_theme_constant_override("separation", -4)
	bv.add_child(UIKit.label("江城市公安局", 16, UIKit.TEXT_DIM, "bold"))
	bv.add_child(UIKit.label("滨江分局指挥中心", 16, UIKit.TEXT_DIM))
	badge_row.add_child(bv)
	col.add_child(badge_row)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 26)
	col.add_child(sp)
	var title := UIKit.label("110", 148, Color.WHITE, "bold")
	title.add_theme_constant_override("line_spacing", -40)
	col.add_child(title)
	var sub := UIKit.label("城市守夜人", 52, Color.WHITE, "bold")
	col.add_child(sub)
	var tag := UIKit.label("在预算之内，守护一座城市的夜晚。", 18, UIKit.TEXT_DIM)
	col.add_child(tag)
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 48)
	col.add_child(sp2)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 10)
	col.add_child(menu)
	var start := UIKit.icon_text_button("play_arrow", "开始值班", "primary", UIKit.ACCENT, 18)
	start.custom_minimum_size = Vector2(300, 56)
	start.pressed.connect(_start)
	menu.add_child(start)
	for it in [["map", "沙盒模式", false], ["settings", "设置", false], ["close", "退出游戏", true]]:
		var b := UIKit.icon_text_button(it[0], it[1], "secondary", UIKit.ACCENT, 16)
		b.custom_minimum_size = Vector2(300, 48)
		b.disabled = not it[2]
		if not it[2]:
			b.tooltip_text = "即将开放"
		if it[1] == "退出游戏":
			b.pressed.connect(func(): get_tree().quit())
		menu.add_child(b)

	var foot := UIKit.label("原型版本 0.2 · 江城为虚构城市，人物与情节纯属虚构", 12, UIKit.TEXT_MUTED)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(130, -56)
	ui.add_child(foot)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.2)


func _start() -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/game.tscn"))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and (e.keycode == KEY_ENTER or e.keycode == KEY_SPACE):
		_start()
