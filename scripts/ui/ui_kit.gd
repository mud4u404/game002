class_name UIKit
extends RefCounted
## 界面视觉规范（参照《112》）：深海军蓝半透明面板 + 细青蓝描边、胶囊按钮、
## 六边形图标框；实色按钮只用蓝（确认）与红（紧急/结束）。

const ACCENT := Color("2f7bff")
const CYAN := Color("3fa9ff")
const BLUE := ACCENT
const AMBER := Color("ffb020")
const RED := Color("ff3d4a")
const GREEN := Color("2fe0a0")
const TEXT := Color("eaf3ff")
const TEXT_DIM := Color("9db8dc")
const TEXT_MUTED := Color("6582ad")
const BG := Color(0.027, 0.07, 0.18, 0.94)
const BG2 := Color(0.06, 0.13, 0.28, 0.95)
const BG3 := Color(0.09, 0.19, 0.38, 0.95)
const LINE := Color(0.16, 0.48, 1.0, 0.75)
const NAVY := Color("12306e")

static var _fonts := {}


static func font(kind := "reg") -> Font:
	if _fonts.is_empty():
		var reg: FontFile = load("res://assets/fonts/NotoSansSC-Regular.ttf")
		var bold: FontFile = load("res://assets/fonts/NotoSansSC-Bold.ttf")
		var icon: FontFile = load("res://assets/fonts/MaterialSymbolsRounded-Subset.ttf")
		for f in [reg, bold, icon]:
			f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			f.hinting = TextServer.HINTING_LIGHT
		_fonts = {"reg": reg, "bold": bold, "icon": icon, "num": bold, "num_bold": bold, "mono": reg}
	return _fonts[kind]


static func icon(name: String) -> String:
	return Icons.ch(name)


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("reg")
	t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", button_box(state, "secondary"))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_MUTED)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_font("font", "Button", font("bold"))
	t.set_font_size("font_size", "Button", 13)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.3, 0.6, 1.0, 0.35)
	grab.set_corner_radius_all(3)
	grab.content_margin_left = 3
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	var sc := StyleBoxEmpty.new()
	sc.content_margin_left = 3
	t.set_stylebox("scroll", "VScrollBar", sc)
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.03, 0.07, 0.16, 0.97)
	tip.border_color = LINE
	tip.set_border_width_all(1)
	tip.set_corner_radius_all(4)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


static func panel_box(radius := 3, bg := BG, pad := 14, accent_left := false) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = LINE
	b.set_border_width_all(1)
	if accent_left:
		b.border_width_left = 4
		b.border_color = Color("1f6fff")
	b.set_corner_radius_all(radius)
	b.shadow_color = Color(0, 0.02, 0.08, 0.5)
	b.shadow_size = 12
	b.set_content_margin_all(pad)
	b.anti_aliasing = true
	return b


static func button_box(state: String, kind := "secondary", color := ACCENT) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.set_corner_radius_all(3)
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	b.anti_aliasing = true
	match kind:
		"primary":
			b.bg_color = color
			if state == "hover":
				b.bg_color = color.lightened(0.15)
			elif state == "pressed":
				b.bg_color = color.darkened(0.15)
			elif state == "disabled":
				b.bg_color = Color(color.r, color.g, color.b, 0.25)
		"ghost":
			b.bg_color = Color(0, 0, 0, 0)
			if state == "hover":
				b.bg_color = Color(0.3, 0.6, 1.0, 0.14)
			elif state == "pressed":
				b.bg_color = Color(0.3, 0.6, 1.0, 0.24)
		"active":
			b.bg_color = Color(0.18, 0.48, 1.0, 0.35)
			b.border_color = CYAN
			b.set_border_width_all(1)
		_:
			b.bg_color = Color(0.1, 0.25, 0.55, 0.25)
			b.border_color = LINE
			b.set_border_width_all(1)
			if state == "hover":
				b.bg_color = Color(0.18, 0.4, 0.85, 0.35)
				b.border_color = CYAN
			elif state == "pressed":
				b.bg_color = Color(0.18, 0.4, 0.85, 0.5)
			elif state == "disabled":
				b.bg_color = Color(0.1, 0.2, 0.4, 0.15)
				b.border_color = Color(0.3, 0.45, 0.7, 0.25)
	if state == "focus":
		b.bg_color = Color(0, 0, 0, 0)
		b.border_color = Color(0, 0, 0, 0)
	return b


