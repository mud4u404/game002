class_name IncidentCard
extends Control
## 警情卡片（自绘）：级别色图标、标题、位置、状态与进度。

signal pressed(inc: Incident)

var inc: Incident
var game: Game
var _hover := false
var _born := 0.0


func _init(p_inc: Incident, p_game: Game) -> void:
	inc = p_inc
	game = p_game
	custom_minimum_size = Vector2(0, 70)
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
	queue_redraw()


func _fit(f: Font, s: String, size_px: int, w: float) -> String:
	if w <= 10.0 or f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x <= w:
		return s
	while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > w:
		s = s.left(s.length() - 1)
	return s + "…"


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var r := Rect2(Vector2.ZERO, size)
	var col := Data.level_color(inc.level())
	var active := inc.is_active()
	var calling := inc.state == Incident.S.CALL
	if not active:
		col = UIKit.GREEN if inc.state == Incident.S.DONE else UIKit.TEXT_MUTED
	var sel: bool = UIKit.same(game.selected, inc)
	var bg := UIKit.BG2
	if _hover or sel:
		bg = UIKit.BG3
	if calling:
		bg = bg.lerp(Color("4a1d20"), 0.35 + 0.25 * sin(t * 5.0))
	UIKit.draw_round_rect(self, r, bg, 9, UIKit.ACCENT if sel else Color(0, 0, 0, 0), 2 if sel else 0)
	var age := t - _born
	if age < 0.8:
		UIKit.draw_round_rect(self, r, UIKit.with_alpha(col, 0.3 * (1.0 - age / 0.8)), 9)

	# 图标
	var ic := Vector2(32, size.y * 0.5)
	draw_circle(ic, 20, UIKit.with_alpha(col, 0.16))
	draw_arc(ic, 20, 0, TAU, 40, UIKit.with_alpha(col, 0.55), 1.5, true)
	var gi: String = "phone_in_talk" if calling else inc.data().gi
	UIKit.draw_icon(self, gi, ic, 22, col)

	var fb := UIKit.font("bold")
	var fr := UIKit.font("reg")
	var x := 62.0
	var w := size.x - x - 12.0
	var title := "110 来电 · 待研判" if calling else inc.title()
	var lvl_txt := Data.level_name(inc.level())
	var lw := fb.get_string_size(lvl_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
	draw_string(fb, Vector2(x, 23), _fit(fb, title, 15, w - lw - 8), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.TEXT)
	UIKit.draw_chip(self, lvl_txt, Vector2(size.x - lw - 10, 9), col, 11)
	draw_string(fr, Vector2(x, 43), _fit(fr, inc.desc(), 12, w), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEXT_DIM)

	# 状态行
	var st: String = Incident.STATE_NAMES[inc.state]
	var st_col := UIKit.TEXT_DIM
	var frac := -1.0
	var bar_col := col
	match inc.state:
		Incident.S.CALL:
			st = "点击接听"
			st_col = UIKit.RED
			frac = clampf(1.0 - inc.call_wait / 10.0, 0, 1)
			bar_col = UIKit.RED
		Incident.S.WAITING:
			st = "等待派警"
			st_col = UIKit.AMBER
			frac = clampf(inc.deadline / float(inc.true_data().deadline), 0, 1)
		Incident.S.DISPATCHED:
			var eta := 99.0
			for u in inc.units:
				if u.state == PoliceUnit.State.ENROUTE:
					eta = minf(eta, u.eta_min)
			st = "赶赴现场" + (" · 约 %d 分钟" % ceili(eta) if eta < 99.0 else "")
			st_col = UIKit.ACCENT.lightened(0.25)
			frac = clampf(inc.deadline / float(inc.true_data().deadline), 0, 1)
		Incident.S.ONSCENE:
			st = "武力不足，请求增援" if inc.stalled else "现场处置中"
			st_col = UIKit.RED if inc.stalled else UIKit.GREEN
			frac = clampf(inc.progress, 0, 1)
			bar_col = UIKit.GREEN
		Incident.S.DONE:
			st = "已结案"
			st_col = UIKit.GREEN
		Incident.S.FAILED:
			st = "处置失败"
			st_col = UIKit.RED
	draw_string(fb, Vector2(x, 62), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, st_col)
	var info := "%s  ·  %d/%d" % [UIKit.fmt_min(inc.elapsed(GameState.minutes)), inc.units.size(), int(inc.data().need)]
	var iw := fr.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(fr, Vector2(size.x - iw - 12, 62), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.TEXT_MUTED)
	if frac >= 0.0:
		var br := Rect2(x, size.y - 5, size.x - x - 12, 3)
		UIKit.draw_round_rect(self, br, Color(1, 1, 1, 0.07), 2)
		if frac > 0.01:
			UIKit.draw_round_rect(self, Rect2(br.position, Vector2(br.size.x * frac, 3)), bar_col if frac > 0.25 or inc.state == Incident.S.ONSCENE else UIKit.RED, 2)
