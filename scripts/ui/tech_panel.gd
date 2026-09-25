class_name TechPanel
extends PanelContainer
## 通用面板：圆角深灰底 + 可选标题栏（图标、标题、计数徽标、关闭按钮）。

signal closed

var title := ""
var body: VBoxContainer
var _title_label: Label
var _sub_label: Label
var _icon_label: Label
var _count_label: Label
var _close: Button


func _init(p_title := "", p_icon := "", _accent := UIKit.ACCENT, closable := false) -> void:
	title = p_title
	add_theme_stylebox_override("panel", UIKit.panel_box(3, UIKit.BG, 14, true))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	if title != "":
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		_icon_label = UIKit.icon_label(p_icon if p_icon != "" else "info", 20, UIKit.TEXT_DIM)
		_icon_label.visible = p_icon != ""
		h.add_child(_icon_label)
		_title_label = UIKit.label(title, 14, UIKit.CYAN, "bold")
		h.add_child(_title_label)
		_sub_label = UIKit.label("", 13, UIKit.TEXT_MUTED)
		_sub_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(_sub_label)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(sp)
		_count_label = UIKit.label("", 13, UIKit.TEXT, "bold")
		_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(_count_label)
		if closable:
			_close = UIKit.icon_button("close", "关闭", 18)
			_close.pressed.connect(func(): closed.emit())
			h.add_child(_close)
		v.add_child(h)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)


func set_title(t: String, sub := "", icon_name := "") -> void:
	if _title_label:
		_title_label.text = t
		_sub_label.text = sub
		if icon_name != "":
			_icon_label.text = UIKit.icon(icon_name)
			_icon_label.visible = true


func set_count(t: String, c := Color(-1, 0, 0)) -> void:
	if _count_label:
		_count_label.text = t
		if c.r >= 0:
			_count_label.add_theme_color_override("font_color", c)
