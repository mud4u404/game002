class_name HUD
extends CanvasLayer
## 游戏界面：地图为主，面板按需出现。
##   左上：分局与时钟、倍速     右上：经费 / 安全感 / 舆情 / 编制
##   左侧：警情列表             右侧：选中对象详情 / 警力列表 / 值班统计（按需）
##   底部：工具栏               左下：电台短讯        底部居中：值班长对话

const GAP := 16.0
const TOP := 16.0
const LEFT_W := 340.0
const RIGHT_W := 360.0
const RADIO_COLORS := {
	"cmd": Color("8fb8ff"), "unit": Color("b9c7d6"), "call": Color("ffb020"),
	"good": Color("35c98a"), "sys": Color("8a96a3"), "info": Color("b9c7d6"),
	"lv1": Color("4ea1ff"), "lv2": Color("ffc53d"), "lv3": Color("ff8a24"), "lv4": Color("ff4d4f"),
}

var game: Game
var root: Control
var markers: MarkerLayer
var call_panel: CallPanel
var recruit_panel: RecruitPanel

var _status: PanelContainer
var _clock: Label
var _day: Label
var _speed_btns: Array = []
var _res: PanelContainer
var _money: Label
var _safety: Label
var _opinion: Label
var _staff: Label
var _safety_bar: MeterBar
var _opinion_bar: MeterBar

var _inc_panel: TechPanel
var _inc_list: VBoxContainer
var _inc_empty: Label
var _cards := {}

var _right: TechPanel
var _right_mode := ""          # select / units / stats
var _right_body: VBoxContainer
var _fields := {}
var _ctx_obj = null

var _dock: PanelContainer
var _dock_btns := {}
var _call_badge: Label

var _ticker: VBoxContainer
var _log_panel: TechPanel
var _log: RichTextLabel
var _log_lines: Array = []
var _recent: Array = []        # [entry, time]

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
	vig.material = vm
	root.add_child(vig)

	_build_status()
	_build_resources()
	_build_incidents()
	_build_right()
	_build_dock()
	_build_radio()
	_build_advisor()
	call_panel = CallPanel.new(game)
	root.add_child(call_panel)
	recruit_panel = RecruitPanel.new(game)
	root.add_child(recruit_panel)

	GameState.radio.connect(_on_radio)
	GameState.advisor.connect(func(t): _advisor_queue.append(t))
	GameState.speed_changed.connect(func(_s): _update_speed_btns())
	game.incident_added.connect(_on_inc_added)
	game.incident_removed.connect(_on_inc_removed)
	game.units_changed.connect(func(): if _right_mode == "units": _show_units())
	game.selection_changed.connect(_on_selection)
	_update_speed_btns()
	_set_right("")


# ================================================================== 左上：分局与时钟
func _build_status() -> void:
	_status = PanelContainer.new()
	_status.add_theme_stylebox_override("panel", UIKit.panel_box(12, UIKit.BG, 10))
	_status.position = Vector2(GAP, TOP)
	root.add_child(_status)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_status.add_child(h)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(40, 40)
	badge.draw.connect(func():
		UIKit.draw_round_rect(badge, Rect2(0, 0, 40, 40), UIKit.NAVY, 9)
		UIKit.draw_icon(badge, "local_police", Vector2(20, 20), 24, Color.WHITE))
	h.add_child(badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -3)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_child(UIKit.label("滨江分局", 16, UIKit.TEXT, "bold"))
	names.add_child(UIKit.label("江城市公安局 · 指挥中心", 11, UIKit.TEXT_MUTED))
	h.add_child(names)
	h.add_child(_vsep())
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -5)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	_clock = UIKit.label("17:10", 24, Color.WHITE, "bold")
	_day = UIKit.label("", 11, UIKit.TEXT_MUTED)
	tv.add_child(_clock)
	tv.add_child(_day)
	h.add_child(tv)
	var sb := HBoxContainer.new()
	sb.add_theme_constant_override("separation", 2)
	sb.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair in [[0.0, "pause", "暂停  P"], [1.0, "play_arrow", "正常速度  1"], [2.0, "fast_forward", "2 倍速  2"], [4.0, "keyboard_double_arrow_right", "4 倍速  3"]]:
		var b := UIKit.icon_button(pair[1], pair[2], 20)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sp: float = pair[0]
		b.pressed.connect(func(): GameState.set_speed(sp))
		sb.add_child(b)
		_speed_btns.append([b, sp])
	h.add_child(sb)


