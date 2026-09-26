class_name RecruitPanel
extends Control
## 招募编组：在经费与编制之内扩充警力。

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
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: visible = false)
	add_child(dim)
	_panel = TechPanel.new("招募编组", "person_add", UIKit.ACCENT, true)
	_panel.closed.connect(func(): visible = false)
	add_child(_panel)
	var b := _panel.body
	b.add_theme_constant_override("separation", 14)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 20)
	info.add_child(UIKit.icon_label("payments", 20, UIKit.GREEN))
	_money = UIKit.label("", 16, UIKit.TEXT, "bold")
	info.add_child(_money)
	info.add_child(UIKit.icon_label("badge", 20, UIKit.TEXT_DIM))
	_staff = UIKit.label("", 16, UIKit.TEXT, "bold")
	info.add_child(_staff)
	b.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	b.add_child(row)
	for kind in Data.UNIT_TYPES.keys():
		row.add_child(_make_card(kind))
	var tip := UIKit.label("新编组在所属设施组建，立即上岗。", 12, UIKit.TEXT_MUTED)
	b.add_child(tip)


func _make_card(kind: String) -> Control:
	var d: Dictionary = Data.UNIT_TYPES[kind]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_box(12, UIKit.BG2, 16))
	card.custom_minimum_size = Vector2(236, 0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(v)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(0, 76)
	icon.draw.connect(func():
		var c := Vector2(icon.size.x * 0.5, 38)
		icon.draw_circle(c, 36, UIKit.with_alpha(UIKit.ACCENT, 0.14))
		UIKit.draw_icon(icon, d.gi, c, 44, UIKit.ACCENT.lightened(0.3)))
	v.add_child(icon)
	var name := UIKit.label(d.name, 18, UIKit.TEXT, "bold")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	var fac := UIKit.label("%s · %s" % [Data.FACILITY_TYPES[d.facility].name, d.crew], 12, UIKit.TEXT_DIM)
	fac.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(fac)
	var desc := UIKit.label(d.desc, 13, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0, 38)
	v.add_child(desc)
	var sk: Dictionary = Data.SKILLS[d.skill]
	var skh := HBoxContainer.new()
	skh.add_theme_constant_override("separation", 6)
	skh.add_child(UIKit.icon_label(sk.gi, 16, sk.color))
	skh.add_child(UIKit.label("专长：" + sk.name, 13, sk.color, "bold"))
	v.add_child(skh)
	v.add_child(_incidents_block(d.skill))
	# spacer 在警情列表下方：吸收各卡警情条数差，让底部按钮贴底对齐
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 0)
	v.add_child(spacer)
	v.add_child(_stat("speed", "速度", (float(d.speed) - 15.0) / 20.0, UIKit.ACCENT, "%d km/h" % int(float(d.speed) * 3.6)))
	var up := HBoxContainer.new()
	up.add_child(UIKit.icon_label("schedule", 16, UIKit.TEXT_MUTED))
	up.add_child(UIKit.label("  日维持费", 13, UIKit.TEXT_DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up.add_child(sp)
	up.add_child(UIKit.label(Data.money_str(d.upkeep), 13, UIKit.TEXT, "bold"))
	v.add_child(up)
	var have := UIKit.label("", 12, UIKit.TEXT_MUTED)
	have.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(have)
	var btn := UIKit.accent_button("招募  " + Data.money_str(d.cost), UIKit.ACCENT, 15)
	btn.custom_minimum_size = Vector2(0, 42)
	btn.pressed.connect(func():
		game.recruit(kind)
		_refresh())
	v.add_child(btn)
	_cards.append({"kind": kind, "btn": btn, "have": have})
	return card


func _incidents_block(skill_id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 6)
	label_row.add_child(UIKit.icon_label("info", 14, UIKit.TEXT_MUTED))
	label_row.add_child(UIKit.label("负责警情", 12, UIKit.TEXT_MUTED, "bold"))
	box.add_child(label_row)
	var matches: Array = []
	for type_id in Data.INCIDENTS.keys():
		if type_id == "prank":
			continue
		var inc: Dictionary = Data.INCIDENTS[type_id]
		var req: Dictionary = inc.get("req", {})
		if req.has(skill_id):
			matches.append({"name": inc.name, "gi": inc.gi})
	var shown := matches.slice(0, 6)
	for m in shown:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.add_child(UIKit.icon_label(m.gi, 12, UIKit.TEXT_DIM))
		row.add_child(UIKit.label(m.name, 11, UIKit.TEXT_DIM))
		box.add_child(row)
	if matches.size() > shown.size():
		var more: int = matches.size() - shown.size()
		var more_row := HBoxContainer.new()
		more_row.add_theme_constant_override("separation", 5)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(12, 0)
		more_row.add_child(pad)
		more_row.add_child(UIKit.label("等 %d 类" % more, 11, UIKit.TEXT_MUTED))
		box.add_child(more_row)
	if matches.is_empty():
		var empty_row := HBoxContainer.new()
		empty_row.add_theme_constant_override("separation", 5)
		empty_row.add_child(UIKit.icon_label("remove", 12, UIKit.TEXT_MUTED))
		empty_row.add_child(UIKit.label("无直接对应警情", 11, UIKit.TEXT_MUTED))
		box.add_child(empty_row)
	return box


func _stat(icon_name: String, name: String, v: float, c: Color, txt: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UIKit.icon_label(icon_name, 16, UIKit.TEXT_MUTED))
	var l := UIKit.label(name, 13, UIKit.TEXT_DIM)
	l.custom_minimum_size = Vector2(34, 0)
	h.add_child(l)
	var bar := MeterBar.new(c, 5, 1)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.set_value(clampf(v, 0.05, 1.0))
	h.add_child(bar)
	var t := UIKit.label(txt, 12, UIKit.TEXT, "bold")
	t.custom_minimum_size = Vector2(64, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(t)
	return h


func open() -> void:
	visible = true
	_refresh()
	await get_tree().process_frame
	_panel.reset_size()
	_panel.position = (get_viewport_rect().size - _panel.size) * 0.5


func _process(_d: float) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	_money.text = Data.money_str(GameState.money)
	_staff.text = "编制 %d / %d" % [GameState.staff_used, GameState.staff_cap]
	for c in _cards:
		var reason := game.can_recruit(c.kind)
		c.btn.disabled = reason != ""
		c.btn.tooltip_text = reason
		var n := 0
		for u in game.units:
			if u.kind == c.kind:
				n += 1
		c.have.text = "现有 %d 组" % n + ("　·　" + reason if reason != "" else "")
