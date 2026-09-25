class_name MarkerLayer
extends Control
## 地图标注层（参照《112》）：
##   单位 = 车辆剪影卡片 + 引线 + 地面定位点；警情 = 六边形；设施 = 六边形 + 地面波纹；
##   出警路线 = 白色发光线 + 拐点节点。

const UNIT_FILL := {"community": Color("3b8cff"), "patrol": Color("2f6ff0"), "traffic": Color("25a8ff"), "swat": Color("1f47b0")}

var game: Game
var hover = null
var _labels: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_d: float) -> void:
	if game and game.city and game._started:
		hover = game.pick(get_viewport().get_mouse_position())
	queue_redraw()


func _p(w: Vector3) -> Vector2:
	return game.cam.cam.unproject_position(w)


func _draw() -> void:
	if game == null or not game._started:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var zoom: float = game.cam.dist
	var vr := get_viewport_rect()
	_road_labels(zoom, vr)

	# 设施：地面波纹 + 六边形
	for f in game.city.facilities:
		var p := _p(f.center)
		if not vr.grow(60).has_point(p):
			continue
		var sel: bool = UIKit.same(game.selected, f)
		for k in 3:
			var ph := fmod(t * 0.35 + k / 3.0, 1.0)
			draw_arc(p, 10.0 + ph * 34.0, 0, TAU, 48, Color(0.5, 0.8, 1.0, 0.35 * (1.0 - ph)), 1.5, true)
		var top := p + Vector2(0, -30)
		draw_line(p, top + Vector2(0, 14), Color(0.6, 0.85, 1.0, 0.8), 1.5, true)
		draw_circle(p, 3.0, Color.WHITE)
		UIKit.draw_hex(self, top, 17, Color(0.85, 0.93, 1.0), UIKit.CYAN if not sel else Color.WHITE, 2.0 if not sel else 3.0)
		UIKit.draw_hex(self, top, 13, Color("1d4fb8"))
		UIKit.draw_icon(self, Data.FACILITY_TYPES[f.type].gi, top, 16, Color.WHITE)
		if zoom < 700.0 or sel or UIKit.same(hover, f):
			_pill(f.name, top + Vector2(0, -28), UIKit.TEXT, 11)

	# 出警路线
	for u in game.units:
		var show_route: bool = u.state == PoliceUnit.State.ENROUTE or (UIKit.same(game.selected, u) and u.state in [PoliceUnit.State.PATROL, PoliceUnit.State.RETURN, PoliceUnit.State.MOVE])
		if not show_route:
			continue
		var pts: PackedVector3Array = u.remaining_points()
		var sp := PackedVector2Array()
		for w in pts:
			sp.append(_p(w))
		_route(sp, t, u.state == PoliceUnit.State.ENROUTE)

	for inc in game.incidents:
		_draw_incident(inc, t, zoom, vr)
	# 单位按屏幕 y 排序，下方的卡片绘制在上层
	var order := game.units.duplicate()
	order.sort_custom(func(a, b): return _p(a.global_position).y < _p(b.global_position).y)
	for u in order:
		_draw_unit(u, t, zoom, vr)


