class_name MarkerLayer
extends Control
## 地图标注层：街道名、设施、警情图钉、警力图标、出警路线、屏幕外指示。

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

	# 出警路线
	for u in game.units:
		var show_route: bool = u.state == PoliceUnit.State.ENROUTE or UIKit.same(game.selected, u) and u.state in [PoliceUnit.State.PATROL, PoliceUnit.State.RETURN, PoliceUnit.State.MOVE]
		if not show_route:
			continue
		var pts: PackedVector3Array = u.remaining_points()
		var sp := PackedVector2Array()
		for w in pts:
			sp.append(_p(w))
		var c: Color = Data.level_color(u.incident.level()) if u.incident != null else UIKit.ACCENT
		_route(sp, c, t)

	# 设施
	for f in game.city.facilities:
		var p := _p(f.center)
		if not vr.grow(40).has_point(p):
			continue
		var sel: bool = UIKit.same(game.selected, f)
		var r := Rect2(p - Vector2(16, 16), Vector2(32, 32))
		UIKit.draw_round_rect(self, r.grow(2), Color(1, 1, 1, 0.9) if sel else Color(0, 0, 0, 0.35), 9)
		UIKit.draw_round_rect(self, r, UIKit.NAVY, 8)
		UIKit.draw_icon(self, Data.FACILITY_TYPES[f.type].gi, p, 20, Color.WHITE)
		if zoom < 700.0 or sel or UIKit.same(hover, f):
			_pill(f.name, p + Vector2(0, 30), UIKit.TEXT, 12)

	# 警情
	for inc in game.incidents:
		_draw_incident(inc, t, zoom, vr)

	# 警力
	for u in game.units:
		_draw_unit(u, t, zoom, vr)


# ------------------------------------------------------------------ 警情图钉
func _draw_incident(inc: Incident, t: float, zoom: float, vr: Rect2) -> void:
	var p := _p(inc.spot.pos)
	var col := Data.level_color(inc.level())
	var active := inc.is_active()
	if not active:
		col = UIKit.GREEN if inc.state == Incident.S.DONE else UIKit.TEXT_MUTED
	var calling := inc.state == Incident.S.CALL
	if not vr.grow(-20).has_point(p):
		if active:
			_offscreen(p, col, inc.data().gi if not calling else "phone_in_talk", vr)
		return
	var sel: bool = UIKit.same(game.selected, inc)
	var hv: bool = UIKit.same(hover, inc)
	var R := 15.0 + (2.0 if inc.level() >= 3 else 0.0) + (2.0 if sel or hv else 0.0)
	# 等待状态的扩散波纹
	if inc.state in [Incident.S.CALL, Incident.S.WAITING]:
		for k in 2:
			var ph := fmod(t * 0.9 + k * 0.5, 1.0)
			draw_arc(p, R + 4 + ph * 22.0, 0, TAU, 48, UIKit.with_alpha(col, 0.55 * (1.0 - ph)), 2.0, true)
	draw_circle(p + Vector2(0, 2), R + 2, Color(0, 0, 0, 0.35))
	draw_circle(p, R + 2, Color.WHITE if sel else Color(1, 1, 1, 0.92))
	draw_circle(p, R, col)
	UIKit.draw_icon(self, "phone_in_talk" if calling else inc.data().gi, p, int(R * 1.25), Color.WHITE)
	# 外环：时限 / 进度
	var rr := R + 6.0
	if inc.state == Incident.S.ONSCENE:
		draw_arc(p, rr, 0, TAU, 48, Color(0, 0, 0, 0.35), 4.0, true)
		draw_arc(p, rr, -PI / 2, -PI / 2 + TAU * clampf(inc.progress, 0, 1), 48, UIKit.GREEN, 4.0, true)
	elif inc.state in [Incident.S.WAITING, Incident.S.DISPATCHED]:
		var frac := clampf(inc.deadline / float(inc.true_data().deadline), 0.0, 1.0)
		var rc := col if frac > 0.3 else (UIKit.RED if fmod(t * 3.0, 1.0) < 0.5 else Color.WHITE)
		draw_arc(p, rr, 0, TAU, 48, Color(0, 0, 0, 0.35), 4.0, true)
		draw_arc(p, rr, -PI / 2, -PI / 2 + TAU * frac, 48, rc, 4.0, true)
	if zoom < 650.0 or sel or hv or inc.level() >= 3 or calling:
		var text := "110 来电" if calling else inc.title()
		if not active:
			text = "已结案" if inc.state == Incident.S.DONE else "处置失败"
		elif inc.stalled:
			text += " · 武力不足"
		_pill(text, p + Vector2(0, R + 22), UIKit.RED if inc.stalled else Color.WHITE, 12)


