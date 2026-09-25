class_name MapPainter
extends Node2D
## 在 SubViewport 中以世界坐标（米）绘制高清地面贴图。

var map: CityMap
var _samples := {}


func _draw() -> void:
	var W := map.world_rect
	draw_rect(W.grow(80), CityMap.C_LAND)
	# 街区：人行道铺装 + 路缘
	for b in map.blocks:
		var o: PackedVector2Array = b.outer
		draw_colored_polygon(o, CityMap.C_SIDEWALK)
	# 地块底色、绿地、广场、停车场
	for p in map.patches:
		if p.poly.size() >= 3:
			draw_colored_polygon(p.poly, p.color)
		if p.has("parking"):
			_parking(p.parking)
	for t in map.tracks:
		_track(t)
	for pa in map.paths:
		_round_polyline(pa.pts, pa.color, pa.w)
	# 路缘线
	for b in map.blocks:
		var o: PackedVector2Array = b.outer.duplicate()
		o.append(o[0])
		draw_polyline(o, CityMap.C_CURB, 0.45, true)
	# 江岸石砌护岸
	var rv := map.river_poly.duplicate()
	if rv.size() > 2:
		rv.append(rv[0])
		draw_polyline(rv, CityMap.C_BANK, 5.0, true)
		draw_polyline(rv, CityMap.C_BANK.darkened(0.25), 1.0, true)
	# 道路：先铺所有沥青，再画标线
	var order := map.roads.duplicate()
	order.sort_custom(func(a, b): return a.w < b.w)
	for r in order:
		_round_polyline(r.pts, CityMap.C_ASPHALT if r.cls != "D" else CityMap.C_ASPHALT_D.lightened(0.12), r.w)
	for j in map.junctions:
		if j.r >= 6.0:
			draw_circle(j.p, j.r - 1.0, CityMap.C_ASPHALT)
	for r in map.roads:
		_markings(r)
	for j in map.junctions:
		_crosswalks(j)
	_boundary()


func _round_polyline(pts: PackedVector2Array, c: Color, w: float) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, c, w, true)
	for p in pts:
		draw_circle(p, w * 0.5, c)


## 沿道路每 1 米采样：位置、法线、是否在路口范围内、累计里程
func _sample(r: Dictionary) -> Array:
	var out: Array = []
	var pts: PackedVector2Array = r.pts
	var acc := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var L := a.distance_to(b)
		if L < 0.01:
			continue
		var d := (b - a) / L
		var n := Vector2(-d.y, d.x)
		var s := 0.0
		while s < L:
			var p := a + d * s
			var near := false
			for j in map.junctions:
				if p.distance_to(j.p) < j.r + 5.5:
					near = true
					break
			out.append([p, n, near, acc + s])
			s += 1.0
		acc += L
	return out


func _markings(r: Dictionary) -> void:
	if r.cls == "D":
		return
	var smp := _sample(r)
	var hw: float = r.w * 0.5
	match r.cls:
		"A":
			_line(smp, hw - 1.0, CityMap.C_LINE, 0.22)
			_line(smp, -(hw - 1.0), CityMap.C_LINE, 0.22)
			_line(smp, 0.28, CityMap.C_YELLOW, 0.2)
			_line(smp, -0.28, CityMap.C_YELLOW, 0.2)
			for off in [4.0, 7.6]:
				_line(smp, off, CityMap.C_LINE, 0.18, 4.0, 6.0)
				_line(smp, -off, CityMap.C_LINE, 0.18, 4.0, 6.0)
		"B":
			_line(smp, hw - 0.9, CityMap.C_LINE, 0.2)
			_line(smp, -(hw - 0.9), CityMap.C_LINE, 0.2)
			_line(smp, 0.24, CityMap.C_YELLOW, 0.18)
			_line(smp, -0.24, CityMap.C_YELLOW, 0.18)
			_line(smp, 4.0, CityMap.C_LINE, 0.16, 4.0, 6.0)
			_line(smp, -4.0, CityMap.C_LINE, 0.16, 4.0, 6.0)
		"C":
			_line(smp, hw - 0.7, CityMap.C_LINE, 0.16)
			_line(smp, -(hw - 0.7), CityMap.C_LINE, 0.16)
			_line(smp, 0.0, CityMap.C_YELLOW, 0.16, 3.0, 4.0)


