class_name CallPanel
extends Control
## 110 接警：通话问询 + 警情定性。打开时游戏时间减速。

var game: Game
var inc: Incident
var _panel: PanelContainer
var _transcript: VBoxContainer
var _scroll: ScrollContainer
var _q_box: GridContainer
var _q_left: Label
var _c_box: HBoxContainer
var _timer_label: Label
var _caller_label: Label
var _loc_label: Label
var _hint_label: Label
var _phone: Control
var _avatar: Control
var _t0 := 0.0
var _asked := 0
var _talk := 0.0


func _init(p_game: Game) -> void:
	game = p_game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIKit.panel_box(16, Color(0.075, 0.09, 0.11, 0.98), 20))
	_panel.custom_minimum_size = Vector2(920, 0)
	add_child(_panel)
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 14)
	_panel.add_child(b)

	# 标题栏
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_phone = Control.new()
	_phone.custom_minimum_size = Vector2(44, 44)
	_phone.draw.connect(func():
		var t := Time.get_ticks_msec() / 1000.0
		var ph := fmod(t * 1.2, 1.0)
		_phone.draw_circle(Vector2(22, 22), 22 + ph * 6.0, UIKit.with_alpha(UIKit.RED, 0.3 * (1.0 - ph)))
		_phone.draw_circle(Vector2(22, 22), 22, UIKit.RED)
		UIKit.draw_icon(_phone, "phone_in_talk", Vector2(22, 22), 26, Color.WHITE))
	top.add_child(_phone)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.add_child(UIKit.label("110 报警来电", 20, UIKit.TEXT, "bold"))
	_timer_label = UIKit.label("通话中 00:00", 13, UIKit.RED)
	tv.add_child(_timer_label)
	top.add_child(tv)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var later := UIKit.icon_text_button("call_end", "稍后处理", "secondary")
	later.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	later.pressed.connect(_on_later)
	top.add_child(later)
	b.add_child(top)

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 16)
	b.add_child(mid)

	# 左：报警人信息卡
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_box(12, UIKit.BG2, 14))
	card.custom_minimum_size = Vector2(250, 0)
	mid.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	var av := Control.new()
	av.custom_minimum_size = Vector2(0, 64)
	av.draw.connect(func():
		var c := Vector2(av.size.x * 0.5, 32)
		av.draw_circle(c, 32, UIKit.BG3)
		UIKit.draw_icon(av, "person", c, 40, UIKit.TEXT_DIM)
		# 声波
		var t := Time.get_ticks_msec() / 1000.0
		for s in [-1.0, 1.0]:
			for k in 3:
				var a := (0.35 + 0.65 * absf(sin(t * 7.0 + k * 1.3))) if _talk > 0.0 else 0.25
				av.draw_arc(c, 40.0 + k * 7.0, (PI if s < 0 else 0.0) - 0.5, (PI if s < 0 else 0.0) + 0.5, 12, UIKit.with_alpha(UIKit.RED, a * (1.0 - k * 0.25)), 2.0, true))
	cv.add_child(av)
	_avatar = av
	_caller_label = UIKit.label("", 15, UIKit.TEXT, "bold")
	_caller_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caller_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_caller_label)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 6)
	lh.add_child(UIKit.icon_label("my_location", 16, UIKit.TEXT_MUTED))
	_loc_label = UIKit.label("", 13, UIKit.TEXT_DIM)
	_loc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(_loc_label)
	cv.add_child(lh)
	_hint_label = UIKit.label("", 12, UIKit.TEXT_MUTED)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_hint_label)

	# 右：通话记录（聊天气泡）
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 280)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(_scroll)
	_transcript = VBoxContainer.new()
	_transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_transcript.add_theme_constant_override("separation", 10)
	_scroll.add_child(_transcript)

	# 问询
	var qh := HBoxContainer.new()
	qh.add_child(UIKit.label("问询", 16, UIKit.TEXT, "bold"))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qh.add_child(sp2)
	_q_left = UIKit.label("", 13, UIKit.TEXT_DIM)
	qh.add_child(_q_left)
	b.add_child(qh)
	_q_box = GridContainer.new()
	_q_box.columns = 2
	_q_box.add_theme_constant_override("h_separation", 10)
	_q_box.add_theme_constant_override("v_separation", 8)
	b.add_child(_q_box)

	# 定性
	var ch := HBoxContainer.new()
	ch.add_child(UIKit.label("警情定性", 16, UIKit.TEXT, "bold"))
	var sp3 := Control.new()
	sp3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(sp3)
	ch.add_child(UIKit.label("定性决定出警的警种和数量", 13, UIKit.TEXT_DIM))
	b.add_child(ch)
	_c_box = HBoxContainer.new()
	_c_box.add_theme_constant_override("separation", 10)
	b.add_child(_c_box)


