class_name HUD
extends CanvasLayer
## 指挥大屏 HUD。

const LEFT_W := 380.0
const RIGHT_W := 340.0
const TOP_H := 64.0
const RADIO_KIND := {
	"cmd": Color(0.35, 0.85, 1.0), "unit": Color(0.6, 0.78, 1.0), "call": UIKit.AMBER,
	"good": UIKit.GREEN, "sys": UIKit.TEXT_DIM, "info": Color(0.75, 0.8, 0.86),
	"lv1": Color(0.21, 0.88, 1.0), "lv2": Color(1.0, 0.8, 0.28), "lv3": Color(1.0, 0.52, 0.18), "lv4": Color(1.0, 0.23, 0.31),
}

var game: Game
var root: Control
var markers: MarkerLayer
var call_panel: CallPanel
var recruit_panel: RecruitPanel

var _inc_panel: TechPanel
var _inc_list: VBoxContainer
var _cards := {}
var _unit_panel: TechPanel
var _unit_list: VBoxContainer
var _rows := {}
var _radio: RichTextLabel
var _radio_lines: Array = []
var _ctx: TechPanel
var _ctx_body: VBoxContainer
var _ctx_fields := {}
var _ctx_obj = null
var _clock: Label
var _day: Label
var _money: Label
var _safety: Label
var _opinion: Label
var _staff: Label
var _safety_bar: MeterBar
var _opinion_bar: MeterBar
var _speed_btns: Array = []
var _auto_btn: Button
var _advisor: Control
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

	_build_top_bar()
	_build_incidents()
	_build_units()
	_build_radio()
	_build_context()
	_build_advisor()

	call_panel = CallPanel.new(game)
	root.add_child(call_panel)
	recruit_panel = RecruitPanel.new(game)
	root.add_child(recruit_panel)

	GameState.radio.connect(_on_radio)
	GameState.advisor.connect(_on_advisor)
	GameState.speed_changed.connect(func(_s): _update_speed_btns())
	game.incident_added.connect(_on_inc_added)
	game.incident_removed.connect(_on_inc_removed)
	game.units_changed.connect(_sync_units)
	game.selection_changed.connect(_on_selection)
	_sync_units()
	_on_selection(null)
	_update_speed_btns()


