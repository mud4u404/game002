class_name HUD
extends CanvasLayer
## 游戏界面（参照《112》布局）：
##   顶部居中：胶囊工具栏（时间 / 消息 / 倍速 / 安全感 / 舆情 / 经费 / 编制）
##   左侧：六边形警情栏        右侧：情况报告 / 接警通话 / 警力 / 统计（按需）
##   底部居中：圆形功能按钮     值班长提示在按钮上方

const RADIO_COLORS := {
	"cmd": Color("8fc2ff"), "unit": Color("b8d4ff"), "call": Color("ffb020"),
	"good": Color("2fe0a0"), "sys": Color("7d9cc9"), "info": Color("b8d4ff"),
	"lv1": Color("5aa8ff"), "lv2": Color("ffc53d"), "lv3": Color("ff8a24"), "lv4": Color("ff3d4a"),
}
const RIGHT_W := 330.0

var game: Game
var root: Control
var markers: MarkerLayer
var call_panel: CallPanel
var recruit_panel: RecruitPanel

var _bar: PanelContainer
var _clock: Label
var _day: Label
var _msg_pill: Button
var _msg_label: Label
var _msg_icon: Label
var _speed_btns: Array = []
var _safety: Label
var _opinion: Label
var _money: Label
var _staff: Label

var _rail: IncidentRail
var _rail_bg: PanelContainer

var _right: TechPanel
var _right_mode := ""
var _right_body: VBoxContainer
var _fields := {}
var _ctx_obj = null

var _dock: HBoxContainer
var _dock_btns := {}

var _log_panel: TechPanel
var _log: RichTextLabel
var _log_lines: Array = []
var _last_msg := {}
var _last_msg_t := -99.0
var _unread := 0

var _advisor: PanelContainer
var _advisor_text: Label
var _advisor_queue: Array = []
var _advisor_t := 0.0
var _refresh_t := 0.0


func setup(p_game: Game) -> void:
	game = p_game
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	markers = MarkerLayer.new()
	markers.game = game
	root.add_child(markers)
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/ui_vignette.gdshader")
	vm.set_shader_parameter("strength", 0.75)
	vig.material = vm
	root.add_child(vig)

	_build_bar()
	_build_rail()
	_build_right()
	_build_dock()
	_build_log()
	_build_advisor()
	call_panel = CallPanel.new(game)
	root.add_child(call_panel)
	recruit_panel = RecruitPanel.new(game)
	root.add_child(recruit_panel)

	GameState.radio.connect(_on_radio)
	GameState.advisor.connect(func(t): _advisor_queue.append(t))
	GameState.speed_changed.connect(func(_s): _update_speed_btns())
	game.units_changed.connect(func(): if _right_mode == "units": _show_units())
	game.selection_changed.connect(_on_selection)
	_update_speed_btns()
	_set_right("")


# ================================================================== 顶部工具栏
func _pill_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.05, 0.12, 0.28, 0.9)
	b.border_color = UIKit.LINE
	b.set_border_width_all(1)
	b.bg_color = Color(0, 0, 0, 0)
	b.border_color = Color(0.25, 0.6, 1.0, 0.9)
	b.set_corner_radius_all(11)
	b.content_margin_left = 8
	b.content_margin_right = 10
	b.content_margin_top = 1
	b.content_margin_bottom = 1
	return b


func _pill(parent: Control, icon_name: String, icon_col: Color, tip: String) -> Label:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _pill_box())
	pc.tooltip_text = tip
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UIKit.icon_label(icon_name, 13, icon_col))
	var l := UIKit.label("", 11, UIKit.TEXT, "bold")
	h.add_child(l)
	pc.add_child(h)
	parent.add_child(pc)
	return l