static func _style(btn: Button, kind: String, color := ACCENT) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, button_box(state, kind, color))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func button(text: String, size := 13, kind := "secondary") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", size)
	_style(btn, kind)
	return btn


static func accent_button(text: String, color := ACCENT, size := 13) -> Button:
	var btn := button(text, size, "primary")
	_style(btn, "primary", color)
	return btn


static func icon_text_button(icon_name: String, text: String, kind := "secondary", color := ACCENT, size := 13) -> Button:
	var btn := button("", size, kind)
	_style(btn, kind, color)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := icon_label(icon_name, size + 4, TEXT)
	h.add_child(ic)
	var l := label(text, size, TEXT, "bold")
	h.add_child(l)
	btn.add_child(h)
	btn.custom_minimum_size = Vector2(l.get_minimum_size().x + size + 44, size + 22)
	btn.set_meta("label", l)
	btn.set_meta("icon", ic)
	return btn


static func icon_button(icon_name: String, tooltip := "", size := 20, kind := "ghost") -> Button:
	var btn := button(icon(icon_name), size, kind)
	btn.add_theme_font_override("font", font("icon"))
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(size + 16, size + 14)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var b: StyleBoxFlat = button_box(state, kind)
		b.content_margin_left = 5
		b.content_margin_right = 5
		b.content_margin_top = 3
		b.content_margin_bottom = 3
		btn.add_theme_stylebox_override(state, b)
	return btn


static func label(text: String, size := 14, color := TEXT, kind := "reg") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func icon_label(icon_name: String, size := 20, color := TEXT) -> Label:
	var l := label(icon(icon_name), size, color, "icon")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func tag(text: String, color := TEXT_MUTED, size := 12) -> Label:
	return label(text, size, color)


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


static func fmt_min(m: float) -> String:
	var mm := int(maxf(m, 0.0))
	return "%d:%02d" % [mm, int((maxf(m, 0.0) - mm) * 60.0)]


static func draw_icon(ci: CanvasItem, name: String, center: Vector2, size: int, color: Color) -> void:
	var f := font("icon")
	var ch := icon(name)
	var sz := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	ci.draw_string(f, center + Vector2(-sz.x * 0.5, (asc - desc) * 0.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func draw_text_c(ci: CanvasItem, text: String, center: Vector2, size: int, color: Color, kind := "bold", halo := 0) -> void:
	var f := font(kind)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if halo > 0:
		ci.draw_string_outline(f, center + Vector2(-w * 0.5, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, halo, Color(0.01, 0.04, 0.12, 0.92))
	ci.draw_string(f, center + Vector2(-w * 0.5, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func draw_round_rect(ci: CanvasItem, r: Rect2, color: Color, radius := 4.0, border := Color(0, 0, 0, 0), bw := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	sb.draw(ci.get_canvas_item(), r)


static func draw_chip(ci: CanvasItem, text: String, pos: Vector2, color: Color, size := 12) -> float:
	var f := font("bold")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0
	var h := size + 8.0
	draw_round_rect(ci, Rect2(pos, Vector2(w, h)), with_alpha(color, 0.2), h * 0.5, with_alpha(color, 0.7), 1)
	ci.draw_string(f, pos + Vector2(7, h * 0.5 + size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w


## 尖顶六边形顶点
static func hex_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 6:
		var a := -PI / 2 + TAU * k / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func draw_hex(ci: CanvasItem, c: Vector2, r: float, fill: Color, border := Color(0, 0, 0, 0), bw := 0.0) -> void:
	var pts := hex_points(c, r)
	ci.draw_colored_polygon(pts, fill)
	if bw > 0.0:
		var ol := pts.duplicate()
		ol.append(pts[0])
		ci.draw_polyline(ol, border, bw, true)


## 沿六边形边框绘制进度（0..1，从顶点顺时针）
static func draw_hex_progress(ci: CanvasItem, c: Vector2, r: float, frac: float, color: Color, width := 3.0) -> void:
	var pts := hex_points(c, r)
	var total := 6.0 * frac
	var line := PackedVector2Array([pts[0]])
	for k in 6:
		var seg := clampf(total - k, 0.0, 1.0)
		if seg <= 0.0:
			break
		line.append(pts[k].lerp(pts[(k + 1) % 6], seg))
	if line.size() >= 2:
		ci.draw_polyline(line, color, width, true)
