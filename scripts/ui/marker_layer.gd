class_name MarkerLayer
extends Control
## 地图标注层：警情、单位、设施图标，选中高亮，行进路线，屏幕外指示。

const FAC_GLYPH := {"station": "所", "patrol_hq": "巡", "traffic_hq": "交", "swat_hq": "特"}

var game: Game
var hover = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_d: float) -> void:
	hover = game.pick(get_viewport().get_mouse_position()) if game else null
	queue_redraw()


func _p(w: Vector3) -> Vector2:
	return game.cam.cam.unproject_position(w)


func _draw() -> void:
	if game == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var zoom: float = game.cam.dist
	var close := zoom < 520.0
	var f_bold := UIKit.font("bold")
	var f_num := UIKit.font("num_bold")
	var f_reg := UIKit.font("reg")
	var vr := get_viewport_rect()

	# 街道名
	_road_labels(zoom, vr)

	# 设施
	for f in game.city.facilities:
		var p := _p(f.center)
		if not vr.grow(40).has_point(p):
			continue
		var r := Rect2(p - Vector2(15, 15), Vector2(30, 30))
		var pts := UIKit.chamfer_points(r, 6, 0, 6, 0)
		draw_colored_polygon(pts, Color(0.03, 0.1, 0.25, 0.92))
		var ol := pts.duplicate()
		ol.append(pts[0])
		draw_polyline(ol, Color(0.35, 0.6, 1.0), 1.5, true)
		_text_c(f_bold, FAC_GLYPH.get(f.type, "警"), p + Vector2(0, 6), 16, Color(0.85, 0.92, 1.0))
		if close or UIKit.same(game.selected, f) or UIKit.same(hover, f):
			_text_c(f_bold, f.name, p + Vector2(0, 32), 13, Color(0.7, 0.82, 1.0), true)
		if UIKit.same(game.selected, f):
			UIKit.draw_brackets(self, r.grow(6), UIKit.CYAN, 7, 2)

	# 出警连线与路线
	for u in game.units:
		if u.state == PoliceUnit.State.ENROUTE and u.incident != null:
			var pts: PackedVector3Array = u.remaining_points()
			var sp := PackedVector2Array()
			for w in pts:
				sp.append(_p(w))
			var c := Data.level_color(u.incident.level())
			_dashed(sp, UIKit.with_alpha(c, 0.55), 2.0, t)
		elif UIKit.same(game.selected, u) and u.state in [PoliceUnit.State.PATROL, PoliceUnit.State.RETURN, PoliceUnit.State.MOVE]:
			var pts: PackedVector3Array = u.remaining_points()
			var sp := PackedVector2Array()
			for w in pts:
				sp.append(_p(w))
			_dashed(sp, UIKit.with_alpha(UIKit.CYAN, 0.45), 1.5, t)

	# 警情
	for inc in game.incidents:
		_draw_incident(inc, t, close, vr, f_bold, f_num, f_reg)

	# 单位
	for u in game.units:
		var p := _p(u.global_position)
		if not vr.grow(20).has_point(p):
			continue
		var hd := _p(u.global_position + u.heading() * 10.0) - p
		var ang := hd.angle()
		var col: Color = u.state_color()
		var s := 8.0 if u.kind != "swat" else 9.5
		var tri := PackedVector2Array([
			p + Vector2(s * 1.4, 0).rotated(ang),
			p + Vector2(-s, s * 0.85).rotated(ang),
			p + Vector2(-s * 0.45, 0).rotated(ang),
			p + Vector2(-s, -s * 0.85).rotated(ang),
		])
		var outline := tri.duplicate()
		outline.append(tri[0])
		draw_colored_polygon(tri, Color(0.02, 0.04, 0.07, 0.9))
		draw_polyline(outline, col, 2.0, true)
		if u.state == PoliceUnit.State.ENROUTE or u.state == PoliceUnit.State.ONSCENE:
			var on := fmod(t * 3.2, 1.0) < 0.5
			draw_circle(p, 2.6, UIKit.RED if on else UIKit.BLUE)
		if UIKit.same(game.selected, u) or UIKit.same(hover, u) or (close and zoom < 300.0):
			_text(f_num, u.callsign, p + Vector2(12, -8), 13, col, true)
		if UIKit.same(game.selected, u):
			UIKit.draw_brackets(self, Rect2(p - Vector2(15, 15), Vector2(30, 30)), UIKit.CYAN, 7, 2)
		elif UIKit.same(hover, u):
			draw_arc(p, 14, 0, TAU, 24, UIKit.with_alpha(UIKit.CYAN, 0.6), 1.5, true)