func _vsep() -> Control:
	var c := ColorRect.new()
	c.color = UIKit.LINE
	c.custom_minimum_size = Vector2(1, 30)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _update_speed_btns() -> void:
	for pair in _speed_btns:
		var b: Button = pair[0]
		var s: float = pair[1]
		var active := (GameState.paused and s == 0.0) or (not GameState.paused and s == GameState.speed)
		for state in ["normal", "hover"]:
			var box := UIKit.button_box(state, "active" if active else "ghost")
			box.content_margin_left = 6
			box.content_margin_right = 6
			box.content_margin_top = 4
			box.content_margin_bottom = 4
			b.add_theme_stylebox_override(state, box)


# ================================================================== 右上：资源
func _build_resources() -> void:
	_res = PanelContainer.new()
	_res.add_theme_stylebox_override("panel", UIKit.panel_box(12, UIKit.BG, 10))
	root.add_child(_res)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	_res.add_child(h)
	_money = _res_item(h, "payments", "经费", UIKit.GREEN)[0]
	h.add_child(_vsep())
	var s: Array = _res_item(h, "health_and_safety", "群众安全感", UIKit.ACCENT, true)
	_safety = s[0]
	_safety_bar = s[1]
	h.add_child(_vsep())
	var o: Array = _res_item(h, "campaign", "舆情", UIKit.AMBER, true)
	_opinion = o[0]
	_opinion_bar = o[1]
	h.add_child(_vsep())
	_staff = _res_item(h, "badge", "警力编制", UIKit.TEXT_DIM)[0]


func _res_item(parent: HBoxContainer, icon_name: String, tip: String, col: Color, bar := false) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.tooltip_text = tip
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := UIKit.icon_label(icon_name, 22, col)
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UIKit.label(tip, 11, UIKit.TEXT_MUTED))
	var val := UIKit.label("", 17, Color.WHITE, "bold")
	v.add_child(val)
	var mb: MeterBar = null
	if bar:
		mb = MeterBar.new(col, 3, 1)
		mb.custom_minimum_size = Vector2(84, 3)
		v.add_child(mb)
	h.add_child(v)
	parent.add_child(h)
	return [val, mb]


# ================================================================== 左侧：警情
func _build_incidents() -> void:
	_inc_panel = TechPanel.new("警情", "notifications")
	root.add_child(_inc_panel)
	_inc_empty = UIKit.label("辖区平稳，暂无警情", 13, UIKit.TEXT_MUTED)
	_inc_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inc_panel.body.add_child(_inc_empty)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inc_panel.body.add_child(scroll)
	_inc_list = VBoxContainer.new()
	_inc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inc_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_inc_list)


func _on_inc_added(inc: Incident) -> void:
	var card := IncidentCard.new(inc, game)
	card.pressed.connect(_on_card_pressed)
	_cards[inc] = card
	_inc_list.add_child(card)
	_sort_cards()


func _on_inc_removed(inc: Incident) -> void:
	if _cards.has(inc):
		_cards[inc].queue_free()
		_cards.erase(inc)


func _sort_cards() -> void:
	var list := _cards.keys()
	list.sort_custom(func(a, b):
		var pa: int = (0 if a.state == Incident.S.CALL else 1) if a.is_active() else 3
		var pb: int = (0 if b.state == Incident.S.CALL else 1) if b.is_active() else 3
		if pa != pb:
			return pa < pb
		if a.level() != b.level():
			return a.level() > b.level()
		return a.id < b.id)
	for k in list.size():
		_inc_list.move_child(_cards[list[k]], k)


func _on_card_pressed(inc: Incident) -> void:
	game.select(inc)
	game.cam.focus_on(inc.spot.pos)
	if inc.state == Incident.S.CALL:
		open_call(inc)


func open_call(inc: Incident) -> void:
	recruit_panel.visible = false
	call_panel.open(inc)


# ================================================================== 右侧：详情 / 警力 / 统计
func _build_right() -> void:
	_right = TechPanel.new("详情", "info", UIKit.ACCENT, true)
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


func _row(icon_name: String, key: String, id: String, parent: Control = null) -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UIKit.icon_label(icon_name, 16, UIKit.TEXT_MUTED))
	var k := UIKit.label(key, 13, UIKit.TEXT_DIM)
	k.custom_minimum_size = Vector2(66, 0)
	h.add_child(k)
	var v := UIKit.label("", 13, UIKit.TEXT, "bold")
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(v)
	(parent if parent else _right_body).add_child(h)
	_fields[id] = v
	return v


