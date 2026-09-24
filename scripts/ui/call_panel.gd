class_name CallPanel
extends Control
## 110 接警台：通话问询 + 警情定性。打开时游戏时间减速。

var game: Game
var inc: Incident
var _panel: TechPanel
var _transcript: VBoxContainer
var _scroll: ScrollContainer
var _q_box: GridContainer
var _c_box: HBoxContainer
var _timer_label: Label
var _caller_label: Label
var _loc_label: Label
var _hint_label: Label
var _wave: Control
var _talk := 0.0
var _t0 := 0.0
var _asked := 0


func _init(p_game: Game) -> void:
	game = p_game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = TechPanel.new("110 接警台", "EMERGENCY CALL · 通话中", UIKit.AMBER)
	_panel.custom_minimum_size = Vector2(940, 0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_panel)
	var b := _panel.body
	b.add_theme_constant_override("separation", 12)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	b.add_child(top)

	# 左：来电信息
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(270, 0)
	left.add_theme_constant_override("separation", 8)
	top.add_child(left)
	_wave = Control.new()
	_wave.custom_minimum_size = Vector2(270, 70)
	_wave.draw.connect(_draw_wave)
	left.add_child(_wave)
	_timer_label = UIKit.label("通话 00:00", 22, UIKit.AMBER, "num_bold")
	left.add_child(_timer_label)
	left.add_child(UIKit.tag("CALLER · 报警人"))
	_caller_label = UIKit.label("", 15, UIKit.TEXT, "bold")
	_caller_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_caller_label)
	left.add_child(UIKit.tag("LOCATION · 定位"))
	_loc_label = UIKit.label("", 14, UIKit.TEXT_DIM)
	_loc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_loc_label)

	# 右：通话记录
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	right.add_child(UIKit.tag("TRANSCRIPT · 通话记录"))
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 250)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_scroll)
	_transcript = VBoxContainer.new()
	_transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_transcript.add_theme_constant_override("separation", 10)
	_scroll.add_child(_transcript)

	var qh := HBoxContainer.new()
	qh.add_child(UIKit.label("问询", 16, UIKit.TEXT, "bold"))
	qh.add_child(UIKit.tag("  ASK · 最多三问，每一问都在消耗时间"))
	b.add_child(qh)
	_q_box = GridContainer.new()
	_q_box.columns = 2
	_q_box.add_theme_constant_override("h_separation", 12)
	_q_box.add_theme_constant_override("v_separation", 8)
	b.add_child(_q_box)

	var ch := HBoxContainer.new()
	ch.add_child(UIKit.label("警情定性", 16, UIKit.TEXT, "bold"))
	ch.add_child(UIKit.tag("  CLASSIFY · 定性决定派警配置"))
	b.add_child(ch)
	_c_box = HBoxContainer.new()
	_c_box.add_theme_constant_override("separation", 12)
	b.add_child(_c_box)

	var foot := HBoxContainer.new()
	_hint_label = UIKit.label("", 13, UIKit.TEXT_DIM)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_hint_label)
	var later := UIKit.accent_button("稍后处理", UIKit.TEXT_DIM, 14)
	later.pressed.connect(_on_later)
	foot.add_child(later)
	b.add_child(foot)


func open(p_inc: Incident) -> void:
	inc = p_inc
	game.begin_call(inc)
	visible = true
	_t0 = Time.get_ticks_msec() / 1000.0
	_asked = inc.asked.size()
	for c in _transcript.get_children():
		c.queue_free()
	for c in _q_box.get_children():
		c.queue_free()
	for c in _c_box.get_children():
		c.queue_free()
	_caller_label.text = inc.call.caller
	_loc_label.text = "基站定位：%s附近（误差约 150 米）" % inc.desc()
	_hint_label.text = "系统初判：%s　·　定性过轻会导致现场警力不足，过重则挤占其他警情的警力。" % Data.INCIDENTS[inc.call.report].name
	_line("operator", "110，请讲。")
	_line("caller", inc.call.open.replace("{loc}", inc.desc()))
	for idx in inc.asked:
		_line("operator", inc.call.questions[idx].q)
		_line("caller", game.answer_text(inc, idx))
	for i in inc.call.questions.size():
		var q: Dictionary = inc.call.questions[i]
		var btn := UIKit.button("“" + q.q + "”", 14)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(440, 38)
		btn.disabled = i in inc.asked
		btn.pressed.connect(_on_ask.bind(i, btn))
		_q_box.add_child(btn)
	var opts: Array = inc.call.options.duplicate()
	for o in opts:
		var d: Dictionary = Data.INCIDENTS[o]
		var btn := UIKit.accent_button("%s  ·  L%d" % [d.name, d.level], Data.level_color(d.level), 15)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_classify.bind(o))
		_c_box.add_child(btn)
	if not ("prank" in opts):
		var pb := UIKit.accent_button("恶作剧 / 无效报警", UIKit.TEXT_DIM, 15)
		pb.custom_minimum_size = Vector2(0, 44)
		pb.pressed.connect(_on_classify.bind("prank"))
		_c_box.add_child(pb)
	_talk = 1.5
	_center()


func _center() -> void:
	await get_tree().process_frame
	_panel.reset_size()
	var vs := get_viewport_rect().size
	_panel.position = (vs - _panel.size) * 0.5


func _line(who: String, text: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var is_op := who == "operator"
	var name_l := UIKit.label("接警员" if is_op else "报警人", 13, UIKit.CYAN if is_op else UIKit.AMBER, "bold")
	name_l.custom_minimum_size = Vector2(56, 0)
	h.add_child(name_l)
	var body := UIKit.label(text, 16, UIKit.TEXT if not is_op else Color(0.7, 0.85, 0.95))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.visible_ratio = 0.0
	h.add_child(body)
	_transcript.add_child(h)
	var tw := create_tween()
	tw.tween_property(body, "visible_ratio", 1.0, clampf(text.length() * 0.035, 0.25, 1.4))
	if not is_op:
		_talk = maxf(_talk, text.length() * 0.035 + 0.3)
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _on_ask(i: int, btn: Button) -> void:
	if _asked >= 3 or not inc.is_active():
		return
	btn.disabled = true
	_asked += 1
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
	_timer_label.text = "通话 %02d:%02d" % [int(el) / 60, int(el) % 60]
	_talk = maxf(_talk - delta, 0.0)
	_wave.queue_redraw()


func _draw_wave() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var n := 40
	var w := _wave.size.x / n
	var mid := _wave.size.y * 0.5
	var amp := 0.12 + (0.88 if _talk > 0.0 else 0.0)
	for k in n:
		var v := absf(sin(t * 9.0 + k * 0.7) * sin(t * 3.3 + k * 0.23)) * amp
		v = maxf(v, 0.04)
		var h := v * mid * 0.95
		_wave.draw_rect(Rect2(k * w + 1, mid - h, w - 2, h * 2), UIKit.with_alpha(UIKit.AMBER, 0.35 + 0.65 * v))
	_wave.draw_line(Vector2(0, mid), Vector2(_wave.size.x, mid), UIKit.with_alpha(UIKit.AMBER, 0.25), 1.0)