# ------------------------------------------------------------------ 警力图标
func _draw_unit(u: PoliceUnit, t: float, zoom: float, vr: Rect2) -> void:
	var p := _p(u.global_position)
	if not vr.grow(20).has_point(p):
		return
	var sel: bool = UIKit.same(game.selected, u)
	var hv: bool = UIKit.same(hover, u)
	var col: Color = u.state_color()
	var R := 9.5 if not (sel or hv) else 11.0
	var hd := _p(u.global_position + u.heading() * 10.0) - p
	var ang := hd.angle()
	var emergency := u.state == PoliceUnit.State.ENROUTE or u.state == PoliceUnit.State.ONSCENE
	# 朝向小三角
	var tip := p + Vector2(R + 6, 0).rotated(ang)
	var tri := PackedVector2Array([tip, p + Vector2(R, 4.5).rotated(ang), p + Vector2(R, -4.5).rotated(ang)])
	draw_colored_polygon(tri, Color.WHITE)
	draw_circle(p + Vector2(0, 1.5), R + 1.5, Color(0, 0, 0, 0.35))
	var ring := Color.WHITE
	if emergency:
		ring = Color("ff3b3b") if fmod(t * 3.2, 1.0) < 0.5 else Color("3b7bff")
	draw_circle(p, R + 1.5, ring)
	draw_circle(p, R, col.darkened(0.35) if u.state == PoliceUnit.State.IDLE else col)
	UIKit.draw_icon(self, u.info.gi, p, int(R * 1.35), Color.WHITE)
	if sel or hv or zoom < 320.0:
		_pill(u.callsign, p + Vector2(0, -R - 13), Color.WHITE, 11)


# ------------------------------------------------------------------ 工具
func _pill(text: String, center: Vector2, col: Color, size: int) -> void:
	var f := UIKit.font("bold")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0
	var h := size + 9.0
	var r := Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h))
	UIKit.draw_round_rect(self, r, Color(0.07, 0.08, 0.1, 0.82), h * 0.5)
	draw_string(f, Vector2(r.position.x + 7, center.y + size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _offscreen(p: Vector2, col: Color, icon_name: String, vr: Rect2) -> void:
	var c := vr.get_center()
	var dir := (p - c).normalized()
	var edge := _clip_to_rect(c, p, vr.grow(-46))
	var tri := PackedVector2Array([edge + dir * 22, edge + dir * 12 + dir.orthogonal() * 7, edge + dir * 12 - dir.orthogonal() * 7])
	draw_colored_polygon(tri, col)
	draw_circle(edge, 13, Color.WHITE)
	draw_circle(edge, 11.5, col)
	UIKit.draw_icon(self, icon_name, edge, 15, Color.WHITE)


func _route(pts: PackedVector2Array, col: Color, t: float) -> void:
	if pts.size() < 2:
		return
	var ok := PackedVector2Array()
	for q in pts:
		if is_finite(q.x) and is_finite(q.y) and absf(q.x) < 20000.0 and absf(q.y) < 20000.0:
			ok.append(q)
	if ok.size() < 2:
		return
	draw_polyline(ok, Color(0, 0, 0, 0.35), 6.0, true)
	draw_polyline(ok, UIKit.with_alpha(col, 0.85), 3.0, true)
	# 流动的方向点
	var total := 0.0
	for k in ok.size() - 1:
		total += ok[k].distance_to(ok[k + 1])
	var spacing := 26.0
	var off := fmod(t * 40.0, spacing)
	var acc := 0.0
	var next := off
	for k in ok.size() - 1:
		var a := ok[k]
		var b := ok[k + 1]
		var L := a.distance_to(b)
		while next <= acc + L and next < total:
			draw_circle(a.lerp(b, (next - acc) / maxf(L, 0.001)), 2.2, Color.WHITE)
			next += spacing
		acc += L


func _road_labels(zoom: float, vr: Rect2) -> void:
	if zoom > 760.0:
		return
	if _labels.is_empty():
		_labels = game.city.road_labels()
	var night: float = game.env.night
	var col := Color(0.2, 0.22, 0.25).lerp(Color(0.8, 0.84, 0.9), night)
	var halo := Color(0.97, 0.96, 0.93, 0.8).lerp(Color(0.02, 0.03, 0.05, 0.8), night)
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
		var size := 13 if L.cls in ["A", "B"] else 11
		var text: String = L.name
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
