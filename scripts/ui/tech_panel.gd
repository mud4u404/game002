class_name TechPanel
extends PanelContainer
## 切角面板：半透明深色底 + 细描边 + 角标 + 可选标题栏。

var accent := UIKit.CYAN
var title := ""
var subtitle := ""
var cut := 14.0
var header_h := 0.0
var body: VBoxContainer
var _title_label: Label
var _sub_label: Label
var _count_label: Label


func _init(p_title := "", p_sub := "", p_accent := UIKit.CYAN) -> void:
	title = p_title
	subtitle = p_sub
	accent = p_accent
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_bottom = 12
	sb.content_margin_top = 12
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	if title != "":
		header_h = 30.0
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		_title_label = UIKit.label(title, 17, UIKit.TEXT, "bold")
		h.add_child(_title_label)
		_sub_label = UIKit.tag(subtitle, UIKit.with_alpha(accent, 0.75), 11)
		_sub_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(_sub_label)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		_count_label = UIKit.label("", 15, accent, "num_bold")
		h.add_child(_count_label)
		v.add_child(h)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)


func set_count(t: String, c := Color(-1, 0, 0)) -> void:
	if _count_label:
		_count_label.text = t
		if c.r >= 0:
			_count_label.add_theme_color_override("font_color", c)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var pts := UIKit.chamfer_points(r, 0, cut, 0, cut)
	draw_colored_polygon(pts, UIKit.BG)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, UIKit.with_alpha(accent, 0.22), 1.0, true)
	UIKit.draw_brackets(self, r.grow(-1), UIKit.with_alpha(accent, 0.8), 9, 2)
	if header_h > 0:
		var y := 12 + header_h + 2
		draw_line(Vector2(14, y), Vector2(size.x - 14, y), UIKit.with_alpha(accent, 0.25), 1.0)
		draw_rect(Rect2(14, y - 1, 34, 3), accent)
	# 扫描纹理
	var t := Time.get_ticks_msec() / 1000.0
	var sy := fmod(t * 40.0, maxf(size.y, 1.0))
	draw_line(Vector2(2, sy), Vector2(size.x - 2, sy), UIKit.with_alpha(accent, 0.035), 2.0)


func _process(_d: float) -> void:
	if is_visible_in_tree():
		queue_redraw()