# ------------------------------------------------------------------ 警情：六边形
func _draw_incident(inc: Incident, t: float, zoom: float, vr: Rect2) -> void:
	var p := _p(inc.spot.pos)
	var col := Data.level_color(inc.level())
	var active := inc.is_active()
	var calling := inc.state == Incident.S.CALL
	if calling:
		col = UIKit.RED
	if not active:
		col = UIKit.GREEN if inc.state == Incident.S.DONE else UIKit.TEXT_MUTED
	if not vr.grow(-24).has_point(p):
		if active:
			_offscreen(p, col, "phone_in_talk" if calling else inc.data().gi, vr)
		return
	var sel: bool = UIKit.same(game.selected, inc)
	var hv: bool = UIKit.same(hover, inc)
	var R := 16.0 + (2.0 if inc.level() >= 3 else 0.0) + (2.0 if sel or hv else 0.0)
	# 重大警情：青绿色搜索 / 警戒范围圈（参照《112》）
	if active and inc.level() >= 3 and not calling:
		var rw := 55.0
		var edge_p := _p(inc.spot.pos + Vector3(rw, 0, 0))
		var rr := edge_p.distance_to(p)
		draw_circle(p, rr, Color(0.1, 0.75, 0.6, 0.12))
		var n := 48
		for k in n:
			if k % 2 == 0:
				draw_arc(p, rr, TAU * k / n + t * 0.1, TAU * (k + 1) / n + t * 0.1, 3, Color(0.25, 0.95, 0.75, 0.7), 1.5, true)
	# 地面光晕 / 波纹
	var glow := Color(col.r, col.g, col.b, 0.22)
	draw_circle(p, R * 1.6, Color(col.r, col.g, col.b, 0.08))
	if inc.state in [Incident.S.CALL, Incident.S.WAITING]:
		for k in 2:
			var ph := fmod(t * 0.8 + k * 0.5, 1.0)
			draw_arc(p, R + ph * 26.0, 0, TAU, 48, UIKit.with_alpha(col, 0.6 * (1.0 - ph)), 2.0, true)
	UIKit.draw_hex(self, p, R + 3, glow)
	UIKit.draw_hex(self, p, R, col.darkened(0.15), Color.WHITE if (sel or hv) else col.lightened(0.35), 2.0)
	UIKit.draw_icon(self, "phone_in_talk" if calling else inc.data().gi, p, int(R * 1.1), Color.WHITE)
	# 六边形边框进度：时限（白→红）或处置进度（绿）
	if inc.state == Incident.S.ONSCENE:
		UIKit.draw_hex_progress(self, p, R + 5, clampf(inc.progress, 0, 1), UIKit.GREEN, 3.0)
	elif inc.state in [Incident.S.WAITING, Incident.S.DISPATCHED]:
		var frac := clampf(inc.deadline / float(inc.true_data().deadline), 0.0, 1.0)
		var rc := Color.WHITE if frac > 0.3 else (UIKit.RED if fmod(t * 3.0, 1.0) < 0.5 else Color.WHITE)
		UIKit.draw_hex_progress(self, p, R + 5, frac, rc, 2.5)
	if sel or hv or inc.stalled or (zoom < 420.0 and active):
		var text := "110 来电" if calling else inc.title()
		if inc.stalled:
			text = "武力不足"
		_pill(text, p + Vector2(0, R + 16), UIKit.RED if inc.stalled else Color.WHITE, 11)


# ------------------------------------------------------------------ 单位：车辆卡片
func _draw_unit(u: PoliceUnit, t: float, zoom: float, vr: Rect2) -> void:
	var p := _p(u.global_position)
	if not vr.grow(40).has_point(p):
		return
	var sel: bool = UIKit.same(game.selected, u)
	var hv: bool = UIKit.same(hover, u)
	var idle := u.state == PoliceUnit.State.IDLE
	var emergency := u.state == PoliceUnit.State.ENROUTE or u.state == PoliceUnit.State.ONSCENE
	var scale := clampf(420.0 / zoom, 0.8, 1.15) * (1.12 if sel or hv else 1.0)
	var cw := 40.0 * scale
	var ch := 25.0 * scale
	var stem := 13.0 * scale
	var fill: Color = UNIT_FILL.get(u.kind, UIKit.ACCENT)
	if idle:
		fill = fill.darkened(0.35)
	# 地面定位点 + 发光光柱
	draw_circle(p, 9.0, Color(0.3, 0.65, 1.0, 0.18))
	draw_circle(p, 4.5, Color(0.5, 0.8, 1.0, 0.45))
	draw_circle(p, 2.4, Color.WHITE)
	var card := Rect2(p + Vector2(-cw * 0.5, -stem - ch), Vector2(cw, ch))
	draw_line(p, Vector2(p.x, card.end.y), Color(0.35, 0.7, 1.0, 0.35), 5.0, true)
	draw_line(p, Vector2(p.x, card.end.y), Color(0.85, 0.95, 1.0, 0.95), 1.4, true)
	# 卡片
	var border := Color(0.75, 0.9, 1.0, 0.9)
	if sel:
		border = Color.WHITE
	elif u.state == PoliceUnit.State.ONSCENE:
		border = UIKit.GREEN
	elif u.state == PoliceUnit.State.ENROUTE:
		border = Color("ff4a5a") if fmod(t * 3.2, 1.0) < 0.5 else Color("5aa0ff")
	if emergency:
		UIKit.draw_round_rect(self, card.grow(3), Color(border.r, border.g, border.b, 0.25), 5)
	UIKit.draw_round_rect(self, card, fill, 4, border, 2 if (sel or emergency) else 1)
	var inner := Rect2(card.position + Vector2(3, 3), card.size - Vector2(6, 6))
	UIKit.draw_round_rect(self, inner, Color(0.78, 0.89, 1.0, 0.92 if not idle else 0.6), 2)
	var siren := fmod(t * 3.2, 1.0) if emergency else -1.0
	VehicleArt.draw(self, u.kind, inner.grow(-1), Color("f4f8ff"), Color("15357a"), siren)
	# 车组人数小圆点
	var n := int(u.info.staff) + (1 if u.kind == "community" else 0)
	for k in n:
		var dx := (k - (n - 1) * 0.5) * 6.0 * scale
		draw_circle(Vector2(p.x + dx, card.position.y - 5.0 * scale), 2.0 * scale, Color(0.85, 0.94, 1.0))
	if sel or hv or zoom < 300.0:
		_pill(u.callsign, Vector2(p.x, card.position.y - 18 * scale), Color.WHITE, 11)