func _draw_incident(inc: Incident, t: float, close: bool, vr: Rect2, f_bold: Font, f_num: Font, f_reg: Font) -> void:
	var p := _p(inc.spot.pos)
	var col := Data.level_color(inc.level())
	var done := not inc.is_active()
	if done:
		col = UIKit.GREEN if inc.state == Incident.S.DONE else Color(0.6, 0.6, 0.6)
	var inside := vr.grow(-24).has_point(p)
	if not inside:
		if done:
			return
		# 屏幕外指示箭头
		var c := vr.get_center()
		var dir := (p - c).normalized()
		var edge := _clip_to_rect(c, p, vr.grow(-40))
		var tri := PackedVector2Array([edge + dir * 12, edge + dir.rotated(2.4) * 9, edge + dir.rotated(-2.4) * 9])
		draw_colored_polygon(tri, col)
		_text_c(f_bold, inc.data().icon, edge - dir * 14 + Vector2(0, 5), 13, col)
		return
	var s := 13.0 + (2.0 if inc.level() >= 3 else 0.0)
	var pulse := 1.0 + 0.12 * sin(t * 6.0) if inc.state in [Incident.S.CALL, Incident.S.WAITING] else 1.0
	s *= pulse
	var dia := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	draw_colored_polygon(dia, Color(0.03, 0.03, 0.05, 0.92))
	var ol := dia.duplicate()
	ol.append(dia[0])
	draw_polyline(ol, col, 2.0, true)
	if inc.state == Incident.S.CALL:
		var blink := fmod(t * 2.0, 1.0) < 0.6
		_text_c(f_num, "110", p + Vector2(0, 4.5), 10, UIKit.AMBER if blink else col)
	else:
		_text_c(f_bold, inc.data().icon, p + Vector2(0, 5.5), 14, col)
	# 外环：升级倒计时 / 处置进度
	var r := s + 6.0
	if inc.state == Incident.S.ONSCENE:
		draw_arc(p, r, -PI / 2, -PI / 2 + TAU * clampf(inc.progress, 0, 1), 32, UIKit.GREEN, 3.0, true)
		if inc.stalled:
			_text_c(f_bold, "武力不足", p + Vector2(0, -r - 8), 12, UIKit.RED, true)
	elif inc.state in [Incident.S.WAITING, Incident.S.DISPATCHED]:
		var total: float = inc.true_data().deadline
		var frac := clampf(inc.deadline / total, 0.0, 1.0)
		var rc := col if frac > 0.3 else (UIKit.RED if fmod(t * 4.0, 1.0) < 0.5 else col)
		draw_arc(p, r, -PI / 2, -PI / 2 + TAU * frac, 32, UIKit.with_alpha(rc, 0.9), 2.5, true)
	if UIKit.same(game.selected, inc):
		UIKit.draw_brackets(self, Rect2(p - Vector2(r + 5, r + 5), Vector2(r + 5, r + 5) * 2), UIKit.CYAN, 8, 2)
	if close or UIKit.same(game.selected, inc) or UIKit.same(hover, inc) or inc.level() >= 3:
		var label := inc.title() if inc.state != Incident.S.CALL else "来电待研判"
		if done:
			label = "已结案" if inc.state == Incident.S.DONE else "处置失败"
		_text_c(f_bold, label, p + Vector2(0, r + 18), 13, col, true)


var _labels: Array = []


func _road_labels(zoom: float, vr: Rect2) -> void:
	if zoom > 760.0:
		return
	if _labels.is_empty():
		_labels = game.city.road_labels()
	var night: float = game.env.night
	var col := Color(0.16, 0.18, 0.21).lerp(Color(0.86, 0.9, 0.95), night)
	var halo := Color(0.96, 0.95, 0.92, 0.85).lerp(Color(0.02, 0.03, 0.05, 0.85), night)
	var f := UIKit.font("bold")
	for L in _labels:
		if L.cls == "D" and zoom > 380.0:
			continue
		var a := _p(Vector3(L.a.x, 0, L.a.y))
		var b := _p(Vector3(L.b.x, 0, L.b.y))
		var m := (a + b) * 0.5
		if not vr.grow(-60).has_point(m):
			continue
		var ang := (b - a).angle()
		if ang > PI * 0.5 or ang < -PI * 0.5:
			ang += PI
		var size := 14 if L.cls in ["A", "B"] else 12
		var text: String = L.name
		# 竖向道路逐字竖排更易读
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if w > a.distance_to(b) * 0.8:
			continue
		draw_set_transform(m, ang, Vector2.ONE)
		draw_string_outline(f, Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, halo)
		draw_string(f, Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _clip_to_rect(c: Vector2, p: Vector2, r: Rect2) -> Vector2:
	var d := p - c
	var tx := INF
	var ty := INF
	if absf(d.x) > 0.001:
		tx = ((r.end.x if d.x > 0 else r.position.x) - c.x) / d.x
	if absf(d.y) > 0.001:
		ty = ((r.end.y if d.y > 0 else r.position.y) - c.y) / d.y
	return c + d * minf(tx, ty)


func _dashed(pts: PackedVector2Array, col: Color, w: float, t: float) -> void:
	var dash := 8.0
	var gap := 6.0
	var phase := fmod(t * 30.0, dash + gap)
	var acc := -phase
	for k in range(pts.size() - 1):
		var a := pts[k]
		var b := pts[k + 1]
		var L := a.distance_to(b)
		if L < 0.01 or L > 20000.0 or is_nan(L):
			continue
		var dir := (b - a) / L
		var s := 0.0
		var guard := 0
		while s < L and guard < 4000:
			guard += 1
			var cyc := fposmod(acc + s, dash + gap)
			if cyc < dash:
				var e := minf(s + (dash - cyc), L)
				draw_line(a + dir * s, a + dir * e, col, w, true)
				s = e
			else:
				s = minf(s + (dash + gap - cyc), L)
		acc += L


func _text(f: Font, s: String, pos: Vector2, size: int, col: Color, shadow := false) -> void:
	if shadow:
		draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_c(f: Font, s: String, pos: Vector2, size: int, col: Color, shadow := false) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(f, s, pos - Vector2(w * 0.5, 0), size, col, shadow)