func _header(icon_name: String, color: Color, title: String, sub: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(48, 48)
	ic.draw.connect(func():
		ic.draw_circle(Vector2(24, 24), 24, UIKit.with_alpha(color, 0.18))
		UIKit.draw_icon(ic, icon_name, Vector2(24, 24), 28, color))
	_fields["hicon"] = ic
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UIKit.label(title, 18, UIKit.TEXT, "bold")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fields["title"] = t
	v.add_child(t)
	var s := UIKit.label(sub, 12, UIKit.TEXT_DIM)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fields["sub"] = s
	v.add_child(s)
	h.add_child(v)
	_right_body.add_child(h)


func _sep() -> void:
	var c := ColorRect.new()
	c.color = UIKit.LINE
	c.custom_minimum_size = Vector2(0, 1)
	_right_body.add_child(c)


func _actions(buttons: Array) -> void:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	_right_body.add_child(g)


func _ctx_incident(inc: Incident) -> void:
	_right.set_title("警情详情", "#%03d" % inc.id, "notifications")
	_header(inc.data().gi, Data.level_color(inc.level()), inc.title(), inc.desc())
	_sep()
	_row("info", "状态", "state")
	_row("schedule", "已用时", "elapsed")
	_row("timer", "升级时限", "deadline")
	_row("groups", "需求警力", "need")
	_row("local_police", "出警单位", "units")
	var bar := MeterBar.new(UIKit.GREEN, 5, 1)
	bar.custom_minimum_size = Vector2(0, 5)
	_right_body.add_child(bar)
	_fields["bar"] = bar
	var btns := []
	if inc.state == Incident.S.CALL:
		var cb := UIKit.icon_text_button("phone_in_talk", "接听来电", "primary", UIKit.RED)
		cb.pressed.connect(func(): open_call(inc))
		btns.append(cb)
	var add := UIKit.icon_text_button("add_circle", "增派警力", "primary")
	add.pressed.connect(func():
		var u := game.best_unit(inc, 0)
		if u:
			game.assign(u, inc, true)
		else:
			GameState.post("指挥中心", "暂无可调派的空闲警力。", "info"))
	btns.append(add)
	var fb := UIKit.icon_text_button("my_location", "定位")
	fb.pressed.connect(func(): game.cam.focus_on(inc.spot.pos, 220))
	btns.append(fb)
	_actions(btns)


func _ctx_unit(u: PoliceUnit) -> void:
	_right.set_title("警力详情", u.info.name, "local_police")
	_header(u.info.gi, u.state_color(), u.callsign, "%s · %s %s" % [u.info.crew, u.rank, u.leader])
	_sep()
	_row("info", "状态", "state")
	_row("assignment", "当前任务", "task")
	_row("trending_up", "等级", "level")
	_row("shield", "武力等级", "force")
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 8)
	fh.add_child(UIKit.icon_label("speed", 16, UIKit.TEXT_MUTED))
	var k := UIKit.label("体力", 13, UIKit.TEXT_DIM)
	k.custom_minimum_size = Vector2(66, 0)
	fh.add_child(k)
	var bar := MeterBar.new(UIKit.GREEN, 6, 1)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(bar)
	_fields["fat"] = bar
	_right_body.add_child(fh)
	var btns := []
	if u.info.patrol:
		var pb := UIKit.icon_text_button("route", "恢复巡逻", "primary")
		pb.pressed.connect(func(): game.patrol(u))
		btns.append(pb)
	var rb := UIKit.icon_text_button("garage_home", "返回驻地")
	rb.pressed.connect(func(): game.recall(u))
	btns.append(rb)
	var fb := UIKit.icon_text_button("my_location", "定位")
	fb.pressed.connect(func(): game.cam.focus_on(u.global_position, 220))
	btns.append(fb)
	_actions(btns)
	var hint := UIKit.label("右键点击警情：手动派警\n右键点击路面：机动布控", 12, UIKit.TEXT_MUTED)
	_right_body.add_child(hint)