# ------------------------------------------------------------------ 工具
func _pill(text: String, center: Vector2, col: Color, size: int) -> void:
	var f := UIKit.font("bold")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0
	var h := size + 8.0
	var r := Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h))
	UIKit.draw_round_rect(self, r, Color(0.03, 0.08, 0.2, 0.88), h * 0.5, Color(0.35, 0.65, 1.0, 0.6), 1)
	draw_string(f, Vector2(r.position.x + 7, center.y + size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _offscreen(p: Vector2, col: Color, icon_name: String, vr: Rect2) -> void:
	var c := vr.get_center()
	var dir := (p - c).normalized()
	var safe := Rect2(vr.position + Vector2(110, 90), vr.size - Vector2(110 + 360, 90 + 110))
	var edge := c + (p - c) * _clip_t(c, p, safe)
	var tri := PackedVector2Array([edge + dir * 24, edge + dir * 14 + dir.orthogonal() * 7, edge + dir * 14 - dir.orthogonal() * 7])
	draw_colored_polygon(tri, col)
	UIKit.draw_hex(self, edge, 13, col.darkened(0.15), Color.WHITE, 1.5)
	UIKit.draw_icon(self, icon_name, edge, 14, Color.WHITE)


func _route(pts: PackedVector2Array, t: float, emergency: bool) -> void:
	var ok := PackedVector2Array()
	for q in pts:
		if is_finite(q.x) and is_finite(q.y) and absf(q.x) < 20000.0 and absf(q.y) < 20000.0:
			ok.append(q)
	if ok.size() < 2:
		return
	var col := Color(0.85, 0.94, 1.0) if emergency else Color(0.45, 0.72, 1.0)
	draw_polyline(ok, Color(col.r, col.g, col.b, 0.12), 9.0, true)
	draw_polyline(ok, Color(col.r, col.g, col.b, 0.3), 4.5, true)
	draw_polyline(ok, col, 1.8, true)
	# 拐点节点
	for k in range(1, ok.size() - 1):
		if ok[k].distance_to(ok[k - 1]) > 6.0:
			draw_circle(ok[k], 3.0, col)
	draw_circle(ok[ok.size() - 1], 4.0, col)
	# 流动光点
	var total := 0.0
	for k in ok.size() - 1:
		total += ok[k].distance_to(ok[k + 1])
	var head := fmod(t * 120.0, maxf(total, 1.0))
	var acc := 0.0
	for k in ok.size() - 1:
		var L := ok[k].distance_to(ok[k + 1])
		if head <= acc + L:
			var hp := ok[k].lerp(ok[k + 1], (head - acc) / maxf(L, 0.001))
			draw_circle(hp, 6.0, Color(1, 1, 1, 0.25))
			draw_circle(hp, 2.8, Color.WHITE)
			break
		acc += L


func _road_labels(zoom: float, vr: Rect2) -> void:
	if zoom > 760.0:
		return
	if _labels.is_empty():
		_labels = game.city.road_labels()
	var col := Color(0.6, 0.78, 1.0, 0.85)
	var halo := Color(0.02, 0.06, 0.16, 0.9)
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
		var size := 12 if L.cls in ["A", "B"] else 11
		var text: String = L.name
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if w > a.distance_to(b) * 0.8:
			continue
		draw_set_transform(m + Vector2(0, -9).rotated(ang), ang, Vector2.ONE)
		draw_string_outline(f, Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, halo)
		draw_string(f, Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _clip_t(c: Vector2, p: Vector2, r: Rect2) -> float:
	var d := p - c
	var tx := INF
	var ty := INF
	if absf(d.x) > 0.001:
		tx = ((r.end.x if d.x > 0 else r.position.x) - c.x) / d.x
	if absf(d.y) > 0.001:
		ty = ((r.end.y if d.y > 0 else r.position.y) - c.y) / d.y
	return minf(tx, ty)