# ------------------------------------------------------------------ 顶栏
func _build_top_bar() -> void:
	var bar := Control.new()
	bar.name = "TopBar"
	bar.position = Vector2.ZERO
	bar.size = Vector2(1920, TOP_H)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.draw.connect(func():
		var w := bar.size.x
		bar.draw_rect(Rect2(0, 0, w, TOP_H), Color(0.01, 0.025, 0.045, 0.94))
		bar.draw_line(Vector2(0, TOP_H), Vector2(w, TOP_H), UIKit.with_alpha(UIKit.CYAN, 0.35), 1.0)
		bar.draw_rect(Rect2(0, TOP_H - 2, 420, 2), UIKit.CYAN)
		_draw_emblem(bar, Vector2(34, TOP_H * 0.5)))
	root.add_child(bar)

	var h := HBoxContainer.new()
	h.name = "Row"
	h.position = Vector2(62, 0)
	h.size = Vector2(1920 - 80, TOP_H)
	h.add_theme_constant_override("separation", 22)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	bar.add_child(h)

	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", -2)
	titles.add_child(UIKit.label("江城市公安局 · 滨江分局", 18, UIKit.TEXT, "bold"))
	titles.add_child(UIKit.tag("JIANGCHENG PSB · COMMAND CENTER 指挥中心", UIKit.with_alpha(UIKit.CYAN, 0.7), 11))
	h.add_child(titles)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)

	# 时钟与倍速
	var clock_box := HBoxContainer.new()
	clock_box.add_theme_constant_override("separation", 12)
	clock_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_theme_constant_override("separation", -6)
	_day = UIKit.tag("DAY 1", UIKit.with_alpha(UIKit.CYAN, 0.8), 12)
	_clock = UIKit.label("19:40", 32, Color.WHITE, "num_bold")
	cv.add_child(_day)
	cv.add_child(_clock)
	clock_box.add_child(cv)
	for s in [0.0, 1.0, 2.0, 4.0]:
		var b := UIKit.button("", 13)
		b.custom_minimum_size = Vector2(44, 32)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.draw.connect(_draw_speed_icon.bind(b, s))
		b.pressed.connect(func(): GameState.set_speed(s))
		b.tooltip_text = ["暂停 (P)", "1× (1)", "2× (2)", "4× (3)"][[0.0, 1.0, 2.0, 4.0].find(s)]
		clock_box.add_child(b)
		_speed_btns.append([b, s])
	h.add_child(clock_box)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp2)

	_money = _stat(h, "经费", "BUDGET")
	var sb: Array = _stat(h, "群众安全感", "SAFETY", true)
	_safety = sb[0]
	_safety_bar = sb[1]
	var ob: Array = _stat(h, "舆情", "OPINION", true)
	_opinion = ob[0]
	_opinion_bar = ob[1]
	_staff = _stat(h, "警力编制", "STAFF")

	_auto_btn = UIKit.button("自动派警  开", 14)
	_auto_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_auto_btn.custom_minimum_size = Vector2(0, 36)
	_auto_btn.tooltip_text = "关闭后，所有警情都需要手动调度"
	_auto_btn.pressed.connect(func():
		GameState.auto_dispatch = not GameState.auto_dispatch
		_auto_btn.text = "自动派警  " + ("开" if GameState.auto_dispatch else "关"))
	h.add_child(_auto_btn)
	var rb := UIKit.accent_button("警力部署  R", UIKit.AMBER, 14)
	rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rb.custom_minimum_size = Vector2(0, 36)
	rb.pressed.connect(toggle_recruit)
	h.add_child(rb)


func _stat(parent: HBoxContainer, name: String, tag: String, with_bar := false):
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 6)
	th.add_child(UIKit.label(name, 12, UIKit.TEXT_DIM))
	th.add_child(UIKit.tag(tag, UIKit.with_alpha(UIKit.CYAN, 0.5), 10))
	v.add_child(th)
	var val := UIKit.label("", 20, Color.WHITE, "num_bold")
	v.add_child(val)
	parent.add_child(v)
	if with_bar:
		var bar := MeterBar.new(UIKit.CYAN, 4, 16)
		bar.custom_minimum_size = Vector2(110, 4)
		v.add_child(bar)
		return [val, bar]
	return val