func _build_bar() -> void:
	_bar = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.16, 0.8)
	sb.border_color = Color(0.16, 0.48, 1.0, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	_bar.add_theme_stylebox_override("panel", sb)
	root.add_child(_bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_bar.add_child(h)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(24, 24)
	badge.draw.connect(func():
		UIKit.draw_hex(badge, Vector2(12, 12), 12, Color("1d4fb8"), UIKit.CYAN, 1.2)
		UIKit.draw_icon(badge, "local_police", Vector2(12, 12), 14, Color.WHITE))
	h.add_child(badge)
	var tv := HBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	_clock = UIKit.label("17:10", 14, Color.WHITE, "bold")
	_day = UIKit.label("", 11, UIKit.TEXT_DIM)
	_day.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_child(_clock)
	tv.add_child(_day)
	h.add_child(tv)
	# 消息胶囊（点击打开电台记录）
	_msg_pill = Button.new()
	_msg_pill.focus_mode = Control.FOCUS_NONE
	_msg_pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_msg_pill.custom_minimum_size = Vector2(260, 22)
	_msg_pill.tooltip_text = "电台记录（L）"
	_msg_pill.pressed.connect(toggle_log)
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 6)
	mh.set_anchors_preset(Control.PRESET_FULL_RECT)
	mh.offset_left = 10
	mh.offset_right = -10
	mh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg_icon = UIKit.icon_label("radio", 14, UIKit.GREEN)
	mh.add_child(_msg_icon)
	_msg_label = UIKit.label("暂无新消息", 11, UIKit.GREEN, "bold")
	_msg_label.clip_text = true
	_msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(_msg_label)
	_msg_pill.add_child(mh)
	h.add_child(_msg_pill)
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 0)
	for pair in [[0.0, "pause", "暂停  P"], [1.0, "play_arrow", "正常  1"], [2.0, "fast_forward", "2 倍速  2"], [4.0, "keyboard_double_arrow_right", "4 倍速  3"]]:
		var b := UIKit.icon_button(pair[1], pair[2], 15)
		b.custom_minimum_size = Vector2(26, 22)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var s: float = pair[0]
		b.pressed.connect(func(): GameState.set_speed(s))
		sp.add_child(b)
		_speed_btns.append([b, s])
	h.add_child(sp)
	_safety = _pill(h, "health_and_safety", UIKit.CYAN, "群众安全感")
	_opinion = _pill(h, "campaign", UIKit.AMBER, "舆情")
	_money = _pill(h, "payments", UIKit.GREEN, "经费")
	_staff = _pill(h, "badge", UIKit.TEXT_DIM, "民警编制")


func _update_speed_btns() -> void:
	for pair in _speed_btns:
		var b: Button = pair[0]
		var s: float = pair[1]
		var active := (GameState.paused and s == 0.0) or (not GameState.paused and s == GameState.speed)
		for state in ["normal", "hover"]:
			var box := UIKit.button_box(state, "active" if active else "ghost")
			box.set_corner_radius_all(12)
			box.content_margin_left = 5
			box.content_margin_right = 5
			box.content_margin_top = 2
			box.content_margin_bottom = 2
			b.add_theme_stylebox_override(state, box)


# ================================================================== 左侧警情栏
func _build_rail() -> void:
	_rail_bg = PanelContainer.new()
	var sb := UIKit.panel_box(8, Color(0.02, 0.06, 0.15, 0.7), 6)
	_rail_bg.add_theme_stylebox_override("panel", sb)
	_rail_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_rail_bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_rail_bg.add_child(v)
	var head := Control.new()
	head.custom_minimum_size = Vector2(64, 26)
	head.draw.connect(func():
		UIKit.draw_icon(head, "notifications", Vector2(22, 13), 16, UIKit.TEXT_DIM)
		var n := 0
		for inc in game.incidents:
			if inc.is_active():
				n += 1
		UIKit.draw_text_c(head, str(n), Vector2(44, 13), 13, UIKit.TEXT))
	v.add_child(head)
	_rail = IncidentRail.new(game)
	v.add_child(_rail)
	_rail_bg.set_meta("head", head)


func _rail_items() -> Array:
	var list := game.incidents.duplicate()
	list.sort_custom(func(a, b):
		var pa: int = (0 if a.state == Incident.S.CALL else 1) if a.is_active() else 3
		var pb: int = (0 if b.state == Incident.S.CALL else 1) if b.is_active() else 3
		if pa != pb:
			return pa < pb
		if a.level() != b.level():
			return a.level() > b.level()
		return a.id < b.id)
	return list.slice(0, 13)


