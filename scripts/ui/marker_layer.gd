class_name MarkerLayer
extends Control
## 地图标注层（参照《112》）：
##   单位 = 车辆剪影卡片 + 引线 + 地面定位点；警情 = 六边形；设施 = 六边形 + 地面波纹；
##   出警路线 = 白色发光线 + 拐点节点。

const UNIT_FILL := {"community": Color("3b8cff"), "patrol": Color("2f6ff0"), "traffic": Color("25a8ff"), "swat": Color("1f47b0")}

var game: Game
var hover = null
var layers := {"heat": false, "reach": false, "sky": false}
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
	var ops: Ops = game.ops
	if layers.heat:
		_heat(ops)
	if layers.reach:
		_reach(ops)
	_road_labels(zoom, vr)
	_zones(t)
	_cameras(ops, t, zoom, layers.sky or _any_suspect(ops))
	_checkpoints(ops, t)

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
		var show_route: bool = u.state == PoliceUnit.State.ENROUTE or u.state == PoliceUnit.State.CHASE or (UIKit.same(game.selected, u) and u.state in [PoliceUnit.State.PATROL, PoliceUnit.State.RETURN, PoliceUnit.State.MOVE])
		if not show_route:
			continue
		var pts: PackedVector3Array = u.remaining_points()
		var sp := PackedVector2Array()
		for w in pts:
			sp.append(_p(w))
		_route(sp, t, u.state == PoliceUnit.State.ENROUTE or u.state == PoliceUnit.State.CHASE)

	for inc in game.incidents:
		_draw_incident(inc, t, zoom, vr)
	for sp in ops.suspects:
		_draw_suspect(sp, t, vr)
	# 单位按屏幕 y 排序，下方的卡片绘制在上层
	var order := game.units.duplicate()
	order.sort_custom(func(a, b): return _p(a.global_position).y < _p(b.global_position).y)
	for u in order:
		_draw_unit(u, t, zoom, vr)
	if ops.placing:
		_placing_cursor(t)


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
	# 专长需求小图标：红 = 缺，青 = 在途，绿 = 到场
	if active and not calling and inc.state != Incident.S.DONE:
		var r := inc.req()
		var ks := r.keys()
		for i in ks.size():
			var k: String = ks[i]
			var st := inc.skill_state(k)
			var ic: Color = {"done": UIKit.GREEN, "enroute": UIKit.CYAN, "missing": UIKit.RED}[st]
			var cp := p + Vector2((i - (ks.size() - 1) * 0.5) * 17.0, -R - 12)
			draw_circle(cp, 7.5, Color(0.02, 0.06, 0.15, 0.92))
			draw_arc(cp, 7.5, 0, TAU, 20, ic, 1.4, true)
			UIKit.draw_icon(self, Data.SKILLS[k].gi, cp, 10, ic)
	if sel or hv or inc.stalled or (zoom < 420.0 and active):
		var text := "110 来电" if calling else inc.title()
		if inc.stalled:
			var miss: Dictionary = inc.missing(true, true)
			var names := []
			for k in miss.keys():
				if k != "any":
					names.append(Data.SKILLS[k].name)
			text = "缺" + "、".join(names)
		_pill(text, p + Vector2(0, R + 16), UIKit.RED if inc.stalled else Color.WHITE, 11)


