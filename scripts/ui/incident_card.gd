class_name IncidentCard
extends Control
## 警情队列卡片（自绘）

signal pressed(inc: Incident)

var inc: Incident
var game: Game
var _hover := false
var _born := 0.0


func _init(p_inc: Incident, p_game: Game) -> void:
	inc = p_inc
	game = p_game
	custom_minimum_size = Vector2(0, 74)
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
	if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x <= w:
		return s
	while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > w:
		s = s.left(s.length() - 1)
	return s + "…"


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var r := Rect2(Vector2.ZERO, size)
	var col := Data.level_color(inc.level())
	var active := inc.is_active()
	if not active:
		col = UIKit.GREEN if inc.state == Incident.S.DONE else Color(0.55, 0.55, 0.58)
	var sel: bool = UIKit.same(game.selected, inc)
	var bg := Color(0.04, 0.08, 0.13, 0.9)
	if inc.state == Incident.S.CALL:
		var k := 0.5 + 0.5 * sin(t * 6.0)
		bg = bg.lerp(Color(0.35, 0.08, 0.06, 0.9), 0.35 * k)
	if _hover or sel:
		bg = bg.lightened(0.06)
	var pts := UIKit.chamfer_points(r, 0, 10, 0, 0)
	draw_colored_polygon(pts, bg)
	# 入场闪光
	var age := t - _born
	if age < 0.6:
		draw_colored_polygon(pts, UIKit.with_alpha(col, 0.35 * (1.0 - age / 0.6)))
	draw_rect(Rect2(0, 0, 4, size.y), col)
	if sel:
		var ol := pts.duplicate()
		ol.append(pts[0])
		draw_polyline(ol, UIKit.CYAN, 1.5, true)

	var fb := UIKit.font("bold")
	var fr := UIKit.font("reg")
	var fn := UIKit.font("num_bold")
	var fm := UIKit.font("mono")
	var x := 16.0
	var w := size.x - x - 12.0

	# 行1：图标 + 标题 + 等级
	var title := inc.title() if inc.state != Incident.S.CALL else "110 来电 · 待研判"
	var lvl_txt := "L%d %s" % [inc.level(), Data.level_name(inc.level())]
	var lw := fb.get_string_size(lvl_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(fb, Vector2(x, 22), _fit(fb, title, 16, w - lw - 16), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIKit.TEXT)
	var chip := Rect2(size.x - lw - 20, 8, lw + 10, 18)
	draw_rect(chip, UIKit.with_alpha(col, 0.18))
	draw_rect(chip, UIKit.with_alpha(col, 0.7), false, 1.0)
	draw_string(fb, Vector2(chip.position.x + 5, 22), lvl_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

	# 行2：位置
	draw_string(fr, Vector2(x, 42), _fit(fr, inc.desc(), 13, w), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.TEXT_DIM)

	# 行3：状态 / 用时 / 警力
	var st: String = Incident.STATE_NAMES[inc.state]
	var st_col := col
	if inc.state == Incident.S.ONSCENE and inc.stalled:
		st = "武力不足"
		st_col = UIKit.RED
	elif inc.state == Incident.S.DISPATCHED:
		var eta := 99.0
		for u in inc.units:
			if u.state == PoliceUnit.State.ENROUTE:
				eta = minf(eta, u.eta_min)
		if eta < 99.0:
			st = "出警中 · ETA %s" % UIKit.fmt_min(eta)
	draw_string(fb, Vector2(x, 63), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, st_col)
	var el := UIKit.fmt_min(inc.elapsed(GameState.minutes))
	var info := "%s  %d/%d" % [el, inc.units.size(), int(inc.data().need)]
	var iw := fm.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(fm, Vector2(size.x - iw - 12, 63), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.TEXT_DIM)

	# 底部进度 / 时限条
	var bar := Rect2(4, size.y - 3, size.x - 4, 3)
	if inc.state == Incident.S.ONSCENE:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(inc.progress, 0, 1), 3)), UIKit.GREEN)
	elif inc.state in [Incident.S.WAITING, Incident.S.DISPATCHED]:
		var frac := clampf(inc.deadline / float(inc.true_data().deadline), 0, 1)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, 3)), UIKit.with_alpha(col if frac > 0.3 else UIKit.RED, 0.8))
	elif inc.state == Incident.S.CALL:
		var frac2 := clampf(1.0 - inc.call_wait / 10.0, 0, 1)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac2, 3)), UIKit.AMBER)
	var _unused := fn