func _ctx_facility(f: Dictionary) -> void:
	var ft: Dictionary = Data.FACILITY_TYPES[f.type]
	_right.set_title("设施", ft.name, "apartment")
	_header(ft.gi, UIKit.ACCENT, f.name, "江城市公安局滨江分局")
	_sep()
	_row("groups", "驻地警力", "units")
	_row("local_parking", "车位", "spots")
	for kind in ft.units:
		var d: Dictionary = Data.UNIT_TYPES[kind]
		var btn := UIKit.icon_text_button("person_add", "招募%s  %s" % [d.name, Data.money_str(d.cost)], "primary")
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
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)
	for kind in Data.UNIT_TYPES.keys():
		var group := game.units.filter(func(x): return x.kind == kind)
		if group.is_empty():
			continue
		var head := HBoxContainer.new()
		head.add_child(UIKit.label(Data.UNIT_TYPES[kind].name, 12, UIKit.TEXT_MUTED, "bold"))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(sp)
		head.add_child(UIKit.label("%d" % group.size(), 12, UIKit.TEXT_MUTED))
		list.add_child(head)
		for u in group:
			var row := UnitRow.new(u, game)
			row.pressed.connect(func(unit):
				game.cam.focus_on(unit.global_position)
				game.select(unit))
			list.add_child(row)


func _show_stats() -> void:
	_set_right("stats")
	_right.set_title("值班统计", "第 %d 天" % GameState.day(), "bar_chart")
	_row("notifications", "接警总数", "total")
	_row("check_circle", "已结案", "resolved")
	_row("sentiment_satisfied", "圆满处置", "perfect")
	_row("cancel", "处置失败", "failed")
	_row("timer", "平均到场", "avg")
	_row("phone_in_talk", "研判准确", "calls")
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
		_setf("avg", (UIKit.fmt_min(GameState.avg_response()) + " 分钟") if st.resp_n > 0 else "—")
		_setf("calls", ("%d / %d" % [st.calls_ok, st.calls_total]) if st.calls_total > 0 else "—")
		return
	if _right_mode != "select":
		return
	var obj = _ctx_obj
	if obj is Incident:
		var inc: Incident = obj
		var col := Data.level_color(inc.level())
		_setf("title", ("110 来电 · 待研判" if inc.state == Incident.S.CALL else inc.title()), UIKit.TEXT)
		_setf("sub", "%s · %s警情" % [inc.desc(), Data.level_name(inc.level())])
		if _fields.has("hicon"):
			_fields["hicon"].queue_redraw()
		var st_txt: String = Incident.STATE_NAMES[inc.state]
		if inc.stalled:
			st_txt = "武力不足，请求增援"
		_setf("state", st_txt, UIKit.RED if inc.stalled else col)
		_setf("elapsed", UIKit.fmt_min(inc.elapsed(GameState.minutes)) + " 分钟")
		_setf("deadline", (UIKit.fmt_min(inc.deadline) + " 分钟") if inc.state in [Incident.S.WAITING, Incident.S.DISPATCHED, Incident.S.ONSCENE] else "—")
		_setf("need", "%d 组 · 武力 ≥ %d" % [int(inc.data().need), int(inc.data().force)])
		var names := []
		for u in inc.units:
			names.append("%s（%s）" % [u.callsign, "已到场" if u.state == PoliceUnit.State.ONSCENE else "约 %d 分钟" % ceili(u.eta_min)])
		_setf("units", "、".join(names) if not names.is_empty() else "暂无")
		if _fields.has("bar"):
			_fields["bar"].set_value(inc.progress)
	elif obj is PoliceUnit:
		var u: PoliceUnit = obj
		_setf("state", u.state_name() + ("（轮休）" if u.resting else ""), u.state_color())
		_setf("task", (u.incident.title() + " · " + u.incident.desc()) if u.incident else "—")
		_setf("level", "Lv.%d" % u.level)
		_setf("force", "%d / 4" % u.force())
		if _fields.has("fat"):
			var hp := 1.0 - u.fatigue / 100.0
			_fields["fat"].set_value(hp, UIKit.GREEN if hp > 0.5 else (UIKit.AMBER if hp > 0.2 else UIKit.RED))
	elif obj is Dictionary:
		var n := 0
		var busy := 0
		for u in game.units:
			if u.facility == obj:
				n += 1
				if u.incident != null:
					busy += 1
		_setf("units", "%d 组（出警 %d）" % [n, busy])
		_setf("spots", "%d / %d" % [n, obj.spots.size()])
		if _fields.has("recruit_btn"):
			var reason := game.can_recruit(_fields["recruit_kind"])
			_fields["recruit_btn"].disabled = reason != ""
			_fields["recruit_btn"].tooltip_text = reason


