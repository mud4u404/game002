class_name UIKit
extends RefCounted
## 指挥大屏视觉规范：配色、字体、主题、常用控件工厂。

const CYAN := Color(0.21, 0.88, 1.0)
const CYAN_DIM := Color(0.21, 0.88, 1.0, 0.28)
const AMBER := Color(1.0, 0.71, 0.28)
const RED := Color(1.0, 0.23, 0.31)
const BLUE := Color(0.18, 0.42, 1.0)
const GREEN := Color(0.45, 0.95, 0.6)
const TEXT := Color(0.84, 0.9, 0.96)
const TEXT_DIM := Color(0.5, 0.6, 0.7)
const BG := Color(0.015, 0.035, 0.06, 0.86)
const BG_SOFT := Color(0.03, 0.07, 0.11, 0.9)

static var _fonts := {}


static func font(kind := "reg") -> Font:
	if _fonts.is_empty():
		var reg: FontFile = load("res://assets/fonts/NotoSansSC-Regular.ttf")
		var bold: FontFile = load("res://assets/fonts/NotoSansSC-Bold.ttf")
		var num: FontFile = load("res://assets/fonts/Oxanium-Variable.ttf")
		var mono: FontFile = load("res://assets/fonts/ShareTechMono-Regular.ttf")
		for f in [reg, bold, num, mono]:
			f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			f.hinting = TextServer.HINTING_LIGHT
		num.fallbacks = [bold]
		mono.fallbacks = [reg]
		var num_bold := FontVariation.new()
		num_bold.base_font = num
		num_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
		num_bold.fallbacks = [bold]
		_fonts = {"reg": reg, "bold": bold, "num": num, "num_bold": num_bold, "mono": mono}
	return _fonts[kind]


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("reg")
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", button_box(state))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.02, 0.06, 0.1))
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.46, 0.52))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_font("font", "Button", font("bold"))
	t.set_font_size("font_size", "Button", 15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.21, 0.88, 1.0, 0.25)
	sb.content_margin_left = 3
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb)
	var sc := StyleBoxEmpty.new()
	sc.content_margin_left = 3
	t.set_stylebox("scroll", "VScrollBar", sc)
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.02, 0.05, 0.09, 0.95)
	tip.border_color = CYAN_DIM
	tip.set_border_width_all(1)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


static func button_box(state: String, accent := CYAN) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.skew = Vector2(0.22, 0)
	b.set_border_width_all(1)
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	b.anti_aliasing = true
	match state:
		"normal":
			b.bg_color = Color(accent.r, accent.g, accent.b, 0.08)
			b.border_color = Color(accent.r, accent.g, accent.b, 0.45)
		"hover":
			b.bg_color = Color(accent.r, accent.g, accent.b, 0.22)
			b.border_color = accent
		"pressed":
			b.bg_color = accent
			b.border_color = accent
		"disabled":
			b.bg_color = Color(0.2, 0.25, 0.3, 0.12)
			b.border_color = Color(0.4, 0.45, 0.5, 0.3)
		_:
			b.bg_color = Color(0, 0, 0, 0)
			b.border_color = Color(accent.r, accent.g, accent.b, 0.6)
	return b


static func accent_button(text: String, accent: Color, size := 15) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, button_box(state, accent))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_size_override("font_size", size)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn


static func button(text: String, size := 15) -> Button:
	return accent_button(text, CYAN, size)


static func label(text: String, size := 15, color := TEXT, kind := "reg") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 小号英文标签（如 "INCIDENTS"）
static func tag(text: String, color := TEXT_DIM, size := 11) -> Label:
	var l := label(text, size, color, "num")
	return l


## 安全比较（选中对象可能是对象或字典）
static func same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## 绘制切角矩形多边形
static func chamfer_points(r: Rect2, cut_tl := 0.0, cut_tr := 0.0, cut_br := 0.0, cut_bl := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.append(r.position + Vector2(cut_tl, 0))
	p.append(Vector2(r.end.x - cut_tr, r.position.y))
	p.append(Vector2(r.end.x, r.position.y + cut_tr))
	p.append(Vector2(r.end.x, r.end.y - cut_br))
	p.append(Vector2(r.end.x - cut_br, r.end.y))
	p.append(Vector2(r.position.x + cut_bl, r.end.y))
	p.append(Vector2(r.position.x, r.end.y - cut_bl))
	p.append(Vector2(r.position.x, r.position.y + cut_tl))
	return p


static func draw_brackets(ci: CanvasItem, r: Rect2, color: Color, len := 10.0, width := 2.0) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	ci.draw_polyline(PackedVector2Array([a + Vector2(0, len), a, a + Vector2(len, 0)]), color, width)
	ci.draw_polyline(PackedVector2Array([b - Vector2(len, 0), b, b + Vector2(0, len)]), color, width)
	ci.draw_polyline(PackedVector2Array([c - Vector2(0, len), c, c - Vector2(len, 0)]), color, width)
	ci.draw_polyline(PackedVector2Array([d + Vector2(len, 0), d, d - Vector2(0, len)]), color, width)


static func fmt_min(m: float) -> String:
	var mm := int(maxf(m, 0.0))
	return "%d′%02d″" % [mm, int((maxf(m, 0.0) - mm) * 60.0)]
