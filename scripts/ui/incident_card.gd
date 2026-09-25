class_name IncidentCard
extends Control
## 警情卡片：图标 + 倒计时环 + 短标题 + 出警单位小图标。文字只保留最必要的信息。

signal pressed(inc: Incident)

var inc: Incident
var game: Game
var _hover := false
var _born := 0.0


func _init(p_inc: Incident, p_game: Game) -> void:
	inc = p_inc
	game = p_game
	custom_minimum_size = Vector2(0, 60)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_born = Time.get_ticks_msec() / 1000.0
	mouse_entered.connect(func(): _hover = true)
	mouse_exited.connect(func(): _hover = false)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(inc)
		accept_event()


func _process(_d: float) -> void:
	tooltip_text = inc.desc()
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var col := Data.level_color(inc.level())
	var calling := inc.state == Incident.S.CALL
	var done := not inc.is_active()
	if done:
		col = UIKit.GREEN if inc.state == Incident.S.DONE else UIKit.TEXT_MUTED
	if calling:
		col = UIKit.RED
	var sel: bool = UIKit.same(game.selected, inc)
	var bg := Color(1, 1, 1, 0.0)
	if _hover or sel:
		bg = Color(1, 1, 1, 0.06)
	UIKit.draw_round_rect(self, Rect2(Vector2.ZERO, size), bg, 10)
	if sel:
		draw_rect(Rect2(0, 10, 3, size.y - 20), UIKit.ACCENT)
	var age := t - _born
	if age < 0.8:
		UIKit.draw_round_rect(self, Rect2(Vector2.ZERO, size), UIKit.with_alpha(col, 0.25 * (1.0 - age / 0.8)), 10)

	# 图标 + 环
	var c := Vector2(32, size.y * 0.5)
	var R := 19.0
	if calling:
		var ph := fmod(t * 1.3, 1.0)
		draw_circle(c, R + 3 + ph * 8.0, UIKit.with_alpha(col, 0.35 * (1.0 - ph)))
	draw_circle(c, R, col if not done else UIKit.with_alpha(col, 0.35))
	UIKit.draw_icon(self, "phone_in_talk" if calling else inc.data().gi, c, 22, Color.WHITE)
	var ring_frac := -1.0
	var ring_col := Color.WHITE
	match inc.state:
		Incident.S.WAITING, Incident.S.DISPATCHED:
			ring_frac = clampf(inc.deadline / float(inc.true_data().deadline), 0, 1)
			ring_col = Color.WHITE if ring_frac > 0.3 else (UIKit.RED if fmod(t * 3.0, 1.0) < 0.5 else Color.WHITE)
		Incident.S.ONSCENE:
			ring_frac = clampf(inc.progress, 0, 1)
			ring_col = UIKit.GREEN
		Incident.S.CALL:
			ring_frac = clampf(1.0 - inc.call_wait / 10.0, 0, 1)
	if ring_frac >= 0.0:
		draw_arc(c, R + 4, 0, TAU, 40, Color(1, 1, 1, 0.1), 3.0, true)
		draw_arc(c, R + 4, -PI / 2, -PI / 2 + TAU * ring_frac, 40, ring_col, 3.0, true)

	# 标题
	var fb := UIKit.font("bold")
	var title := "110 来电" if calling else inc.title()
	draw_string(fb, Vector2(64, 26), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 64 - 60, 15, UIKit.TEXT if not done else UIKit.TEXT_MUTED)

	# 第二行：出警单位图标（空位用虚线圈表示）
	var x := 64.0
	var y := 43.0
	if calling:
		UIKit.draw_chip(self, "接听", Vector2(x, y - 10), UIKit.RED, 11)
	elif done:
		UIKit.draw_icon(self, "check_circle" if inc.state == Incident.S.DONE else "cancel", Vector2(x + 8, y), 16, col)
	else:
		var need := int(inc.data().need)
		var slots := maxi(need, inc.units.size())
		for k in slots:
			var p := Vector2(x + 9 + k * 22, y)
			if k < inc.units.size():
				var u: PoliceUnit = inc.units[k]
				var uc: Color = u.state_color()
				draw_circle(p, 9, uc)
				UIKit.draw_icon(self, u.info.gi, p, 12, Color.WHITE)
			else:
				_dashed_circle(p, 8.5, UIKit.with_alpha(col, 0.8) if inc.state == Incident.S.WAITING and fmod(t * 2.0, 1.0) < 0.6 else UIKit.TEXT_MUTED)
		if inc.stalled:
			UIKit.draw_icon(self, "warning", Vector2(x + slots * 22 + 12, y), 16, UIKit.RED)

	# 右侧：用时
	var fr := UIKit.font("reg")
	var el := UIKit.fmt_min(inc.elapsed(GameState.minutes))
	var w := fr.get_string_size(el, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(fr, Vector2(size.x - w - 12, 26), el, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEXT_MUTED)
	if not calling and not done:
		var lv := "L%d" % inc.level()
		var lw := fb.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(fb, Vector2(size.x - lw - 12, 47), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


func _dashed_circle(c: Vector2, r: float, col: Color) -> void:
	var n := 10
	for k in n:
		var a0 := TAU * k / n
		draw_arc(c, r, a0, a0 + TAU / n * 0.55, 4, col, 1.5, true)
