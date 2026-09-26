class_name SetupPanel
extends TechPanel
## 班前部署（交接班）：研判今晚警情 → 组建警力 → 划定巡区 → 开始值班。游戏时间冻结。

const W := 360.0

var game: Game
var _rows := {}
var _money: Label
var _zone_label: Label
var _step := {}


func _init(p_game: Game) -> void:
	super._init("班前部署", "assignment", UIKit.ACCENT, false)
	game = p_game
	set_title("班前部署", "17:10 交接班", "assignment")
	var b := body
	b.add_theme_constant_override("separation", 10)

	# ① 研判
	b.add_child(_step_title(1, "研判今晚警情"))
	for line in [["traffic", "17–19 点晚高峰：交通事故、拥堵", "交管"],
			["local_bar", "20 点后夜市：醉酒、打架斗殴", "处突"],
			["forum", "全天：邻里纠纷、走失、盗窃报案", "调解"],
			["swords", "少见但致命：持械、劫持", "突击"]]:
		b.add_child(_intel(line[0], line[1], line[2]))
	var heat := UIKit.label("地图上的橙红色区域是高发片区（老城、滨江夜市）。", 12, UIKit.TEXT_MUTED)
	heat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(heat)

	# ② 组建
	b.add_child(_divider())
	b.add_child(_step_title(2, "组建警力"))
	for kind in Data.UNIT_TYPES.keys():
		b.add_child(_unit_row(kind))
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 6)
	mh.add_child(UIKit.icon_label("payments", 15, UIKit.GREEN))
	_money = UIKit.label("", 13, UIKit.TEXT, "bold")
	mh.add_child(_money)
	b.add_child(mh)

	# ③ 部署
	b.add_child(_divider())
	b.add_child(_step_title(3, "划定巡区"))
	var hint := UIKit.label("点选地图上的警车，再右键路面，它就在那一片巡逻。没划巡区的警力留在驻地待命，出警会慢。", 12, UIKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(hint)
	_zone_label = UIKit.label("", 13, UIKit.TEXT, "bold")
	b.add_child(_zone_label)

	var go := UIKit.accent_button("开始值班", UIKit.ACCENT, 15)
	go.custom_minimum_size.y = 42
	go.pressed.connect(func(): game.start_shift())
	b.add_child(go)


func _step_title(n: int, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(22, 22)
	badge.draw.connect(func():
		var done: bool = _step.get(n, false)
		UIKit.draw_hex(badge, Vector2(11, 11), 11, UIKit.GREEN.darkened(0.3) if done else Color("1d4fb8"), UIKit.CYAN, 1.2)
		if done:
			UIKit.draw_icon(badge, "check_circle", Vector2(11, 11), 14, Color.WHITE)
		else:
			UIKit.draw_text_c(badge, str(n), Vector2(11, 11), 12, Color.WHITE))
	h.add_child(badge)
	var l := UIKit.label(text, 14, UIKit.TEXT, "bold")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	_step[str(n)] = badge
	return h


func _intel(icon_name: String, text: String, skill_name: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(UIKit.icon_label(icon_name, 15, UIKit.AMBER))
	var l := UIKit.label(text, 12, UIKit.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var col := UIKit.TEXT
	for k in Data.SKILLS.keys():
		if Data.SKILLS[k].name == skill_name:
			col = Data.SKILLS[k].color
	h.add_child(UIKit.label(skill_name, 12, col, "bold"))
	return h


func _divider() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.3, 0.6, 1.0, 0.2)
	c.custom_minimum_size = Vector2(0, 1)
	return c


func _unit_row(kind: String) -> Control:
	var d: Dictionary = Data.UNIT_TYPES[kind]
	var sk: Dictionary = Data.SKILLS[d.skill]
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.14, 0.32, 0.6)
	sb.border_color = Color(0.3, 0.6, 1.0, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	pc.add_theme_stylebox_override("panel", sb)
	pc.tooltip_text = d.desc
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	pc.add_child(h)
	var art := Control.new()
	art.custom_minimum_size = Vector2(44, 30)
	art.draw.connect(func():
		var card := Rect2(1, 2, 42, 26)
		UIKit.draw_round_rect(art, card, MarkerLayer.UNIT_FILL.get(kind, UIKit.ACCENT), 3)
		UIKit.draw_round_rect(art, card.grow(-2), Color(0.78, 0.89, 1.0, 0.92), 2)
		VehicleArt.draw(art, kind, card.grow(-3), Color("f4f8ff"), Color("15357a"), -1.0))
	h.add_child(art)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.add_child(UIKit.label(d.short, 13, UIKit.TEXT, "bold"))
	var tag := UIKit.label(sk.name, 11, sk.color, "bold")
	top.add_child(tag)
	v.add_child(top)
	v.add_child(UIKit.label(Data.money_str(d.cost), 11, UIKit.TEXT_MUTED))
	h.add_child(v)
	var minus := UIKit.icon_button("remove", "撤销新组建的一组（退款）", 16)
	minus.pressed.connect(func(): game.disband(kind))
	h.add_child(minus)
	var n := UIKit.label("0", 16, UIKit.TEXT, "bold")
	n.custom_minimum_size = Vector2(22, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(n)
	var plus := UIKit.icon_button("add", "组建一组", 16)
	plus.pressed.connect(func():
		var u := game.recruit(kind)
		if u:
			game.select(u)
		else:
			GameState.advisor.emit(game.can_recruit(kind) + "，无法组建%s。" % d.short))
	h.add_child(plus)
	_rows[kind] = {"n": n, "minus": minus, "plus": plus}
	return pc


func _process(_d: float) -> void:
	if not visible:
		return
	var vs := get_viewport_rect().size
	size = Vector2(W, 0)
	reset_size()
	size.x = W
	position = Vector2(vs.x - W - 14, 72)
	_money.text = "经费 %s　编制 %d/%d" % [Data.money_str(GameState.money), GameState.staff_used, GameState.staff_cap]
	for kind in _rows.keys():
		var r: Dictionary = _rows[kind]
		r.n.text = str(game.units.filter(func(u): return u.kind == kind).size())
		r.minus.disabled = game.bought_count(kind) == 0
		r.minus.modulate.a = 0.35 if r.minus.disabled else 1.0
		var why := game.can_recruit(kind)
		r.plus.tooltip_text = why if why != "" else "组建一组 · " + Data.money_str(Data.UNIT_TYPES[kind].cost)
		r.plus.modulate.a = 0.35 if why != "" else 1.0
	var patrollers := game.units.filter(func(u): return u.info.patrol)
	var zoned := patrollers.filter(func(u): return u.zone_set).size()
	_zone_label.text = "已划巡区 %d / %d 组" % [zoned, patrollers.size()]
	_zone_label.add_theme_color_override("font_color", UIKit.GREEN if zoned > 0 else UIKit.AMBER)
	_set_done(1, true)
	_set_done(2, game.units.any(func(u): return u.bought_in_setup))
	_set_done(3, zoned > 0)


func _set_done(n: int, v: bool) -> void:
	if _step.get(n, false) != v:
		_step[n] = v
		(_step[str(n)] as Control).queue_redraw()