func open_call(inc: Incident) -> void:
	recruit_panel.visible = false
	_set_right("")
	call_panel.open(inc)


# ================================================================== 右侧面板
func _build_right() -> void:
	_right = TechPanel.new("情况报告", "info", UIKit.ACCENT, true)
	_right.closed.connect(func():
		if _right_mode == "select":
			game.select(null)
		_set_right(""))
	root.add_child(_right)
	_right_body = _right.body


func _set_right(mode: String) -> void:
	_right_mode = mode
	_right.visible = mode != ""
	for c in _right_body.get_children():
		c.queue_free()
	_fields.clear()
	_update_dock()


func _on_selection(obj) -> void:
	_ctx_obj = obj
	if call_panel and call_panel.visible:
		return
	if obj == null:
		if _right_mode == "select":
			_set_right("")
		return
	_set_right("select")
	if obj is Incident:
		_ctx_incident(obj)
	elif obj is PoliceUnit:
		_ctx_unit(obj)
	elif obj is Dictionary:
		_ctx_facility(obj)
	_refresh_right()


## 面板顶部：居中的六边形图标 + 标题 + 副标题（参照《112》情况报告）
func _hex_header(icon_name: String, color: Color, title: String, sub: String) -> void:
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(0, 56)
	ic.draw.connect(func():
		var c := Vector2(ic.size.x * 0.5, 28)
		UIKit.draw_hex(ic, c, 27, Color(color.r, color.g, color.b, 0.2))
		UIKit.draw_hex(ic, c, 22, color.darkened(0.2), color.lightened(0.35), 2.0)
		UIKit.draw_icon(ic, icon_name, c, 24, Color.WHITE))
	_fields["hicon"] = ic
	_right_body.add_child(ic)
	var t := UIKit.label(title, 17, UIKit.TEXT, "bold")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fields["title"] = t
	_right_body.add_child(t)
	var s := UIKit.label(sub, 12, UIKit.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fields["sub"] = s
	_right_body.add_child(s)


func _tiles(items: Array) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for it in items:
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.18, 0.4, 0.5)
		sb.border_color = Color(0.3, 0.6, 1.0, 0.3)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(8)
		pc.add_theme_stylebox_override("panel", sb)
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := UIKit.icon_label(it[0], 16, UIKit.TEXT_MUTED)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ic)
		var val := UIKit.label("—", 17, UIKit.TEXT, "bold")
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(val)
		_fields[it[2]] = val
		pc.tooltip_text = it[1]
		pc.add_child(v)
		h.add_child(pc)
	_right_body.add_child(h)


func _bottom_buttons(buttons: Array) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	_right_body.add_child(sp)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	_right_body.add_child(h)


func _ctx_incident(inc: Incident) -> void:
	_right.set_title("情况报告", "", "info")
	_hex_header(inc.data().gi, Data.level_color(inc.level()), inc.title(), inc.desc())
	_right_body.add_child(FlowBar.new(inc))
	_tiles([["schedule", "已用时", "elapsed"], ["timer", "升级时限", "deadline"], ["groups", "出警 / 需求", "need"]])
	var units := HFlowContainer.new()
	units.add_theme_constant_override("h_separation", 6)
	units.add_theme_constant_override("v_separation", 6)
	units.alignment = FlowContainer.ALIGNMENT_CENTER
	_right_body.add_child(units)
	_fields["unit_box"] = units
	_fields["unit_sig"] = "-"
	var btns := []
	if inc.state == Incident.S.CALL:
		var cb := UIKit.accent_button("接听", UIKit.RED, 13)
		cb.custom_minimum_size.y = 34
		cb.pressed.connect(func(): open_call(inc))
		btns.append(cb)
	var add := UIKit.accent_button("增派", UIKit.ACCENT, 13)
	add.custom_minimum_size.y = 34
	add.tooltip_text = "派出最近的可用单位"
	add.pressed.connect(func():
		var u := game.best_unit(inc, 0)
		if u:
			game.assign(u, inc, true)
		else:
			GameState.post("指挥中心", "暂无可调派的空闲警力。", "info"))
	btns.append(add)
	var fb := UIKit.button("定位", 13)
	fb.custom_minimum_size.y = 34
	fb.pressed.connect(func(): game.cam.focus_on(inc.spot.pos, 220))
	btns.append(fb)
	_bottom_buttons(btns)