# ================================================================== 底部工具栏
func _build_dock() -> void:
	_dock = PanelContainer.new()
	_dock.add_theme_stylebox_override("panel", UIKit.panel_box(14, UIKit.BG, 8))
	root.add_child(_dock)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	_dock.add_child(h)
	for it in [["call", "phone_in_talk", "接警"], ["units", "groups", "警力"], ["recruit", "person_add", "招募"],
			["facility", "apartment", "设施"], ["stats", "bar_chart", "统计"], ["auto", "route", "自动派警"]]:
		var b := _dock_button(it[1], it[2])
		b.pressed.connect(_on_dock.bind(it[0]))
		h.add_child(b)
		_dock_btns[it[0]] = b
		if it[0] == "call":
			_call_badge = UIKit.label("", 11, Color.WHITE, "bold")
			var bsb := StyleBoxFlat.new()
			bsb.bg_color = UIKit.RED
			bsb.set_corner_radius_all(9)
			_call_badge.add_theme_stylebox_override("normal", bsb)
			_call_badge.position = Vector2(44, 3)
			b.add_child(_call_badge)
		if it[0] == "call":
			h.add_child(_vsep())
	_dock_btns["call"].tooltip_text = "接听 110 来电（空格）"
	_dock_btns["recruit"].tooltip_text = "招募新编组（R）"
	_dock_btns["auto"].tooltip_text = "开启时一般警情由系统自动派警"


func _dock_button(icon_name: String, text: String) -> Button:
	var b := UIKit.button("", 12, "ghost")
	b.custom_minimum_size = Vector2(74, 58)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UIKit.icon_label(icon_name, 24, UIKit.TEXT)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ic)
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.add_child(v)
	b.set_meta("icon", ic)
	b.set_meta("label", l)
	return b


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
			if fs.is_empty():
				return
			var idx := 0
			if game.selected is Dictionary:
				idx = (fs.find(game.selected) + 1) % fs.size()
			game.select(fs[idx])
			game.cam.focus_on(fs[idx].center, 260)
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
	var active := {"units": _right_mode == "units", "stats": _right_mode == "stats", "recruit": recruit_panel != null and recruit_panel.visible,
		"auto": GameState.auto_dispatch, "facility": _right_mode == "select" and game.selected is Dictionary}
	for id in _dock_btns.keys():
		var b: Button = _dock_btns[id]
		var on: bool = active.get(id, false)
		var ic: Label = b.get_meta("icon")
		var l: Label = b.get_meta("label")
		ic.add_theme_color_override("font_color", UIKit.ACCENT.lightened(0.2) if on else UIKit.TEXT)
		l.add_theme_color_override("font_color", UIKit.ACCENT.lightened(0.2) if on else UIKit.TEXT_DIM)


# ================================================================== 电台
func _build_radio() -> void:
	_ticker = VBoxContainer.new()
	_ticker.custom_minimum_size = Vector2(520, 0)
	_ticker.add_theme_constant_override("separation", 4)
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_ticker)
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
	var line := "[color=#6b7682]%s[/color]  [b][color=#%s]%s[/color][/b]  %s" % [e.time, c.to_html(false), e.from, e.text]
	_log_lines.append(line)
	if _log_lines.size() > 120:
		_log_lines.pop_front()
	_log.text = "\n".join(_log_lines)
	_recent.append([e, Time.get_ticks_msec() / 1000.0])
	if _recent.size() > 4:
		_recent.pop_front()
	_rebuild_ticker()


func _rebuild_ticker() -> void:
	for c in _ticker.get_children():
		c.queue_free()
	for pair in _recent:
		var e: Dictionary = pair[0]
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.08, 0.1, 0.78)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 10
		sb.content_margin_right = 12
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		pc.add_theme_stylebox_override("panel", sb)
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var c: Color = RADIO_COLORS.get(e.kind, UIKit.TEXT)
		h.add_child(UIKit.icon_label("radio", 14, c))
		h.add_child(UIKit.label(e.from, 13, c, "bold"))
		var t := UIKit.label(e.text, 13, UIKit.TEXT)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(380, 0)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		pc.add_child(h)
		pc.set_meta("t", pair[1])
		_ticker.add_child(pc)


