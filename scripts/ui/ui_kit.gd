class_name UIKit
extends RefCounted
## 界面视觉规范：配色、字体、图标、面板与按钮样式。
## 原则：地图为主、面板克制；纯色深灰面板 + 单一主色（警蓝）；状态色只用于表达状态。

const ACCENT := Color("3d7bff")
const CYAN := ACCENT          # 兼容旧名
const BLUE := ACCENT
const AMBER := Color("ffb020")
const RED := Color("ff4d4f")
const GREEN := Color("35c98a")
const TEXT := Color("e9edf1")
const TEXT_DIM := Color("9ba6b2")
const TEXT_MUTED := Color("6b7682")
const BG := Color(0.082, 0.098, 0.118, 0.95)
const BG2 := Color("1c2128")
const BG3 := Color("262c34")
const LINE := Color("2e353e")
const NAVY := Color("1d3a73")

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
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", button_box(state, "secondary"))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_MUTED)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_font("font", "Button", font("bold"))
	t.set_font_size("font_size", "Button", 14)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.14)
	grab.set_corner_radius_all(3)
	grab.content_margin_left = 4
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	var sc := StyleBoxEmpty.new()
	sc.content_margin_left = 4
	t.set_stylebox("scroll", "VScrollBar", sc)
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color("0f1216")
	tip.set_corner_radius_all(6)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


## 面板底板
static func panel_box(radius := 10, bg := BG, pad := 14) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = LINE
	b.set_border_width_all(1)
	b.set_corner_radius_all(radius)
	b.shadow_color = Color(0, 0, 0, 0.32)
	b.shadow_size = 10
	b.shadow_offset = Vector2(0, 3)
	b.set_content_margin_all(pad)
	b.anti_aliasing = true
	return b


static func button_box(state: String, kind := "secondary", color := ACCENT) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.set_corner_radius_all(7)
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 7
	b.content_margin_bottom = 7
	b.anti_aliasing = true
	match kind:
		"primary":
			b.bg_color = color
			if state == "hover":
				b.bg_color = color.lightened(0.12)
			elif state == "pressed":
				b.bg_color = color.darkened(0.12)
			elif state == "disabled":
				b.bg_color = Color(color.r, color.g, color.b, 0.25)
		"ghost":
			b.bg_color = Color(1, 1, 1, 0.0)
			if state == "hover":
				b.bg_color = Color(1, 1, 1, 0.07)
			elif state == "pressed":
				b.bg_color = Color(1, 1, 1, 0.12)
		"active":
			b.bg_color = ACCENT
		_:
			b.bg_color = BG3
			b.border_color = LINE
			b.set_border_width_all(1)
			if state == "hover":
				b.bg_color = BG3.lightened(0.08)
			elif state == "pressed":
				b.bg_color = BG3.darkened(0.15)
			elif state == "disabled":
				b.bg_color = Color(BG3.r, BG3.g, BG3.b, 0.5)
	if state == "focus":
		b.bg_color = Color(0, 0, 0, 0)
		b.border_color = Color(0, 0, 0, 0)
	return b


static func _style(btn: Button, kind: String, color := ACCENT) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, button_box(state, kind, color))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func button(text: String, size := 14, kind := "secondary") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", size)
	_style(btn, kind)
	return btn


## 实色主按钮（可指定颜色）
static func accent_button(text: String, color := ACCENT, size := 14) -> Button:
	var btn := button(text, size, "primary")
	_style(btn, "primary", color)
	return btn


## 图标 + 文字按钮
static func icon_text_button(icon_name: String, text: String, kind := "secondary", color := ACCENT, size := 14) -> Button:
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
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal")
	btn.custom_minimum_size = Vector2(size + 18, size + 16)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var b: StyleBoxFlat = button_box(state, kind)
		b.content_margin_left = 6
		b.content_margin_right = 6
		b.content_margin_top = 4
		b.content_margin_bottom = 4
		btn.add_theme_stylebox_override(state, b)
	var _unused := sb
	return btn


static func label(text: String, size := 15, color := TEXT, kind := "reg") -> Label:
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


## 兼容旧接口：小号辅助文字
static func tag(text: String, color := TEXT_MUTED, size := 12) -> Label:
	return label(text, size, color)


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


static func fmt_min(m: float) -> String:
	var mm := int(maxf(m, 0.0))
	return "%d:%02d" % [mm, int((maxf(m, 0.0) - mm) * 60.0)]


## 在 CanvasItem 上绘制图标字形（居中）
static func draw_icon(ci: CanvasItem, name: String, center: Vector2, size: int, color: Color) -> void:
	var f := font("icon")
	var ch := icon(name)
	var sz := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	ci.draw_string(f, center + Vector2(-sz.x * 0.5, (asc - desc) * 0.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func draw_text_c(ci: CanvasItem, text: String, center: Vector2, size: int, color: Color, kind := "bold") -> void:
	var f := font(kind)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(f, center + Vector2(-w * 0.5, size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## 圆角矩形（用 StyleBoxFlat 绘制）
static func draw_round_rect(ci: CanvasItem, r: Rect2, color: Color, radius := 6.0, border := Color(0, 0, 0, 0), bw := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.anti_aliasing = true
	sb.draw(ci.get_canvas_item(), r)


## 状态小标签（圆角色块 + 文字），返回宽度
static func draw_chip(ci: CanvasItem, text: String, pos: Vector2, color: Color, size := 12) -> float:
	var f := font("bold")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0
	var h := size + 8.0
	draw_round_rect(ci, Rect2(pos, Vector2(w, h)), with_alpha(color, 0.18), h * 0.5)
	ci.draw_string(f, pos + Vector2(7, h * 0.5 + size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return w