func _unit_chip(u: PoliceUnit) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(92, 30)
	c.draw.connect(func():
		UIKit.draw_round_rect(c, Rect2(Vector2.ZERO, c.size), Color(0.08, 0.18, 0.4, 0.6), 4, Color(0.3, 0.6, 1.0, 0.35), 1)
		var card := Rect2(3, 3, 36, 24)
		UIKit.draw_round_rect(c, card, MarkerLayer.UNIT_FILL.get(u.kind, UIKit.ACCENT), 3)
		UIKit.draw_round_rect(c, card.grow(-2), Color(0.78, 0.89, 1.0, 0.92), 2)
		VehicleArt.draw(c, u.kind, card.grow(-3), Color("f4f8ff"), Color("15357a"), -1.0)
		var fb := UIKit.font("bold")
		c.draw_string(fb, Vector2(44, 14), u.callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT)
		var eta := "到场" if u.state == PoliceUnit.State.ONSCENE else "%d 分钟" % ceili(u.eta_min)
		c.draw_string(UIKit.font("reg"), Vector2(44, 26), eta, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.GREEN if u.state == PoliceUnit.State.ONSCENE else UIKit.TEXT_DIM))
	return c


func _ctx_unit(u: PoliceUnit) -> void:
	_right.set_title("警力", "", "local_police")
	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 70)
	art.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var card := Rect2(art.size.x * 0.5 - 60, 4, 120, 62)
		UIKit.draw_round_rect(art, card, MarkerLayer.UNIT_FILL.get(u.kind, UIKit.ACCENT), 6, Color(0.8, 0.92, 1.0), 2)
		UIKit.draw_round_rect(art, card.grow(-4), Color(0.78, 0.89, 1.0, 0.95), 4)
		var em := u.state == PoliceUnit.State.ENROUTE or u.state == PoliceUnit.State.ONSCENE
		VehicleArt.draw(art, u.kind, card.grow(-8), Color("f4f8ff"), Color("15357a"), fmod(t * 3.2, 1.0) if em else -1.0))
	_fields["art"] = art
	_right_body.add_child(art)
	var t2 := UIKit.label(u.callsign, 17, UIKit.TEXT, "bold")
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_body.add_child(t2)
	var s := UIKit.label("%s · %s %s" % [u.info.name, u.rank, u.leader], 12, UIKit.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_body.add_child(s)
	_tiles([["info", "状态", "state"], ["shield", "武力等级", "force"], ["speed", "体力", "hp"]])
	var tl := UIKit.label("", 13, UIKit.TEXT_DIM)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fields["task"] = tl
	_right_body.add_child(tl)
	var btns := []
	if u.info.patrol:
		var pb := UIKit.accent_button("巡逻", UIKit.ACCENT, 13)
		pb.custom_minimum_size.y = 34
		pb.pressed.connect(func(): game.patrol(u))
		btns.append(pb)
	var rb := UIKit.button("回所", 13)
	rb.custom_minimum_size.y = 34
	rb.pressed.connect(func(): game.recall(u))
	btns.append(rb)
	var fb := UIKit.button("定位", 13)
	fb.custom_minimum_size.y = 34
	fb.pressed.connect(func(): game.cam.focus_on(u.global_position, 220))
	btns.append(fb)
	_bottom_buttons(btns)


func _ctx_facility(f: Dictionary) -> void:
	var ft: Dictionary = Data.FACILITY_TYPES[f.type]
	_right.set_title("设施", "", "apartment")
	_hex_header(ft.gi, UIKit.ACCENT, f.name, ft.name)
	_tiles([["groups", "驻地警力", "units"], ["local_parking", "车位", "spots"]])
	for kind in ft.units:
		var d: Dictionary = Data.UNIT_TYPES[kind]
		var btn := UIKit.accent_button("招募%s  %s" % [d.name, Data.money_str(d.cost)], UIKit.ACCENT, 13)
		btn.custom_minimum_size.y = 36
		btn.pressed.connect(func():
			game.recruit(kind)
			_refresh_right())
		_right_body.add_child(btn)
		_fields["recruit_btn"] = btn
		_fields["recruit_kind"] = kind


func _show_units() -> void:
	_set_right("units")
	_right.set_title("警力", "%d 组" % game.units.size(), "groups")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for u in game.units:
		var row := UnitRow.new(u, game)
		row.pressed.connect(func(unit):
			game.cam.focus_on(unit.global_position)
			game.select(unit))
		list.add_child(row)


func _show_stats() -> void:
	_set_right("stats")
	_right.set_title("值班统计", "第 %d 天" % GameState.day(), "bar_chart")
	_tiles([["notifications", "接警总数", "total"], ["check_circle", "已结案", "resolved"], ["cancel", "处置失败", "failed"]])
	_tiles([["timer", "平均到场（分钟）", "avg"], ["sentiment_satisfied", "圆满处置", "perfect"], ["phone_in_talk", "研判准确", "calls"]])
	_refresh_right()


func _setf(id: String, text: String, col := Color(-1, 0, 0)) -> void:
	if _fields.has(id) and _fields[id] is Label:
		var l: Label = _fields[id]
		l.text = text
		if col.r >= 0:
			l.add_theme_color_override("font_color", col)


func _refresh_right() -> void:
	if _right_mode == "stats":
		var st := GameState.stats
		_setf("total", str(st.total))
		_setf("resolved", str(st.resolved), UIKit.GREEN)
		_setf("perfect", str(st.perfect))
		_setf("failed", str(st.failed), UIKit.RED if st.failed > 0 else UIKit.TEXT)
		_setf("avg", UIKit.fmt_min(GameState.avg_response()) if st.resp_n > 0 else "—")
		_setf("calls", ("%d/%d" % [st.calls_ok, st.calls_total]) if st.calls_total > 0 else "—")
		return
	if _right_mode != "select":
		return
	var obj = _ctx_obj
	if obj is Incident:
		var inc: Incident = obj
		_setf("title", ("110 来电" if inc.state == Incident.S.CALL else inc.title()))
		_setf("sub", inc.desc())
		if _fields.has("hicon"):
			_fields["hicon"].queue_redraw()
		_setf("elapsed", UIKit.fmt_min(inc.elapsed(GameState.minutes)))
		var live := inc.state in [Incident.S.WAITING, Incident.S.DISPATCHED, Incident.S.ONSCENE]
		_setf("deadline", UIKit.fmt_min(inc.deadline) if live else "—", UIKit.RED if live and inc.deadline < 5.0 else UIKit.TEXT)
		_setf("need", "%d/%d" % [inc.units.size(), int(inc.data().need)], UIKit.RED if inc.stalled else UIKit.TEXT)
		var sig := ""
		for u in inc.units:
			sig += "%d:%d:%d," % [u.uid, u.state, ceili(u.eta_min)]
		if _fields.has("unit_box") and sig != _fields["unit_sig"]:
			_fields["unit_sig"] = sig
			var box: Control = _fields["unit_box"]
			for c in box.get_children():
				c.queue_free()
			for u in inc.units:
				box.add_child(_unit_chip(u))
	elif obj is PoliceUnit:
		var u: PoliceUnit = obj
		_setf("state", u.state_name() if not u.resting else "轮休", u.state_color())
		_setf("force", "%d/4" % u.force())
		var hp := int(100.0 - u.fatigue)
		_setf("hp", "%d%%" % hp, UIKit.GREEN if hp > 50 else (UIKit.AMBER if hp > 20 else UIKit.RED))
		_setf("task", (u.incident.title() + " · " + u.incident.desc()) if u.incident else "暂无任务")
		if _fields.has("art"):
			_fields["art"].queue_redraw()
	elif obj is Dictionary:
		var n := 0
		var busy := 0
		for u in game.units:
			if u.facility == obj:
				n += 1
				if u.incident != null:
					busy += 1
		_setf("units", "%d（出警 %d）" % [n, busy])
		_setf("spots", "%d/%d" % [n, obj.spots.size()])
		if _fields.has("recruit_btn"):
			var reason := game.can_recruit(_fields["recruit_kind"])
			_fields["recruit_btn"].disabled = reason != ""
			_fields["recruit_btn"].tooltip_text = reason


# ================================================================== 底部圆形按钮
func _build_dock() -> void:
	_dock = HBoxContainer.new()
	_dock.add_theme_constant_override("separation", 8)
	root.add_child(_dock)
	for it in [["call", "phone_in_talk", "来电"], ["incident", "notifications", "警情"], ["units", "groups", "警力"],
			["recruit", "person_add", "招募"], ["facility", "apartment", "设施"], ["stats", "bar_chart", "统计"], ["auto", "route", "自动派警"]]:
		var b := _round_button(it[0], it[1], it[2])
		_dock.add_child(b)
		_dock_btns[it[0]] = b


func _round_button(id: String, icon_name: String, text: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(46, 54)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.set_meta("hover", false)
	c.mouse_entered.connect(func(): c.set_meta("hover", true))
	c.mouse_exited.connect(func(): c.set_meta("hover", false))
	c.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_on_dock(id))
	c.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var ctr := Vector2(23, 19)
		var on: bool = c.get_meta("on", false)
		var hv: bool = c.get_meta("hover")
		var badge: int = c.get_meta("badge", 0)
		var alert := id == "call" and badge > 0
		var ring := UIKit.CYAN if (on or hv) else UIKit.LINE
		var fill := Color(0.05, 0.12, 0.28, 0.92)
		if alert:
			var ph := fmod(t * 1.2, 1.0)
			c.draw_circle(ctr, 17 + ph * 7.0, UIKit.with_alpha(UIKit.RED, 0.35 * (1.0 - ph)))
			fill = UIKit.RED.darkened(0.2)
			ring = UIKit.RED.lightened(0.3)
		elif on:
			fill = Color(0.12, 0.32, 0.75, 0.95)
		c.draw_circle(ctr, 17, fill)
		c.draw_arc(ctr, 17, 0, TAU, 40, ring, 1.5, true)
		UIKit.draw_icon(c, icon_name, ctr, 18, Color.WHITE if (on or hv or alert) else UIKit.TEXT_DIM)
		UIKit.draw_text_c(c, text, Vector2(23, 46), 10, UIKit.TEXT if (on or hv) else UIKit.TEXT_DIM, "reg")
		if badge > 0:
			var bc := ctr + Vector2(13, -13)
			c.draw_circle(bc, 7.5, UIKit.RED if id == "call" else UIKit.AMBER)
			UIKit.draw_text_c(c, str(badge), bc, 10, Color.WHITE))
	return c


