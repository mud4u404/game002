class_name CallPanel
extends Control
## 110 接警对话（参照《112》右侧 DIALOG 面板）：停靠在右侧，不遮挡地图。
## 通话记录 → 问询选项（最多三问）→ 警情定性 → 结束通话。接听时游戏时间减速。

const W := 360.0

var game: Game
var inc: Incident
var _panel: PanelContainer
var _transcript: VBoxContainer
var _scroll: ScrollContainer
var _q_box: VBoxContainer
var _c_box: VBoxContainer
var _timer_label: Label
var _q_title: Label
var _head: Control
var _t0 := 0.0
var _asked := 0
var _talk := 0.0
var _waiting := false


func _init(p_game: Game) -> void:
	game = p_game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIKit.panel_box(6, Color(0.025, 0.065, 0.16, 0.95), 14))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 10)
	_panel.add_child(b)

	# 头部：六边形电话图标 + 计时
	_head = Control.new()
	_head.custom_minimum_size = Vector2(0, 86)
	_head.draw.connect(_draw_head)
	b.add_child(_head)
	_timer_label = UIKit.label("", 12, UIKit.TEXT_DIM)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(_timer_label)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 190)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	b.add_child(_scroll)
	_transcript = VBoxContainer.new()
	_transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_transcript.add_theme_constant_override("separation", 6)
	_scroll.add_child(_transcript)

	b.add_child(_divider())
	_q_title = UIKit.label("", 12, UIKit.TEXT_DIM, "bold")
	b.add_child(_q_title)
	_q_box = VBoxContainer.new()
	_q_box.add_theme_constant_override("separation", 5)
	b.add_child(_q_box)
	b.add_child(_divider())
	b.add_child(UIKit.label("警情定性", 12, UIKit.TEXT_DIM, "bold"))
	_c_box = VBoxContainer.new()
	_c_box.add_theme_constant_override("separation", 5)
	b.add_child(_c_box)
	var later := UIKit.accent_button("挂起 · 稍后处理", UIKit.RED, 13)
	later.custom_minimum_size.y = 36
	later.pressed.connect(_on_later)
	b.add_child(later)


func _divider() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.3, 0.6, 1.0, 0.25)
	c.custom_minimum_size = Vector2(0, 1)
	return c


func _draw_head() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var c := Vector2(_head.size.x * 0.5, 34)
	var ph := fmod(t * 1.1, 1.0)
	UIKit.draw_hex(_head, c, 30 + ph * 10.0, UIKit.with_alpha(UIKit.RED, 0.3 * (1.0 - ph)))
	UIKit.draw_hex(_head, c, 28, Color(0.9, 0.95, 1.0), UIKit.CYAN, 2.0)
	UIKit.draw_hex(_head, c, 23, UIKit.RED.darkened(0.1))
	UIKit.draw_icon(_head, "phone_in_talk", c, 26, Color.WHITE)
	# 声波
	for s in [-1.0, 1.0]:
		for k in 3:
			var a := (0.35 + 0.65 * absf(sin(t * 7.0 + k * 1.3))) if _talk > 0.0 else 0.2
			var base := PI if s < 0 else 0.0
			_head.draw_arc(c, 38.0 + k * 7.0, base - 0.45, base + 0.45, 10, UIKit.with_alpha(UIKit.CYAN, a * (1.0 - k * 0.25)), 2.0, true)
	UIKit.draw_text_c(_head, "110 报警来电", c + Vector2(0, 46), 15, UIKit.TEXT)


