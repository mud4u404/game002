class_name MapPainter
extends Node2D
## 战术图地面贴图（参照《112》）：统一深蓝底 + 细密建筑轮廓 + 分级发光道路 + 发光江岸。

var map: CityMap

const BLD_LOW := Color("0c214d")
const BLD_HIGH := Color("183a7a")
const BLD_EDGE := Color("234c9c")
const PARK_HATCH := Color("0f3a4c")


func _draw() -> void:
	var W := map.world_rect
	draw_rect(W.grow(80), CityMap.C_LAND)
	# 公园、跑道等特殊地块
	for p in map.patches:
		if p.poly.size() < 3:
			continue
		var c: Color = p.color
		if c == CityMap.C_LAND or p.get("water", false):
			continue
		draw_colored_polygon(p.poly, c)
		if c == CityMap.C_GRASS or c == CityMap.C_GRASS_D:
			_hatch(p.poly, PARK_HATCH, 3.2)
	for t in map.tracks:
		_track(t)
	# 江岸光带
	var rv := map.river_poly.duplicate()
	if rv.size() > 2:
		rv.append(rv[0])
		draw_polyline(rv, Color(0.24, 0.55, 1.0, 0.12), 14.0, true)
		draw_polyline(rv, Color(0.24, 0.55, 1.0, 0.3), 5.0, true)
		draw_polyline(rv, CityMap.C_BANK, 1.6, true)
	# 建筑：按高度渐亮的暗蓝填充 + 细描边
	for b in map.buildings:
		var poly: PackedVector2Array = b.poly
		if poly.size() < 3:
			continue
		var h: float = b.h / CityMap.HEIGHT_SCALE
		var k := clampf(h / 90.0, 0.0, 1.0)
		var fill := BLD_LOW.lerp(BLD_HIGH, k)
		var edge := BLD_EDGE.lerp(Color("3a6fd0"), k * 0.6)
		if b.style == "police":
			fill = Color("1d4fb8")
			edge = Color("6fb0ff")
		draw_colored_polygon(poly, fill)
		var ol := poly.duplicate()
		ol.append(poly[0])
		draw_polyline(ol, edge, 0.55, true)
	# 道路：外层柔光 + 内芯；等级越高越亮越宽
	var order := map.roads.duplicate()
	order.sort_custom(func(a, b): return a.w < b.w)
	for r in order:
		match r.cls:
			"A":
				_round_polyline(r.pts, Color(0.2, 0.5, 1.0, 0.1), 20.0)
				_round_polyline(r.pts, Color(0.25, 0.55, 1.0, 0.22), 9.0)
			"B":
				_round_polyline(r.pts, Color(0.2, 0.45, 1.0, 0.1), 11.0)
	for r in order:
		var spec: Array = {"A": [Color("5aa2ff"), 4.2], "B": [Color("2f6fe0"), 3.0], "C": [Color("1d4aa6"), 2.2], "D": [Color("163a82"), 1.5]}[r.cls]
		_round_polyline(r.pts, spec[0], spec[1])
	for r in order:
		if r.cls == "A":
			_round_polyline(r.pts, Color("c7e2ff"), 1.1)
	_boundary()


func _round_polyline(pts: PackedVector2Array, c: Color, w: float) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, c, w, true)
	for p in pts:
		draw_circle(p, w * 0.5, c)


## 斜线填充纹理（公园）
func _hatch(poly: PackedVector2Array, c: Color, spacing: float) -> void:
	var bb := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		bb = bb.expand(v)
	var d := Vector2(1, -1).normalized()
	var n := Vector2(1, 1).normalized()
	var lo := INF
	var hi := -INF
	for v in [bb.position, bb.end, Vector2(bb.position.x, bb.end.y), Vector2(bb.end.x, bb.position.y)]:
		lo = minf(lo, v.dot(n))
		hi = maxf(hi, v.dot(n))
	var s := lo
	var L := bb.size.length() + 10.0
	while s < hi:
		var c0: Vector2 = n * s
		var seg := PackedVector2Array([c0 - d * L, c0 + d * L])
		for part in Geometry2D.intersect_polyline_with_polygon(seg, poly):
			if part.size() >= 2:
				draw_line(part[0], part[part.size() - 1], c, 0.5, true)
		s += spacing


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
	var ol := outer.duplicate()
	ol.append(outer[0])
	draw_polyline(ol, BLD_EDGE, 0.6, true)


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
			draw_line(a + d * s, a + d * minf(s + 8.0, L), Color(0.35, 0.65, 1.0, 0.55), 1.2, true)
			s += 14.0