func _on_dock(id: String) -> void:
	match id:
		"call":
			for inc in game.incidents:
				if inc.state == Incident.S.CALL:
					game.select(inc)
					game.cam.focus_on(inc.spot.pos)
					open_call(inc)
					return
			GameState.advisor.emit("现在没有待接的来电。")
		"incident":
			var list := _rail_items().filter(func(i): return i.is_active() and i.state != Incident.S.CALL)
			if list.is_empty():
				GameState.advisor.emit("辖区目前平稳，没有待处置的警情。")
				return
			var idx := 0
			if game.selected is Incident and game.selected in list:
				idx = (list.find(game.selected) + 1) % list.size()
			game.select(list[idx])
			game.cam.focus_on(list[idx].spot.pos, 300)
		"units":
			if _right_mode == "units":
				_set_right("")
			else:
				game.select(null)
				_show_units()
		"recruit":
			toggle_recruit()
		"facility":
			var fs: Array = game.city.facilities
			var idx := 0
			if game.selected is Dictionary:
				idx = (fs.find(game.selected) + 1) % fs.size()
			game.select(fs[idx])
			game.cam.focus_on(fs[idx].center, 300)
		"stats":
			if _right_mode == "stats":
				_set_right("")
			else:
				game.select(null)
				_show_stats()
		"auto":
			GameState.auto_dispatch = not GameState.auto_dispatch
			GameState.post("指挥中心", "自动派警已" + ("开启。" if GameState.auto_dispatch else "关闭，所有警情需手动调度。"), "sys")
	_update_dock()