# ------------------------------------------------------------------ 单位：车辆卡片
func _draw_unit(u: PoliceUnit, t: float, zoom: float, vr: Rect2) -> void:
	var p := _p(u.global_position)
	if not vr.grow(40).has_point(p):
		return
	var sel: bool = UIKit.same(game.selected, u)
	var hv: bool = UIKit.same(hover, u)
	var idle := u.state == PoliceUnit.State.IDLE
	var emergency := u.state in [PoliceUnit.State.ENROUTE, PoliceUnit.State.ONSCENE, PoliceUnit.State.CHASE]
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
	elif u.state == PoliceUnit.State.ENROUTE or u.state == PoliceUnit.State.CHASE:
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
	# 晋升：3 秒金色光环 + 胶囊
	var lu := t - u.level_up_at
	if lu >= 0.0 and lu < 3.0:
		var ph := lu / 3.0
		for k in 2:
			var w := fmod(ph * 2.0 + k * 0.5, 1.0)
			draw_arc(p, 12.0 + w * 34.0, 0, TAU, 40, UIKit.with_alpha(UIKit.AMBER, 0.75 * (1.0 - w)), 2.2, true)
		_pill("晋升 Lv.%d" % u.level, Vector2(p.x, card.position.y - 30.0 * scale), UIKit.AMBER, 11)
	# 等级角标：Lv.1 保持地图干净
	if u.level >= 2:
		var br := 7.0 * scale
		var bp := Vector2(card.end.x - br - 2.0, card.position.y + br + 2.0)
		draw_circle(bp, br, UIKit.AMBER)
		draw_arc(bp, br, 0, TAU, 20, Color.WHITE, 1.0, true)
		var fs := int(maxf(9.0, 10.0 * scale))
		var ltxt := str(u.level)
		var lsz := UIKit.font("bold").get_string_size(ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(UIKit.font("bold"), bp + Vector2(-lsz.x * 0.5, fs * 0.36), ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if sel or hv or zoom < 300.0:
		_pill(u.callsign, Vector2(p.x, card.position.y - 18 * scale), Color.WHITE, 11)


# ------------------------------------------------------------------ 中国警务图层
func _any_suspect(ops: Ops) -> bool:
	for sp in ops.suspects:
		if sp.state == Suspect.S.FLEE:
			return true
	return false


## 世界半径 → 屏幕半径
func _sr(w: Vector3, r: float) -> float:
	return _p(w + Vector3(r, 0, 0)).distance_to(_p(w))


## 治安热力：风险网格生成小纹理，双线性放大成柔和热区（琥珀 → 红）
var _heat_img: Image
var _heat_tex: ImageTexture
var _heat_t := 0.0


func _heat(ops: Ops) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _heat_tex == null or now - _heat_t > 0.5:
		_heat_t = now
		var S := 4  # 每格细分，平滑边缘
		var w := ops.cols * S
		var h := ops.rows * S
		if _heat_img == null:
			_heat_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		var mx := maxf(ops.risk_max(), 0.001)
		for y in h:
			for x in w:
				# 在网格中心之间双线性插值
				var gx := clampf((x + 0.5) / S - 0.5, 0.0, ops.cols - 1.0)
				var gy := clampf((y + 0.5) / S - 0.5, 0.0, ops.rows - 1.0)
				var x0 := int(gx)
				var y0 := int(gy)
				var x1 := mini(x0 + 1, ops.cols - 1)
				var y1 := mini(y0 + 1, ops.rows - 1)
				var fx := gx - x0
				var fy := gy - y0
				var r := lerpf(lerpf(ops.risk[y0 * ops.cols + x0], ops.risk[y0 * ops.cols + x1], fx),
					lerpf(ops.risk[y1 * ops.cols + x0], ops.risk[y1 * ops.cols + x1], fx), fy)
				var k := clampf(r / mx, 0.0, 1.0)
				k = clampf((k - 0.2) / 0.8, 0.0, 1.0)
				var col := Color("f0a020").lerp(Color("ff2d4a"), clampf(k * 1.4 - 0.3, 0.0, 1.0))
				col.a = pow(k, 1.4) * 0.45
				_heat_img.set_pixel(x, y, col)
		if _heat_tex == null:
			_heat_tex = ImageTexture.create_from_image(_heat_img)
		else:
			_heat_tex.update(_heat_img)
	var P := game.city.play_rect
	var o := _p(Vector3(P.position.x, 0, P.position.y))
	var ex := _p(Vector3(P.end.x, 0, P.position.y))
	var ey := _p(Vector3(P.position.x, 0, P.end.y))
	var sz := Vector2(ops.cols * Ops.CELL, ops.rows * Ops.CELL)
	var xf := Transform2D((ex - o) / P.size.x * sz.x / sz.x, (ey - o) / P.size.y, o)
	draw_set_transform_matrix(xf)
	draw_texture_rect(_heat_tex, Rect2(Vector2.ZERO, sz), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# 见警：路面警力可见范围（青色细点阵）
	for i in ops.presence.size():
		var pr: float = ops.presence[i]
		if pr < 0.25 or ops.base[i] <= 0.0:
			continue
		var c2 := ops.cell_center(i)
		draw_circle(_p(Vector3(c2.x, 0, c2.y)), 1.5 + minf(pr, 1.5) * 1.2, Color(0.25, 0.95, 0.8, 0.5))


## 1-3-5 快反圈：路网按最快到达时间着色，超出 5 分钟为盲区
func _reach(ops: Ops) -> void:
	var g := game.city.graph
	var cols := [Color(0.2, 1.0, 0.75, 0.95), Color(0.25, 0.75, 1.0, 0.8), Color(0.55, 0.5, 1.0, 0.6), Color(1.0, 0.24, 0.3, 0.75)]
	var P := game.city.play_rect
	for ed in g.edges:
		var a: Vector3 = g.positions[ed.a]
		var b: Vector3 = g.positions[ed.b]
		if not P.has_point(Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)):
			continue
		var ta: float = ops.node_eta[ed.a]
		var tb: float = ops.node_eta[ed.b]
		# 分两半着色，让等时线落在路段中间
		var m := (a + b) * 0.5
		for half in [[a, m, ta], [m, b, tb]]:
			var t: float = half[2]
			var ci := 3
			for k in 3:
				if t <= Ops.REACH_MINUTES[k]:
					ci = k
					break
			var col: Color = cols[ci]
			draw_line(_p(half[0]), _p(half[1]), UIKit.with_alpha(col, col.a * 0.25), 7.0, true)
			draw_line(_p(half[0]), _p(half[1]), col, 2.2, true)
	# 图例
	var vr := get_viewport_rect()
	var o := Vector2(vr.size.x * 0.5 - 150, vr.size.y - 96)
	var names := ["1 分钟", "3 分钟", "5 分钟", "盲区"]
	UIKit.draw_round_rect(self, Rect2(o - Vector2(10, 12), Vector2(320, 24)), Color(0.02, 0.06, 0.16, 0.85), 12, Color(0.3, 0.6, 1.0, 0.5), 1)
	for k in 4:
		var x := o.x + k * 78.0
		draw_line(Vector2(x, o.y), Vector2(x + 16, o.y), cols[k], 3.0, true)
		draw_string(UIKit.font("bold"), Vector2(x + 22, o.y + 4), names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIKit.TEXT)


## 巡区：选中单位或开启快反圈图层时显示
func _zones(t: float) -> void:
	for u in game.units:
		if not u.info.patrol:
			continue
		var sel: bool = UIKit.same(game.selected, u)
		if not sel and not (u.zone_set and (layers.reach or layers.heat)):
			continue
		var c := _p(u.patrol_center)
		var r := _sr(u.patrol_center, u.patrol_radius)
		var col := Color(0.3, 0.75, 1.0)
		draw_circle(c, r, Color(col.r, col.g, col.b, 0.06 if sel else 0.035))
		var n := 72
		for k in n:
			if k % 3 != 2:
				draw_arc(c, r, TAU * k / n + t * 0.05, TAU * (k + 1) / n + t * 0.05, 3, Color(col.r, col.g, col.b, 0.75 if sel else 0.4), 1.4, true)
		draw_circle(c, 3.0, Color(col.r, col.g, col.b, 0.8))
		if sel:
			_pill("巡区 · %s" % u.callsign, c + Vector2(0, -r - 10), UIKit.CYAN, 11)


## 天网摄像头：路口小六边形；开启图层或有追逃时显示视域与扫描扇面
func _cameras(ops: Ops, t: float, zoom: float, full: bool) -> void:
	for cam in ops.cameras:
		var p := _p(cam.pos)
		if full:
			var r := _sr(cam.pos, Ops.CAM_RANGE)
			draw_circle(p, r, Color(0.3, 0.8, 1.0, 0.04))
			draw_arc(p, r, 0, TAU, 48, Color(0.3, 0.8, 1.0, 0.3), 1.0, true)
			var sweep := fmod(t * 0.6 + float(cam.node) * 0.37, 1.0) * TAU
			var fan := PackedVector2Array([p])
			for k in 9:
				var a := sweep + (k - 4) * 0.09
				fan.append(p + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(fan, Color(0.3, 0.8, 1.0, 0.1))
		UIKit.draw_hex(self, p, 8.5, Color("0d2a66"), Color(0.45, 0.8, 1.0, 0.9 if full else 0.55), 1.2)
		UIKit.draw_icon(self, "videocam", p, 10, Color(0.75, 0.9, 1.0, 1.0 if full else 0.6))
		if full and zoom < 320.0:
			_pill(cam.name, p + Vector2(0, 18), UIKit.TEXT_DIM, 10)


func _checkpoints(ops: Ops, t: float) -> void:
	for cp in ops.checkpoints:
		var p := _p(cp.pos)
		var r := _sr(cp.pos, Ops.CHECKPOINT_RANGE + 4.0)
		var blink := fmod(t * 2.0, 1.0) < 0.5
		draw_circle(p, r, Color(1.0, 0.24, 0.3, 0.12))
		draw_arc(p, r, 0, TAU, 32, Color(1.0, 0.35, 0.4, 0.7), 1.5, true)
		# 路障条纹
		var bar := Rect2(p - Vector2(15, 4), Vector2(30, 8))
		UIKit.draw_round_rect(self, bar, Color.WHITE, 2)
		for k in 3:
			var x := bar.position.x + 3 + k * 9
			draw_colored_polygon(PackedVector2Array([Vector2(x, bar.end.y), Vector2(x + 4, bar.position.y), Vector2(x + 8, bar.position.y), Vector2(x + 4, bar.end.y)]), UIKit.RED)
		draw_circle(p + Vector2(-17, 0), 2.5, UIKit.RED if blink else Color("3f7bff"))
		draw_circle(p + Vector2(17, 0), 2.5, Color("3f7bff") if blink else UIKit.RED)
		_pill("卡点 %d′" % ceili(cp.life), p + Vector2(0, -16), Color.WHITE, 10)


## 嫌疑人：可见时为红色目标卡；失去视线后显示最后位置 + 逐渐扩大的推算搜索圈
func _draw_suspect(sp: Suspect, t: float, vr: Rect2) -> void:
	var sel: bool = UIKit.same(game.selected, sp)
	var hv: bool = UIKit.same(hover, sp)
	if sp.state != Suspect.S.FLEE:
		var a := clampf(1.0 - sp.fade / 6.0, 0.0, 1.0)
		var p0 := _p(sp.pos)
		var col := UIKit.GREEN if sp.state == Suspect.S.CAUGHT else UIKit.TEXT_MUTED
		UIKit.draw_hex(self, p0, 14, UIKit.with_alpha(col.darkened(0.3), a), UIKit.with_alpha(Color.WHITE, a), 1.5)
		UIKit.draw_icon(self, "check_circle" if sp.state == Suspect.S.CAUGHT else "directions_run", p0, 16, UIKit.with_alpha(Color.WHITE, a))
		_pill("已抓获" if sp.state == Suspect.S.CAUGHT else "已逃脱", p0 + Vector2(0, 24), UIKit.with_alpha(col, a), 11)
		return
	if sp.seen:
		var p := _p(sp.pos)
		if not vr.grow(-24).has_point(p):
			_offscreen(p, UIKit.RED, "directions_run", vr)
			return
		# 锁定框
		var R := 18.0 + (2.0 if sel or hv else 0.0)
		var ph := fmod(t * 1.6, 1.0)
		draw_arc(p, R + 6 + ph * 16.0, 0, TAU, 40, UIKit.with_alpha(UIKit.RED, 0.7 * (1.0 - ph)), 2.0, true)
		for k in 4:
			var a := k * PI * 0.5 + PI * 0.25
			var d := Vector2(cos(a), sin(a))
			var c := p + d * (R + 4)
			draw_line(c, c - d * 7 + d.orthogonal() * 7, Color.WHITE, 2.0, true)
			draw_line(c, c - d * 7 - d.orthogonal() * 7, Color.WHITE, 2.0, true)
		# 逃窜方向
		var hd := _p(sp.pos + sp.heading() * 30.0) - p
		if hd.length() > 1.0:
			var dir := hd.normalized()
			var tip := p + dir * (R + 16)
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * 9 + dir.orthogonal() * 5, tip - dir * 9 - dir.orthogonal() * 5]), UIKit.RED)
		UIKit.draw_hex(self, p, R, UIKit.RED.darkened(0.1), Color.WHITE if (sel or hv) else UIKit.RED.lightened(0.4), 2.0)
		UIKit.draw_icon(self, "directions_run", p, int(R * 1.1), Color.WHITE)
		_pill("嫌疑人 · %s" % sp.last_seen_by, p + Vector2(0, R + 16), UIKit.RED, 11)
	else:
		var p := _p(sp.last_seen)
		if not vr.grow(-24).has_point(p):
			_offscreen(p, UIKit.AMBER, "directions_run", vr)
			return
		var rw := minf(sp.seen_age * sp.speed / Data.MIN_PER_SEC * 0.8, 380.0)
		var rr := maxf(_sr(sp.last_seen, rw), 14.0)
		draw_circle(p, rr, Color(1.0, 0.55, 0.15, 0.07))
		var n := 60
		for k in n:
			if k % 2 == 0:
				draw_arc(p, rr, TAU * k / n - t * 0.15, TAU * (k + 1) / n - t * 0.15, 3, Color(1.0, 0.6, 0.2, 0.65), 1.5, true)
		UIKit.draw_hex(self, p, 14, Color(0.35, 0.18, 0.05, 0.9), Color.WHITE if (sel or hv) else UIKit.AMBER, 2.0)
		UIKit.draw_text_c(self, "?", p, 16, Color.WHITE)
		_pill("最后发现 %s" % UIKit.fmt_min(sp.seen_age), p + Vector2(0, 30), UIKit.AMBER, 11)


func _placing_cursor(t: float) -> void:
	var m := get_viewport().get_mouse_position()
	var g := game.cam.ground_point(m)
	var near := game.city.graph.nearest_edge_point(g)
	var ok: bool = near.d <= 30.0
	var w := game.city.graph.point_on_edge(near.edge, near.t) if ok else g
	var p := _p(w)
	var col := UIKit.CYAN if ok else UIKit.RED
	var r := _sr(w, Ops.CHECKPOINT_RANGE + 4.0)
	draw_arc(p, r + fmod(t * 20.0, 6.0), 0, TAU, 32, col, 2.0, true)
	UIKit.draw_icon(self, "front_hand", p, 18, col)
	_pill("设卡 %s" % Data.money_str(Ops.CHECKPOINT_COST) if ok else "请点在道路上", p + Vector2(0, -r - 14), col, 11)


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