func open(p_inc: Incident) -> void:
	inc = p_inc
	game.begin_call(inc)
	visible = true
	_t0 = Time.get_ticks_msec() / 1000.0
	_asked = inc.asked.size()
	for box in [_transcript, _q_box, _c_box]:
		for c in box.get_children():
			c.queue_free()
	_caller_label.text = inc.call.caller
	_loc_label.text = "基站定位：%s附近，误差约 150 米" % inc.desc()
	_hint_label.text = "系统初判：%s。报警人的描述不一定准确，多问一句，少跑一趟。" % Data.INCIDENTS[inc.call.report].name
	_line("operator", "您好，110。请讲。")
	_line("caller", inc.call.open.replace("{loc}", inc.desc()))
	for idx in inc.asked:
		_line("operator", inc.call.questions[idx].q)
		_line("caller", game.answer_text(inc, idx))
	for i in inc.call.questions.size():
		var q: Dictionary = inc.call.questions[i]
		var btn := UIKit.button(q.q, 14)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(430, 40)
		btn.disabled = i in inc.asked or _asked >= 3
		btn.pressed.connect(_on_ask.bind(i, btn))
		_q_box.add_child(btn)
	var opts: Array = inc.call.options.duplicate()
	if not ("prank" in opts):
		opts.append("prank")
	for o in opts:
		var d: Dictionary = Data.INCIDENTS[o]
		var name: String = d.name if o != "prank" else "恶作剧 / 无效报警"
		var btn := UIKit.icon_text_button(d.gi, name, "secondary", UIKit.ACCENT, 14)
		btn.custom_minimum_size.y = 50
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ic: Label = btn.get_meta("icon")
		ic.add_theme_color_override("font_color", Data.level_color(d.level) if o != "prank" else UIKit.TEXT_DIM)
		btn.tooltip_text = "%s警情 · 需要 %d 组警力 · 武力 ≥ %d" % [Data.level_name(d.level), d.need, d.force] if o != "prank" else "登记备案，不派警"
		btn.pressed.connect(_on_classify.bind(o))
		_c_box.add_child(btn)
	_update_left()
	_center()


func _update_left() -> void:
	_q_left.text = "还可提问 %d 次" % maxi(3 - _asked, 0)


func _center() -> void:
	await get_tree().process_frame
	_panel.reset_size()
	_panel.position = (get_viewport_rect().size - _panel.size) * 0.5


func _line(who: String, text: String) -> void:
	var is_op := who == "operator"
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if is_op else BoxContainer.ALIGNMENT_BEGIN
	var bubble := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("234a91") if is_op else UIKit.BG3
	sb.set_corner_radius_all(12)
	if is_op:
		sb.corner_radius_bottom_right = 3
	else:
		sb.corner_radius_bottom_left = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("panel", sb)
	var l := UIKit.label(text, 15, UIKit.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(text.length() * 15.5 + 4, 440), 0)
	l.visible_ratio = 0.0
	bubble.add_child(l)
	row.add_child(bubble)
	_transcript.add_child(row)
	create_tween().tween_property(l, "visible_ratio", 1.0, clampf(text.length() * 0.03, 0.2, 1.2))
	if not is_op:
		_talk = maxf(_talk, text.length() * 0.03 + 0.4)
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _on_ask(i: int, btn: Button) -> void:
	if _asked >= 3 or not inc.is_active():
		return
	btn.disabled = true
	_asked += 1
	_update_left()
	_line("operator", inc.call.questions[i].q)
	var a := game.ask(inc, i)
	get_tree().create_timer(0.5).timeout.connect(func(): _line("caller", a))
	if _asked >= 3:
		for c in _q_box.get_children():
			c.disabled = true


func _on_classify(type_id: String) -> void:
	visible = false
	game.classify(inc, type_id)
	inc = null


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
	var el := Time.get_ticks_msec() / 1000.0 - _t0
	_timer_label.text = "通话中 %02d:%02d" % [int(el) / 60, int(el) % 60]
	_talk = maxf(_talk - delta, 0.0)
	_phone.queue_redraw()
	_avatar.queue_redraw()