func _update_dock() -> void:
	if _dock_btns.is_empty():
		return
	var on := {"units": _right_mode == "units", "stats": _right_mode == "stats", "recruit": recruit_panel != null and recruit_panel.visible,
		"auto": GameState.auto_dispatch, "facility": _right_mode == "select" and game.selected is Dictionary,
		"incident": _right_mode == "select" and game.selected is Incident}
	for id in _dock_btns.keys():
		_dock_btns[id].set_meta("on", on.get(id, false))


# ================================================================== 电台记录
func _build_log() -> void:
	_log_panel = TechPanel.new("电台记录", "radio", UIKit.ACCENT, true)
	_log_panel.visible = false
	_log_panel.closed.connect(func(): _log_panel.visible = false)
	root.add_child(_log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_override("normal_font", UIKit.font("reg"))
	_log.add_theme_font_override("bold_font", UIKit.font("bold"))
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_font_size_override("bold_font_size", 13)
	_log.add_theme_constant_override("line_separation", 6)
	_log_panel.body.add_child(_log)


func _on_radio(e: Dictionary) -> void:
	var c: Color = RADIO_COLORS.get(e.kind, UIKit.TEXT)
	_log_lines.append("[color=#6582ad]%s[/color]  [b][color=#%s]%s[/color][/b]  %s" % [e.time, c.to_html(false), e.from, e.text])
	if _log_lines.size() > 150:
		_log_lines.pop_front()
	_log.text = "\n".join(_log_lines)
	_last_msg = e
	_last_msg_t = Time.get_ticks_msec() / 1000.0
	if not _log_panel.visible:
		_unread += 1


func toggle_log() -> void:
	_log_panel.visible = not _log_panel.visible
	if _log_panel.visible:
		_unread = 0


# ================================================================== 值班长
func _build_advisor() -> void:
	_advisor = PanelContainer.new()
	_advisor.add_theme_stylebox_override("panel", UIKit.panel_box(8, UIKit.BG, 10))
	_advisor.modulate.a = 0.0
	_advisor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_advisor)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_advisor.add_child(h)
	var face := Control.new()
	face.custom_minimum_size = Vector2(44, 44)
	face.draw.connect(func():
		UIKit.draw_hex(face, Vector2(22, 22), 21, Color("1d4fb8"), UIKit.AMBER, 1.5)
		UIKit.draw_icon(face, "support_agent", Vector2(22, 23), 26, Color.WHITE))
	h.add_child(face)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UIKit.label("值班长 老周", 12, UIKit.AMBER, "bold"))
	_advisor_text = UIKit.label("", 14, UIKit.TEXT)
	_advisor_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_advisor_text.custom_minimum_size = Vector2(420, 0)
	v.add_child(_advisor_text)
	h.add_child(v)