# ================================================================== 值班长对话
func _build_advisor() -> void:
	_advisor = PanelContainer.new()
	_advisor.add_theme_stylebox_override("panel", UIKit.panel_box(14, UIKit.BG, 12))
	_advisor.modulate.a = 0.0
	_advisor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_advisor)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_advisor.add_child(h)
	var face := Control.new()
	face.custom_minimum_size = Vector2(56, 56)
	face.draw.connect(func():
		face.draw_circle(Vector2(28, 28), 28, UIKit.NAVY)
		face.draw_arc(Vector2(28, 28), 27, 0, TAU, 48, UIKit.AMBER, 2.0, true)
		UIKit.draw_icon(face, "support_agent", Vector2(28, 29), 34, Color.WHITE))
	h.add_child(face)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(UIKit.label("值班长 · 老周", 13, UIKit.AMBER, "bold"))
	_advisor_text = UIKit.label("", 15, UIKit.TEXT)
	_advisor_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_advisor_text.custom_minimum_size = Vector2(460, 0)
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


func toggle_log() -> void:
	_log_panel.visible = not _log_panel.visible


# ================================================================== 布局与刷新
func _layout() -> void:
	var vs := root.get_viewport_rect().size
	_status.position = Vector2(GAP, TOP)
	_res.reset_size()
	_res.position = Vector2(vs.x - _res.size.x - GAP, TOP)
	var top2 := TOP + 76.0
	_dock.reset_size()
	_dock.position = Vector2((vs.x - _dock.size.x) * 0.5, vs.y - _dock.size.y - GAP)
	# 警情列表高度随内容变化
	var want := 56.0 + maxf(_cards.size(), 1) * 76.0
	var max_h := vs.y - top2 - 250.0
	_inc_panel.position = Vector2(GAP, top2)
	_inc_panel.size = Vector2(LEFT_W, clampf(want, 110.0, max_h))
	_right.position = Vector2(vs.x - RIGHT_W - GAP, top2)
	var rh := 0.0
	if _right_mode == "units":
		rh = vs.y - top2 - 110.0
	else:
		_right.size.y = 0
		_right.reset_size()
		rh = _right.size.y
	_right.size = Vector2(RIGHT_W, rh)
	# 电台短讯：左下
	var tw := 520.0
	_ticker.size = Vector2(tw, 0)
	_ticker.reset_size()
	_ticker.position = Vector2(GAP, vs.y - GAP - _ticker.size.y)
	_log_panel.position = Vector2(GAP, vs.y * 0.35)
	_log_panel.size = Vector2(560, vs.y * 0.65 - GAP - 4)
	_advisor.reset_size()
	_advisor.position = Vector2((vs.x - _advisor.size.x) * 0.5, _dock.position.y - _advisor.size.y - 12)


func _process(delta: float) -> void:
	_layout()
	_tick_advisor(delta)
	_clock.text = GameState.clock_str()
	var h := GameState.hour()
	_day.text = "第 %d 天 · %s" % [GameState.day(), "夜间" if h >= 19 or h < 6 else ("清晨" if h < 9 else "白天")]
	# 电台短讯淡出
	var now := Time.get_ticks_msec() / 1000.0
	for c in _ticker.get_children():
		if c.has_meta("t"):
			var age: float = now - c.get_meta("t")
			c.modulate.a = clampf(1.0 - (age - 9.0) / 2.0, 0.0, 1.0)
	_refresh_t -= delta
	if _refresh_t > 0.0:
		return
	_refresh_t = 0.2
	_money.text = Data.money_str(GameState.money)
	_money.add_theme_color_override("font_color", Color.WHITE if GameState.money >= 0 else UIKit.RED)
	_safety.text = "%.0f" % GameState.safety
	_safety_bar.set_value(GameState.safety / 100.0, _metric_color(GameState.safety, UIKit.ACCENT))
	_opinion.text = "%.0f" % GameState.opinion
	_opinion_bar.set_value(GameState.opinion / 100.0, _metric_color(GameState.opinion, UIKit.AMBER))
	_staff.text = "%d / %d" % [GameState.staff_used, GameState.staff_cap]
	var active := 0
	var calls := 0
	for inc in game.incidents:
		if inc.is_active():
			active += 1
			if inc.state == Incident.S.CALL:
				calls += 1
	_inc_panel.set_count("%d" % active if active > 0 else "", UIKit.TEXT_DIM)
	_inc_empty.visible = _cards.is_empty()
	_call_badge.text = " %d " % calls if calls > 0 else ""
	var cb: Button = _dock_btns["call"]
	var ic: Label = cb.get_meta("icon")
	ic.add_theme_color_override("font_color", UIKit.RED if calls > 0 and fmod(now, 1.0) < 0.6 else UIKit.TEXT)
	_sort_cards()
	_refresh_right()


func _metric_color(v: float, base: Color) -> Color:
	if v >= 55.0:
		return base
	if v >= 40.0:
		return UIKit.AMBER
	return UIKit.RED