func _line(smp: Array, off: float, c: Color, w: float, on := 0.0, gap := 0.0) -> void:
	var run := PackedVector2Array()
	for s in smp:
		var vis: bool = not s[2]
		if vis and on > 0.0:
			vis = fmod(s[3], on + gap) < on
		if vis:
			run.append(s[0] + s[1] * off)
		elif run.size() > 0:
			if run.size() >= 2:
				draw_polyline(run, c, w, true)
			run = PackedVector2Array()
	if run.size() >= 2:
		draw_polyline(run, c, w, true)


func _crosswalks(j: Dictionary) -> void:
	var g := map.graph
	var node: int = j.node
	var c: Vector2 = j.p
	var jr: float = j.r
	for nb in g.adj[node]:
		var e := g.edge_between(node, nb)
		var w: float = g.edges[e].width
		if w < 10.0:
			continue
		var q := Vector2(g.positions[nb].x, g.positions[nb].z)
		var d := (q - c).normalized()
		var n := Vector2(-d.y, d.x)
		var center := c + d * (jr + 2.6)
		var half := w * 0.5 - 1.2
		var t := -half
		while t < half:
			var sc := center + n * (t + 0.3)
			var poly := PackedVector2Array([sc - d * 1.6 - n * 0.3, sc + d * 1.6 - n * 0.3, sc + d * 1.6 + n * 0.3, sc - d * 1.6 + n * 0.3])
			draw_colored_polygon(poly, CityMap.C_LINE)
			t += 1.1
		# 停止线（右侧车道）
		var sl := c + d * (jr + 4.9)
		draw_line(sl + n * 0.4, sl + n * (w * 0.5 - 1.0), CityMap.C_LINE, 0.4, true)


func _parking(pk: Dictionary) -> void:
	var c: Vector2 = pk.c
	var side: Vector2 = pk.side
	var front: Vector2 = pk.front
	var hs: float = pk.hs
	var n := clampi(int(hs * 2.0 / 4.6), 3, 8)
	for k in n + 1:
		var t := -1.0 + 2.0 * k / n
		var p := c + side * hs * t
		draw_line(p - front * 5.0, p + front * 3.0, CityMap.C_LINE, 0.18, true)
	draw_line(c - front * 5.0 - side * hs, c - front * 5.0 + side * hs, CityMap.C_LINE, 0.18, true)


func _stadium(t: Dictionary, a: float, b: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c: Vector2 = t.c
	var u: Vector2 = t.u
	var v: Vector2 = t.v
	var straight := maxf(a - b, 0.0)
	for k in 17:
		var ang := -PI * 0.5 + PI * k / 16.0
		pts.append(c + u * (straight + cos(ang) * b) + v * sin(ang) * b)
	for k in 17:
		var ang := PI * 0.5 + PI * k / 16.0
		pts.append(c + u * (-straight + cos(ang) * b) + v * sin(ang) * b)
	return pts


func _track(t: Dictionary) -> void:
	var outer := _stadium(t, t.a, t.b)
	var inner := _stadium(t, t.a - 7.0, t.b - 7.0)
	draw_colored_polygon(outer, CityMap.C_TRACK)
	draw_colored_polygon(inner, CityMap.C_GRASS)
	for k in range(1, 6):
		var lane := _stadium(t, t.a - k * 1.2, t.b - k * 1.2)
		lane.append(lane[0])
		draw_polyline(lane, Color(1, 1, 1, 0.75), 0.12, true)
	var fc := _stadium(t, t.a - 18.0, t.b - 14.0)
	if fc.size() > 2:
		fc.append(fc[0])
		draw_polyline(fc, Color(1, 1, 1, 0.7), 0.15, true)


func _boundary() -> void:
	var P := map.play_rect
	var pts := [P.position, Vector2(P.end.x, P.position.y), P.end, Vector2(P.position.x, P.end.y), P.position]
	for k in 4:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var L := a.distance_to(b)
		var d := (b - a) / L
		var s := 0.0
		while s < L:
			draw_line(a + d * s, a + d * minf(s + 10.0, L), Color(0.12, 0.3, 0.75, 0.85), 1.6, true)
			s += 16.0