func _tick_advisor(delta: float) -> void:
	if _advisor_t > 0.0:
		_advisor_t -= delta
		if _advisor_t <= 0.0:
			create_tween().tween_property(_advisor, "modulate:a", 0.0, 0.35)
		return
	if _advisor_queue.is_empty() or _advisor.modulate.a > 0.01:
		return
	var text: String = _advisor_queue.pop_front()
	_advisor_text.text = text
	_advisor_text.visible_ratio = 0.0
	_advisor_t = 3.5 + text.length() * 0.09
	var tw := create_tween()
	tw.tween_property(_advisor, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_advisor_text, "visible_ratio", 1.0, text.length() * 0.025)


# ================================================================== 叠加面板
func toggle_recruit() -> void:
	if recruit_panel.visible:
		recruit_panel.visible = false
	elif not call_panel.visible:
		recruit_panel.open()
	_update_dock()


func close_overlays() -> bool:
	if recruit_panel.visible:
		recruit_panel.visible = false
		_update_dock()
		return true
	if call_panel.visible:
		call_panel._on_later()
		return true
	if _log_panel.visible:
		_log_panel.visible = false
		return true
	if _right_mode in ["units", "stats"]:
		_set_right("")
		return true
	return false


# ================================================================== 布局与刷新
func _layout() -> void:
	var vs := root.get_viewport_rect().size
	_bar.reset_size()
	_bar.position = Vector2((vs.x - _bar.size.x) * 0.5, 14)
	var top := 14.0 + _bar.size.y + 12.0
	_rail.set_items(_rail_items())
	_rail_bg.reset_size()
	_rail_bg.position = Vector2(14, top)
	(_rail_bg.get_meta("head") as Control).queue_redraw()
	_right.position = Vector2(vs.x - RIGHT_W - 14, top)
	if _right_mode == "units":
		_right.size = Vector2(RIGHT_W, vs.y - top - 120)
	else:
		_right.size = Vector2(RIGHT_W, 0)
		_right.reset_size()
		_right.size.x = RIGHT_W
	_dock.reset_size()
	_dock.position = Vector2((vs.x - _dock.size.x) * 0.5, vs.y - _dock.size.y - 10)
	_log_panel.position = Vector2(vs.x * 0.5 - 300, top)
	_log_panel.size = Vector2(600, vs.y * 0.55)
	_advisor.reset_size()
	_advisor.position = Vector2((vs.x - _advisor.size.x) * 0.5, _dock.position.y - _advisor.size.y - 10)
	for id in _dock_btns.keys():
		_dock_btns[id].queue_redraw()