func open(p_inc: Incident) -> void:
	inc = p_inc
	game.begin_call(inc)
	visible = true
	_t0 = Time.get_ticks_msec() / 1000.0
	_asked = inc.asked.size()
	_waiting = false
	for box in [_transcript, _q_box, _c_box]:
		for c in box.get_children():
			c.queue_free()
	_line("sys", "%s · 基站定位 %s附近" % [inc.call.caller, inc.desc()])
	_line("operator", "您好，110。请讲。")
	_line("caller", inc.call.open.replace("{loc}", inc.desc()))
	for idx in inc.asked:
		_line("operator", inc.call.questions[idx].q)
		_line("caller", game.answer_text(inc, idx))
	for i in inc.call.questions.size():
		var q: Dictionary = inc.call.questions[i]
		var btn := _option("help", q.q, UIKit.CYAN)
		btn.disabled = i in inc.asked or _asked >= 3
		if btn.disabled:
			btn.modulate.a = 0.4
		btn.pressed.connect(_on_ask.bind(i, btn))
		_q_box.add_child(btn)
	var opts: Array = inc.call.options.duplicate()
	if not ("prank" in opts):
		opts.append("prank")
	for o in opts:
		var d: Dictionary = Data.INCIDENTS[o]
		var name: String = d.name if o != "prank" else "恶作剧 / 无效报警"
		var btn := _option(d.gi, name, Data.level_color(d.level) if o != "prank" else UIKit.TEXT_MUTED)
		btn.tooltip_text = "%s警情 · 出警 %d 组 · 武力 ≥ %d" % [Data.level_name(d.level), d.need, d.force] if o != "prank" else "登记备案，不派警"
		btn.pressed.connect(_on_classify.bind(o))
		_c_box.add_child(btn)
	_update_q()


func _option(icon_name: String, text: String, icon_col: Color) -> Button:
	var btn := UIKit.button("", 13, "secondary")
	btn.custom_minimum_size = Vector2(0, 32)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(UIKit.icon_label(icon_name, 16, icon_col))
	var l := UIKit.label(text, 13, UIKit.TEXT)
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	btn.add_child(h)
	return btn


func _update_q() -> void:
	_q_title.text = "问询（还可提问 %d 次）" % maxi(3 - _asked, 0)


func _line(who: String, text: String) -> void:
	var col := UIKit.TEXT
	var prefix := ""
	match who:
		"operator":
			col = Color("8fc2ff")
			prefix = "接警员："
		"caller":
			col = UIKit.TEXT
			prefix = "报警人："
		_:
			col = UIKit.TEXT_MUTED
	var l := UIKit.label(prefix + text, 13 if who != "sys" else 12, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(W - 44, 0)
	l.visible_ratio = 0.0
	_transcript.add_child(l)
	create_tween().tween_property(l, "visible_ratio", 1.0, clampf(text.length() * 0.03, 0.2, 1.2))
	if who == "caller":
		_talk = maxf(_talk, text.length() * 0.03 + 0.4)
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _on_ask(i: int, btn: Button) -> void:
	if _asked >= 3 or _waiting or not inc.is_active():
		return
	btn.disabled = true
	btn.modulate.a = 0.4
	_asked += 1
	_waiting = true
	_update_q()
	_line("operator", inc.call.questions[i].q)
	var a := game.ask(inc, i)
	get_tree().create_timer(0.6).timeout.connect(func():
		_line("caller", a)
		_waiting = false)
	if _asked >= 3:
		for c in _q_box.get_children():
			c.disabled = true
			c.modulate.a = 0.4


func _on_classify(type_id: String) -> void:
	visible = false
	var target := inc
	game.classify(inc, type_id)
	inc = null
	if target and target.is_active():
		game.select(target)


func _on_later() -> void:
	visible = false
	game.cancel_call()
	inc = null


func _process(delta: float) -> void:
	if not visible:
		return
	if inc != null and not inc.is_active():
		_on_later()
		return
	var vs := get_viewport_rect().size
	_panel.size = Vector2(W, 0)
	_panel.reset_size()
	_panel.size.x = W
	_panel.position = Vector2(vs.x - W - 14, 72)
	var el := Time.get_ticks_msec() / 1000.0 - _t0
	_timer_label.text = "通话中 %02d:%02d · 时间已减速" % [int(el) / 60, int(el) % 60]
	_talk = maxf(_talk - delta, 0.0)
	_head.queue_redraw()
