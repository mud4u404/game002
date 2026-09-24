class_name RecruitPanel
extends Control
## 警力部署：在预算与编制内招募编组。

var game: Game
var _panel: TechPanel
var _cards: Array = []
var _money: Label
var _staff: Label


func _init(p_game: Game) -> void:
	game = p_game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: visible = false)
	add_child(dim)
	_panel = TechPanel.new("警力部署", "FORCE DEPLOYMENT · 招募编组", UIKit.CYAN)
	add_child(_panel)
	var b := _panel.body
	b.add_theme_constant_override("separation", 14)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 28)
	_money = UIKit.label("", 18, UIKit.TEXT, "num_bold")
	_staff = UIKit.label("", 18, UIKit.TEXT, "num_bold")
	info.add_child(UIKit.tag("BUDGET · 可用经费"))
	info.add_child(_money)
	info.add_child(UIKit.tag("QUOTA · 民警编制"))
	info.add_child(_staff)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(sp)
	var close := UIKit.accent_button("关闭  ESC", UIKit.TEXT_DIM, 13)
	close.pressed.connect(func(): visible = false)
	info.add_child(close)
	b.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	b.add_child(row)
	for kind in Data.UNIT_TYPES.keys():
		row.add_child(_make_card(kind))
	var tip := UIKit.label("新编组在所属设施组建后即刻上岗。日维持费按游戏时间持续扣除；每日 00:00 按群众安全感拨付经费。", 13, UIKit.TEXT_DIM)
	b.add_child(tip)


func _make_card(kind: String) -> Control:
	var d: Dictionary = Data.UNIT_TYPES[kind]
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.09, 0.15, 0.95)
	sb.border_color = UIKit.with_alpha(UIKit.CYAN, 0.25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(250, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(0, 70)
	icon.draw.connect(_draw_vehicle.bind(icon, kind))
	v.add_child(icon)
	v.add_child(UIKit.label(d.name, 19, UIKit.TEXT, "bold"))
	v.add_child(UIKit.tag(String(Data.FACILITY_TYPES[d.facility].name) + " · " + d.crew, UIKit.with_alpha(UIKit.CYAN, 0.8), 12))
	var desc := UIKit.label(d.desc, 13, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0, 40)
	v.add_child(desc)
	v.add_child(_stat_row("武力等级", float(d.force) / 4.0, UIKit.RED, "%d" % d.force))
	v.add_child(_stat_row("机动速度", (float(d.speed) - 15.0) / 20.0, UIKit.CYAN, "%d" % int(float(d.speed) * 3.6) + " km/h"))
	var up := HBoxContainer.new()
	up.add_child(UIKit.label("日维持费", 13, UIKit.TEXT_DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up.add_child(sp)
	up.add_child(UIKit.label(Data.money_str(d.upkeep), 14, UIKit.TEXT, "num_bold"))
	v.add_child(up)
	var have := UIKit.label("", 13, UIKit.TEXT_DIM)
	v.add_child(have)
	var btn := UIKit.button("招募  " + Data.money_str(d.cost), 15)
	btn.custom_minimum_size = Vector2(0, 42)
	btn.pressed.connect(func():
		game.recruit(kind)
		_refresh())
	v.add_child(btn)
	_cards.append({"kind": kind, "btn": btn, "have": have})
	return card


func _stat_row(name: String, v: float, c: Color, txt: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UIKit.label(name, 13, UIKit.TEXT_DIM)
	l.custom_minimum_size = Vector2(64, 0)
	h.add_child(l)
	var bar := MeterBar.new(c, 6, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.set_value(v)
	h.add_child(bar)
	var t := UIKit.label(txt, 13, UIKit.TEXT, "num_bold")
	t.custom_minimum_size = Vector2(62, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(t)
	return h


func _draw_vehicle(ci: Control, kind: String) -> void:
	var d: Dictionary = Data.UNIT_TYPES[kind]
	var c := ci.size * 0.5
	var body: Color = d.body
	var stripe: Color = d.stripe
	var L := 120.0
	var H := 40.0
	if kind == "traffic":
		L = 70.0
		H = 22.0
	elif kind == "swat":
		L = 140.0
		H = 50.0
	var r := Rect2(c - Vector2(L, H) * 0.5, Vector2(L, H))
	ci.draw_rect(Rect2(r.position + Vector2(6, 6), r.size), Color(0, 0, 0, 0.4))
	ci.draw_rect(r, body)
	ci.draw_rect(Rect2(r.position.x, c.y - 4, L, 8), stripe)
	if kind != "traffic":
		ci.draw_rect(Rect2(r.position.x + L * 0.28, r.position.y + 5, L * 0.46, H - 10), body.darkened(0.25))
		ci.draw_rect(Rect2(r.position.x + L * 0.3, r.position.y + 7, L * 0.12, H - 14), Color(0.05, 0.07, 0.1))
	var t := Time.get_ticks_msec() / 1000.0
	var on := fmod(t * 2.0, 1.0) < 0.5
	ci.draw_rect(Rect2(c.x - 4, r.position.y + 3, 8, H * 0.5 - 4), UIKit.RED if on else UIKit.RED.darkened(0.6))
	ci.draw_rect(Rect2(c.x - 4, c.y + 1, 8, H * 0.5 - 4), UIKit.BLUE.darkened(0.6) if on else UIKit.BLUE)


func open() -> void:
	visible = true
	_refresh()
	await get_tree().process_frame
	_panel.reset_size()
	_panel.position = (get_viewport_rect().size - _panel.size) * 0.5


func _process(_d: float) -> void:
	if visible:
		_refresh()
		for c in _cards:
			c.btn.get_parent().get_child(0).queue_redraw()


func _refresh() -> void:
	_money.text = Data.money_str(GameState.money)
	_staff.text = "%d / %d" % [GameState.staff_used, GameState.staff_cap]
	for c in _cards:
		var reason := game.can_recruit(c.kind)
		c.btn.disabled = reason != ""
		c.btn.tooltip_text = reason
		var n := 0
		for u in game.units:
			if u.kind == c.kind:
				n += 1
		c.have.text = "现有 %d 组%s" % [n, ("　·　" + reason) if reason != "" else ""]