func _process(delta: float) -> void:
	_layout()
	_tick_advisor(delta)
	_clock.text = GameState.clock_str()
	var h := GameState.hour()
	_day.text = "第 %d 天 · %s" % [GameState.day(), "夜间" if h >= 19 or h < 6 else "白天"]
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_msg_t < 6.0 and not _last_msg.is_empty():
		var c: Color = RADIO_COLORS.get(_last_msg.kind, UIKit.TEXT)
		_msg_label.text = "%s：%s" % [_last_msg.from, _last_msg.text]
		_msg_label.add_theme_color_override("font_color", c)
		_msg_icon.add_theme_color_override("font_color", c)
	else:
		var has := _unread > 0
		_msg_label.text = ("%d 条新消息" % _unread) if has else "暂无新消息"
		var cc := UIKit.AMBER if has else UIKit.GREEN
		_msg_label.add_theme_color_override("font_color", cc)
		_msg_icon.add_theme_color_override("font_color", cc)
	var mb := StyleBoxFlat.new()
	mb.bg_color = Color(0.04, 0.35, 0.22, 0.85) if _unread == 0 else Color(0.4, 0.26, 0.04, 0.85)
	mb.border_color = UIKit.with_alpha(UIKit.GREEN if _unread == 0 else UIKit.AMBER, 0.6)
	mb.set_border_width_all(1)
	mb.set_corner_radius_all(11)
	for st in ["normal", "hover", "pressed"]:
		_msg_pill.add_theme_stylebox_override(st, mb)
	_refresh_t -= delta
	if _refresh_t > 0.0:
		return
	_refresh_t = 0.2
	_safety.text = "安全感 %.0f" % GameState.safety
	_safety.add_theme_color_override("font_color", _metric_color(GameState.safety))
	_opinion.text = "舆情 %.0f" % GameState.opinion
	_opinion.add_theme_color_override("font_color", _metric_color(GameState.opinion))
	_money.text = Data.money_str(GameState.money)
	_money.add_theme_color_override("font_color", UIKit.TEXT if GameState.money >= 0 else UIKit.RED)
	_staff.text = "%d/%d" % [GameState.staff_used, GameState.staff_cap]
	var calls := 0
	var active := 0
	for inc in game.incidents:
		if inc.is_active():
			active += 1
			if inc.state == Incident.S.CALL:
				calls += 1
	_dock_btns["call"].set_meta("badge", calls)
	_dock_btns["incident"].set_meta("badge", active - calls)
	_refresh_right()


func _metric_color(v: float) -> Color:
	if v >= 55.0:
		return UIKit.TEXT
	if v >= 40.0:
		return UIKit.AMBER
	return UIKit.RED