func _draw_emblem(ci: Control, c: Vector2) -> void:
	var s := 18.0
	var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.85, -s * 0.6), c + Vector2(s * 0.75, s * 0.25),
		c + Vector2(0, s), c + Vector2(-s * 0.75, s * 0.25), c + Vector2(-s * 0.85, -s * 0.6)])
	ci.draw_colored_polygon(pts, Color(0.05, 0.16, 0.4))
	var ol := pts.duplicate()
	ol.append(pts[0])
	ci.draw_polyline(ol, UIKit.CYAN, 2.0, true)
	var f := UIKit.font("num_bold")
	var w := f.get_string_size("110", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	ci.draw_string(f, c + Vector2(-w * 0.5, 5), "110", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func _draw_speed_icon(b: Button, s: float) -> void:
	var active := (GameState.paused and s == 0.0) or (not GameState.paused and s == GameState.speed)
	var col := Color(0.02, 0.06, 0.1) if active else UIKit.TEXT
	var c := b.size * 0.5
	if s == 0.0:
		b.draw_rect(Rect2(c + Vector2(-6, -7), Vector2(4, 14)), col)
		b.draw_rect(Rect2(c + Vector2(2, -7), Vector2(4, 14)), col)
		return
	var n := int(s) if s < 4.0 else 3
	var total := n * 8.0
	for k in n:
		var x := c.x - total * 0.5 + k * 8.0
		b.draw_colored_polygon(PackedVector2Array([Vector2(x, c.y - 7), Vector2(x + 9, c.y), Vector2(x, c.y + 7)]), col)


func _update_speed_btns() -> void:
	for pair in _speed_btns:
		var b: Button = pair[0]
		var s: float = pair[1]
		var active := (GameState.paused and s == 0.0) or (not GameState.paused and s == GameState.speed)
		b.button_pressed = false
		b.add_theme_stylebox_override("normal", UIKit.button_box("pressed" if active else "normal"))
		b.queue_redraw()


# ------------------------------------------------------------------ 左：警情队列
func _build_incidents() -> void:
	_inc_panel = TechPanel.new("警情队列", "INCIDENT QUEUE", UIKit.CYAN)
	_inc_panel.position = Vector2(16, TOP_H + 14)
	_inc_panel.custom_minimum_size = Vector2(LEFT_W, 560)
	root.add_child(_inc_panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 500)
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


# ------------------------------------------------------------------ 右：警力
func _build_units() -> void:
	_unit_panel = TechPanel.new("警力态势", "UNITS", UIKit.CYAN)
	_unit_panel.custom_minimum_size = Vector2(RIGHT_W, 560)
	root.add_child(_unit_panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 500)
	_unit_panel.body.add_child(scroll)
	_unit_list = VBoxContainer.new()
	_unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_unit_list)


func _sync_units() -> void:
	for c in _unit_list.get_children():
		c.queue_free()
	_rows.clear()
	var by_kind := {}
	for u in game.units:
		if not by_kind.has(u.kind):
			by_kind[u.kind] = []
		by_kind[u.kind].append(u)
	for kind in Data.UNIT_TYPES.keys():
		if not by_kind.has(kind):
			continue
		var head := HBoxContainer.new()
		var hl := UIKit.label(Data.UNIT_TYPES[kind].name, 13, UIKit.with_alpha(UIKit.CYAN, 0.85), "bold")
		head.add_child(hl)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(sp)
		head.add_child(UIKit.tag("×%d" % by_kind[kind].size(), UIKit.TEXT_DIM, 12))
		var mc := MarginContainer.new()
		mc.add_theme_constant_override("margin_top", 6)
		mc.add_child(head)
		_unit_list.add_child(mc)
		for u in by_kind[kind]:
			var row := UnitRow.new(u, game)
			row.pressed.connect(func(unit):
				game.select(unit)
				game.cam.focus_on(unit.global_position))
			_unit_list.add_child(row)
			_rows[u] = row


# ------------------------------------------------------------------ 电台
func _build_radio() -> void:
	var p := TechPanel.new("电台", "RADIO · 350MHz 指挥频道", UIKit.CYAN)
	p.custom_minimum_size = Vector2(640, 238)
	p.name = "Radio"
	root.add_child(p)
	_radio = RichTextLabel.new()
	_radio.bbcode_enabled = true
	_radio.scroll_following = true
	_radio.fit_content = false
	_radio.custom_minimum_size = Vector2(0, 176)
	_radio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_radio.add_theme_font_override("normal_font", UIKit.font("reg"))
	_radio.add_theme_font_override("bold_font", UIKit.font("bold"))
	_radio.add_theme_font_override("mono_font", UIKit.font("mono"))
	_radio.add_theme_font_size_override("normal_font_size", 14)
	_radio.add_theme_font_size_override("bold_font_size", 14)
	_radio.add_theme_font_size_override("mono_font_size", 14)
	_radio.add_theme_color_override("default_color", UIKit.TEXT)
	_radio.add_theme_constant_override("line_separation", 5)
	_radio.mouse_filter = Control.MOUSE_FILTER_PASS
	p.body.add_child(_radio)


func _on_radio(e: Dictionary) -> void:
	var c: Color = RADIO_KIND.get(e.kind, UIKit.TEXT)
	var from_c: Color = c if e.kind != "unit" else Color(0.6, 0.78, 1.0)
	var line := "[color=#5d7285][code]%s[/code][/color]  [b][color=#%s]%s[/color][/b]  [color=#%s]%s[/color]" % [
		e.time, from_c.to_html(false), e.from, (c if e.kind.begins_with("lv") or e.kind == "good" else UIKit.TEXT).to_html(false), e.text]
	_radio_lines.append(line)
	if _radio_lines.size() > 80:
		_radio_lines.pop_front()
	_radio.text = "\n".join(_radio_lines)


# ------------------------------------------------------------------ 上下文面板
func _build_context() -> void:
	_ctx = TechPanel.new("值班概况", "OVERVIEW", UIKit.CYAN)
	_ctx.custom_minimum_size = Vector2(460, 238)
	root.add_child(_ctx)
	_ctx_body = _ctx.body


func _on_selection(obj) -> void:
	_ctx_obj = obj
	for c in _ctx_body.get_children():
		c.queue_free()
	_ctx_fields.clear()
	if obj is Incident:
		_ctx._title_label.text = "警情 #%03d" % obj.id
		_ctx._sub_label.text = "INCIDENT DETAIL"
		_ctx_incident(obj)
	elif obj is PoliceUnit:
		_ctx._title_label.text = obj.callsign
		_ctx._sub_label.text = "UNIT DETAIL · " + obj.info.name
		_ctx_unit(obj)
	elif obj is Dictionary:
		_ctx._title_label.text = obj.name
		_ctx._sub_label.text = "FACILITY · " + Data.FACILITY_TYPES[obj.type].name
		_ctx_facility(obj)
	else:
		_ctx._title_label.text = "值班概况"
		_ctx._sub_label.text = "SHIFT OVERVIEW"
		_ctx_overview()
	_refresh_ctx()


func _kv(key: String, id: String, parent: Control = null) -> Label:
	var h := HBoxContainer.new()
	var k := UIKit.label(key, 13, UIKit.TEXT_DIM)
	k.custom_minimum_size = Vector2(84, 0)
	h.add_child(k)
	var v := UIKit.label("", 14, UIKit.TEXT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.clip_text = true
	h.add_child(v)
	(parent if parent else _ctx_body).add_child(h)
	_ctx_fields[id] = v
	return v


func _grid2() -> Array:
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 16)
	var a := VBoxContainer.new()
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(a)
	g.add_child(b)
	_ctx_body.add_child(g)
	return [a, b]


func _ctx_incident(inc: Incident) -> void:
	var t := UIKit.label("", 22, UIKit.TEXT, "bold")
	_ctx_body.add_child(t)
	_ctx_fields["title"] = t
	var loc := UIKit.label(inc.desc(), 13, UIKit.TEXT_DIM)
	_ctx_body.add_child(loc)
	var g := _grid2()
	_kv("状态", "state", g[0])
	_kv("已用时", "elapsed", g[0])
	_kv("需求警力", "need", g[1])
	_kv("升级时限", "deadline", g[1])
	_kv("现场警力", "units")
	var bar := MeterBar.new(UIKit.GREEN, 5, 30)
	bar.custom_minimum_size = Vector2(0, 5)
	_ctx_body.add_child(bar)
	_ctx_fields["bar"] = bar
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	if inc.state == Incident.S.CALL:
		var cb := UIKit.accent_button("接警研判  SPACE", UIKit.AMBER, 14)
		cb.pressed.connect(func(): open_call(inc))
		h.add_child(cb)
	var add := UIKit.button("增派最近单位", 14)
	add.pressed.connect(func():
		var u := game.best_unit(inc, 0)
		if u:
			game.assign(u, inc, true)
		else:
			GameState.post("指挥中心", "暂无可调派的空闲警力。", "info"))
	h.add_child(add)
	var fb := UIKit.accent_button("定位  F", UIKit.TEXT_DIM, 14)
	fb.pressed.connect(func(): game.cam.focus_on(inc.spot.pos, 220))
	h.add_child(fb)
	_ctx_body.add_child(h)


func _ctx_unit(u: PoliceUnit) -> void:
	var g := _grid2()
	_kv("编组", "crew", g[0])
	_kv("带班民警", "leader", g[0])
	_kv("状态", "state", g[0])
	_kv("警衔", "rank", g[1])
	_kv("等级", "level", g[1])
	_kv("武力", "force", g[1])
	_kv("当前任务", "task")
	var fh := HBoxContainer.new()
	fh.add_child(UIKit.label("疲劳度", 13, UIKit.TEXT_DIM))
	var bar := MeterBar.new(UIKit.AMBER, 6, 24)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(bar)
	_ctx_fields["fat"] = bar
	_ctx_body.add_child(fh)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var rb := UIKit.button("返回驻地", 14)
	rb.pressed.connect(func(): game.recall(u))
	h.add_child(rb)
	if u.info.patrol:
		var pb := UIKit.button("恢复巡逻", 14)
		pb.pressed.connect(func(): game.patrol(u))
		h.add_child(pb)
	var fb := UIKit.accent_button("定位  F", UIKit.TEXT_DIM, 14)
	fb.pressed.connect(func(): game.cam.focus_on(u.global_position, 220))
	h.add_child(fb)
	_ctx_body.add_child(h)
	var hint := UIKit.label("右键警情：手动派警　右键路面：机动布控", 12, UIKit.TEXT_DIM)
	_ctx_body.add_child(hint)


func _ctx_facility(f: Dictionary) -> void:
	_kv("驻地警力", "units")
	_kv("车位", "spots")
	var kinds: Array = Data.FACILITY_TYPES[f.type].units
	for kind in kinds:
		var btn := UIKit.accent_button("招募 %s  %s" % [Data.UNIT_TYPES[kind].name, Data.money_str(Data.UNIT_TYPES[kind].cost)], UIKit.AMBER, 14)
		btn.pressed.connect(func():
			game.recruit(kind)
			_refresh_ctx())
		_ctx_body.add_child(btn)
		_ctx_fields["recruit_btn"] = btn
		_ctx_fields["recruit_kind"] = kind


func _ctx_overview() -> void:
	var g := _grid2()
	_kv("接警总数", "total", g[0])
	_kv("已结案", "resolved", g[0])
	_kv("处置失败", "failed", g[0])
	_kv("平均到场", "avg", g[1])
	_kv("圆满处置", "perfect", g[1])
	_kv("研判准确", "calls", g[1])
	var hint := UIKit.label("点击地图上的警情、单位或设施查看详情。滚轮缩放，拖拽平移。", 12, UIKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ctx_body.add_child(hint)


func _setf(id: String, text: String, col := Color(-1, 0, 0)) -> void:
	if _ctx_fields.has(id):
		var l: Label = _ctx_fields[id]
		l.text = text
		if col.r >= 0:
			l.add_theme_color_override("font_color", col)


func _refresh_ctx() -> void:
	var obj = _ctx_obj
	if obj is Incident:
		var inc: Incident = obj
		var col := Data.level_color(inc.level())
		_setf("title", ("110 来电 · 待研判" if inc.state == Incident.S.CALL else inc.title()) + "　L%d %s" % [inc.level(), Data.level_name(inc.level())], col)
		_setf("state", Incident.STATE_NAMES[inc.state] + ("（武力不足）" if inc.stalled else ""), UIKit.RED if inc.stalled else col)
		_setf("elapsed", UIKit.fmt_min(inc.elapsed(GameState.minutes)))
		_setf("need", "%d 组 · 武力 ≥ %d" % [int(inc.data().need), int(inc.data().force)])
		_setf("deadline", UIKit.fmt_min(inc.deadline) if inc.state in [Incident.S.WAITING, Incident.S.DISPATCHED, Incident.S.ONSCENE] else "—")
		var names := []
		for u in inc.units:
			names.append("%s(%s)" % [u.callsign, "到场" if u.state == PoliceUnit.State.ONSCENE else UIKit.fmt_min(u.eta_min)])
		_setf("units", "、".join(names) if not names.is_empty() else "暂无")
		if _ctx_fields.has("bar"):
			_ctx_fields["bar"].set_value(inc.progress)
	elif obj is PoliceUnit:
		var u: PoliceUnit = obj
		_setf("crew", u.info.crew)
		_setf("leader", u.leader)
		_setf("state", u.state_name(), u.state_color())
		_setf("rank", u.rank)
		_setf("level", "Lv.%d" % u.level)
		_setf("force", "%d / 4" % u.force())
		_setf("task", (u.incident.title() + " · " + u.incident.desc()) if u.incident else "—")
		if _ctx_fields.has("fat"):
			_ctx_fields["fat"].set_value(u.fatigue / 100.0, UIKit.GREEN if u.fatigue < 50 else (UIKit.AMBER if u.fatigue < 80 else UIKit.RED))
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
		if _ctx_fields.has("recruit_btn"):
			var reason := game.can_recruit(_ctx_fields["recruit_kind"])
			_ctx_fields["recruit_btn"].disabled = reason != ""
			_ctx_fields["recruit_btn"].tooltip_text = reason
	else:
		var st := GameState.stats
		_setf("total", str(st.total))
		_setf("resolved", str(st.resolved), UIKit.GREEN)
		_setf("failed", str(st.failed), UIKit.RED if st.failed > 0 else UIKit.TEXT)
		_setf("avg", UIKit.fmt_min(GameState.avg_response()) if st.resp_n > 0 else "—")
		_setf("perfect", str(st.perfect))
		_setf("calls", ("%d / %d" % [st.calls_ok, st.calls_total]) if st.calls_total > 0 else "—")


# ------------------------------------------------------------------ 值班长对讲
func _build_advisor() -> void:
	_advisor = Control.new()
	_advisor.custom_minimum_size = Vector2(620, 74)
	_advisor.size = Vector2(620, 74)
	_advisor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_advisor.modulate.a = 0.0
	_advisor.draw.connect(func():
		var r := Rect2(Vector2.ZERO, _advisor.size)
		var pts := UIKit.chamfer_points(r, 12, 0, 12, 0)
		_advisor.draw_colored_polygon(pts, Color(0.06, 0.05, 0.02, 0.92))
		var ol := pts.duplicate()
		ol.append(pts[0])
		_advisor.draw_polyline(ol, UIKit.with_alpha(UIKit.AMBER, 0.5), 1.0, true)
		_advisor.draw_rect(Rect2(0, 12, 3, r.size.y - 24), UIKit.AMBER)
		# 对讲机图标 + 声波
		var c := Vector2(40, r.size.y * 0.5)
		_advisor.draw_rect(Rect2(c + Vector2(-9, -14), Vector2(18, 30)), Color(0.15, 0.12, 0.05))
		_advisor.draw_rect(Rect2(c + Vector2(-9, -14), Vector2(18, 30)), UIKit.AMBER, false, 1.5)
		_advisor.draw_line(c + Vector2(5, -14), c + Vector2(5, -24), UIKit.AMBER, 2.0)
		var t := Time.get_ticks_msec() / 1000.0
		for k in 5:
			var hh := (0.3 + 0.7 * absf(sin(t * 8.0 + k))) * 7.0 * (1.0 if _advisor_text.visible_ratio < 1.0 else 0.25)
			_advisor.draw_rect(Rect2(c.x - 6 + k * 3, c.y + 2 - hh * 0.5, 2, hh), UIKit.AMBER))
	root.add_child(_advisor)
	var name_l := UIKit.label("值班长 · 老周", 13, UIKit.AMBER, "bold")
	name_l.position = Vector2(72, 8)
	_advisor.add_child(name_l)
	_advisor_text = UIKit.label("", 15, UIKit.TEXT)
	_advisor_text.position = Vector2(72, 30)
	_advisor_text.size = Vector2(530, 40)
	_advisor_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_advisor.add_child(_advisor_text)


func _on_advisor(text: String) -> void:
	_advisor_queue.append(text)


func _tick_advisor(delta: float) -> void:
	_advisor.queue_redraw()
	if _advisor_t > 0.0:
		_advisor_t -= delta
		if _advisor_t <= 0.0:
			var tw := create_tween()
			tw.tween_property(_advisor, "modulate:a", 0.0, 0.4)
		return
	if _advisor_queue.is_empty() or _advisor.modulate.a > 0.01:
		return
	var text: String = _advisor_queue.pop_front()
	_advisor_text.text = text
	_advisor_text.visible_ratio = 0.0
	_advisor_t = 3.5 + text.length() * 0.09
	var tw2 := create_tween()
	tw2.tween_property(_advisor, "modulate:a", 1.0, 0.25)
	tw2.parallel().tween_property(_advisor_text, "visible_ratio", 1.0, text.length() * 0.03)


# ------------------------------------------------------------------ 叠加面板
func toggle_recruit() -> void:
	if recruit_panel.visible:
		recruit_panel.visible = false
	elif not call_panel.visible:
		recruit_panel.open()


func close_overlays() -> bool:
	if recruit_panel.visible:
		recruit_panel.visible = false
		return true
	if call_panel.visible:
		call_panel._on_later()
		return true
	return false


# ------------------------------------------------------------------ 布局与刷新
func _layout() -> void:
	var vs := root.get_viewport_rect().size
	var bottom_h := 270.0
	var gap := 16.0
	_inc_panel.position = Vector2(gap, TOP_H + 14)
	_inc_panel.size = Vector2(LEFT_W, vs.y - TOP_H - 14 - bottom_h - gap * 2)
	_unit_panel.position = Vector2(vs.x - RIGHT_W - gap, TOP_H + 14)
	_unit_panel.size = Vector2(RIGHT_W, vs.y - TOP_H - 14 - bottom_h - gap * 2)
	var bar: Control = root.get_node("TopBar")
	bar.size = Vector2(vs.x, TOP_H)
	var row: Control = bar.get_node("Row")
	row.size = Vector2(vs.x - 80, TOP_H)
	var radio: Control = root.get_node("Radio")
	radio.position = Vector2(gap, vs.y - bottom_h - gap)
	radio.size = Vector2(640, bottom_h)
	_ctx.position = Vector2(vs.x - 480 - gap, vs.y - bottom_h - gap)
	_ctx.size = Vector2(480, bottom_h)
	_advisor.position = Vector2((vs.x - _advisor.size.x) * 0.5, TOP_H + 18)


func _process(delta: float) -> void:
	_layout()
	_tick_advisor(delta)
	_clock.text = GameState.clock_str()
	_day.text = "DAY %d · %s" % [GameState.day(), "夜班" if GameState.hour() >= 19 or GameState.hour() < 7 else "日班"]
	_refresh_t -= delta
	if _refresh_t > 0.0:
		return
	_refresh_t = 0.2
	_money.text = Data.money_str(GameState.money)
	_money.add_theme_color_override("font_color", Color.WHITE if GameState.money >= 0 else UIKit.RED)
	_safety.text = "%.1f" % GameState.safety
	_safety_bar.set_value(GameState.safety / 100.0, _metric_color(GameState.safety))
	_opinion.text = "%.1f" % GameState.opinion
	_opinion_bar.set_value(GameState.opinion / 100.0, _metric_color(GameState.opinion))
	_staff.text = "%d / %d" % [GameState.staff_used, GameState.staff_cap]
	var active := 0
	var calls := 0
	for inc in game.incidents:
		if inc.is_active():
			active += 1
			if inc.state == Incident.S.CALL:
				calls += 1
	_inc_panel.set_count(("来电 %d · " % calls if calls > 0 else "") + "%d" % active, UIKit.AMBER if calls > 0 else UIKit.CYAN)
	var avail := 0
	for u in game.units:
		if u.incident == null:
			avail += 1
	_unit_panel.set_count("%d / %d" % [avail, game.units.size()])
	_sort_cards()
	_refresh_ctx()


func _metric_color(v: float) -> Color:
	if v >= 60.0:
		return UIKit.CYAN
	if v >= 40.0:
		return UIKit.AMBER
	return UIKit.RED
