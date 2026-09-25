class_name CityMap
extends Node3D
## 由 MapData 生成辖区地图：
##   道路折线 → 求交成平面图 → 提取街区面 → 扣除道路/江面缓冲 → 按分区切地块、生成建筑
##   2D 高清地面贴图（沥青、路缘、人行道、标线、斑马线、停车场、跑道、公园小径）
##   3D：挤出建筑（真实阴影）、江面、桥、行道树、夜间路灯光照贴图

signal ready_to_show

const TEX_W := 4096
const HEIGHT_SCALE := 0.3
## 地图保持干净：不画树与屋顶设备，让玩家专注于警力部署
const DECOR := false
const SIDEWALK := 3.2
const LM_W := 1024

# 调色板（白天基准，夜间由场景光照压暗）
const C_LAND := Color("081633")
const C_SIDEWALK := Color("0a1a3d")
const C_CURB := Color("143068")
const C_ASPHALT := Color("2d5fbf")
const C_ASPHALT_D := Color("1d4390")
const C_LINE := Color("ffffff")
const C_YELLOW := Color("6fa0ff")
const C_GRASS := Color("0a2a40")
const C_GRASS_D := Color("0a283d")
const C_COMPOUND := Color("0b1d41")
const C_PLAZA := Color("0a1a3d")
const C_OLDTOWN := Color("0b1b3f")
const C_PARKING := Color("0e2350")
const C_TRACK := Color("143266")
const C_BANK := Color("3a78e0")
const C_WATER_EDGE := Color("1b4a8f")

var graph := RoadGraph.new()
var rng := RandomNumberGenerator.new()
var facilities: Array = []
var roads: Array = []          # {name, cls, w, pts: PackedVector2Array}
var blocks: Array = []         # {outer, inner, zone, centroid}
var buildings: Array = []      # {poly, h, style, color}
var patches: Array = []        # {poly, color}
var paths: Array = []          # {pts, w, color}
var tracks: Array = []         # {c, u, v, a, b}
var trees: Array = []          # Vector3 + scale
var lights: Array = []         # [Vector2, radius, Color, intensity]
var river_poly := PackedVector2Array()
var bridges: Array = []        # PackedVector2Array
var junctions: Array = []      # {p: Vector2, r: float, deg: int}
var play_rect := MapData.PLAY
var world_rect := MapData.WORLD
var ground_tex: Texture2D
var lightmap_tex: Texture2D
var ground_mat: ShaderMaterial
var building_mat: ShaderMaterial

var _pts: Array = []           # 节点 2D 坐标（含边界）
var _adj_all: Array = []       # 平面图邻接（含边界）
var _node_index := {}
var _nav_node := {}            # 平面图节点 -> 导航图节点


# ================================================================== 入口
func build(seed_value: int) -> void:
	rng.seed = seed_value
	var t := Time.get_ticks_msec()
	_prepare_roads()
	_build_planar_graph()
	_lap("graph", t)
	river_poly = _buffer(PackedVector2Array(MapData.RIVER), MapData.RIVER_W * 0.5, Geometry2D.END_SQUARE)
	_extract_blocks()
	_lap("blocks", t)
	for b in blocks:
		_populate(b)
	_place_facilities()
	_lap("populate", t)
	_street_trees_and_lights()
	_lap("trees", t)
	_build_3d()
	_lap("3d", t)
	await _paint_ground()
	_lap("paint", t)
	await _paint_lightmap()
	_lap("lightmap", t)
	ground_mat.set_shader_parameter("map_tex", ground_tex)
	for m in [ground_mat, building_mat]:
		m.set_shader_parameter("lightmap", lightmap_tex)
	ready_to_show.emit()


func _lap(name: String, t0: int) -> void:
	if OS.is_debug_build():
		print("[map] %s %d ms" % [name, Time.get_ticks_msec() - t0])


# ================================================================== 道路与平面图
func _prepare_roads() -> void:
	for r in MapData.ROADS:
		var cls: Dictionary = MapData.CLASSES[r.cls]
		roads.append({"name": r.name, "cls": r.cls, "w": cls.w, "pts": PackedVector2Array(r.pts)})
	# 端点吸附：巷道等端点若靠近其他道路，投影到该道路上，保证连通
	for r in roads:
		for end in [0, r.pts.size() - 1]:
			var p: Vector2 = r.pts[end]
			var best := p
			var bd := 9.0
			for o in roads:
				if o == r:
					continue
				for k in o.pts.size() - 1:
					var q := Geometry2D.get_closest_point_to_segment(p, o.pts[k], o.pts[k + 1])
					var d := q.distance_to(p)
					if d < bd and d > 0.01:
						bd = d
						best = q
			r.pts[end] = best


func _node_at(p: Vector2) -> int:
	var key := Vector2i(roundi(p.x / 1.5), roundi(p.y / 1.5))
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var k2 := key + Vector2i(dx, dy)
			if _node_index.has(k2):
				var id: int = _node_index[k2]
				if _pts[id].distance_to(p) < 1.6:
					return id
	_pts.append(p)
	_adj_all.append([])
	var id := _pts.size() - 1
	_node_index[key] = id
	return id


func _link(a: int, b: int) -> void:
	if a == b:
		return
	if not (b in _adj_all[a]):
		_adj_all[a].append(b)
		_adj_all[b].append(a)


func _build_planar_graph() -> void:
	var W := world_rect
	var bound := PackedVector2Array([W.position, Vector2(W.end.x, W.position.y), W.end, Vector2(W.position.x, W.end.y), W.position])
	var lines: Array = []
	for r in roads:
		lines.append({"pts": r.pts, "road": r, "bound": false})
	lines.append({"pts": bound, "road": null, "bound": true})
	# 所有线段
	var segs: Array = []
	for li in lines.size():
		var pts: PackedVector2Array = lines[li].pts
		for k in pts.size() - 1:
			segs.append({"a": pts[k], "b": pts[k + 1], "line": li, "ts": [0.0, 1.0]})
	# 求交
	for i in segs.size():
		for j in range(i + 1, segs.size()):
			var s1: Dictionary = segs[i]
			var s2: Dictionary = segs[j]
			var x = Geometry2D.segment_intersects_segment(s1.a, s1.b, s2.a, s2.b)
			if x == null:
				continue
			var p: Vector2 = x
			s1.ts.append(_param(s1.a, s1.b, p))
			s2.ts.append(_param(s2.a, s2.b, p))
	# 端点落在其他线段上的 T 形路口
	for i in segs.size():
		for j in segs.size():
			if segs[i].line == segs[j].line:
				continue
			for end in [segs[i].a, segs[i].b]:
				var q := Geometry2D.get_closest_point_to_segment(end, segs[j].a, segs[j].b)
				if q.distance_to(end) < 0.05:
					segs[j].ts.append(_param(segs[j].a, segs[j].b, q))
	# 切分并建立节点
	var nav_edges: Array = []
	for s in segs:
		var ts: Array = s.ts
		ts.sort()
		var prev := -1
		for t in ts:
			var p: Vector2 = s.a.lerp(s.b, t)
			var id := _node_at(p)
			if prev >= 0 and prev != id:
				_link(prev, id)
				if not lines[s.line].bound:
					nav_edges.append([prev, id, lines[s.line].road])
			prev = id
	# 导航图：只保留世界范围内的道路
	var inside := W.grow(0.5)
	for e in nav_edges:
		var pa: Vector2 = _pts[e[0]]
		var pb: Vector2 = _pts[e[1]]
		if not (inside.has_point(pa) and inside.has_point(pb)):
			continue
		var na := _nav(e[0])
		var nb := _nav(e[1])
		graph.add_edge(na, nb, e[2].name, e[2].w)
	# 路口
	for n in _pts.size():
		if not _nav_node.has(n):
			continue
		var nid: int = _nav_node[n]
		var deg: int = graph.adj[nid].size()
		if deg >= 3:
			var r := 0.0
			for nb in graph.adj[nid]:
				var e := graph.edge_between(nid, nb)
				r = maxf(r, graph.edges[e].width * 0.5)
			junctions.append({"p": _pts[n], "r": r + 1.0, "deg": deg, "node": nid})


func _nav(n: int) -> int:
	if not _nav_node.has(n):
		_nav_node[n] = graph.add_node(Vector3(_pts[n].x, 0, _pts[n].y))
	return _nav_node[n]


func _param(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	return clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)


# ================================================================== 街区
func _faces() -> Array:
	# 每个节点的邻居按角度排序
	var order: Array = []
	for n in _pts.size():
		var nb: Array = _adj_all[n].duplicate()
		var c: Vector2 = _pts[n]
		nb.sort_custom(func(x, y): return (_pts[x] - c).angle() < (_pts[y] - c).angle())
		order.append(nb)
	var used := {}
	var faces: Array = []
	for u in _pts.size():
		for v in _adj_all[u]:
			var key := Vector2i(u, v)
			if used.has(key):
				continue
			var face := PackedVector2Array()
			var a: int = u
			var b: int = v
			var guard := 0
			while guard < 400:
				guard += 1
				used[Vector2i(a, b)] = true
				face.append(_pts[a])
				var nb: Array = order[b]
				var i := nb.find(a)
				var c: int = nb[(i - 1 + nb.size()) % nb.size()]
				a = b
				b = c
				if a == u and b == v:
					break
			if face.size() >= 3:
				faces.append(face)
	return faces


func _signed_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func _buffer(pts: PackedVector2Array, r: float, end := Geometry2D.END_ROUND) -> PackedVector2Array:
	var res := Geometry2D.offset_polyline(pts, r, Geometry2D.JOIN_ROUND, end)
	var best := PackedVector2Array()
	for p in res:
		if p.size() > best.size():
			best = p
	return best


func _subtract(pieces: Array, cutter: PackedVector2Array) -> Array:
	var out: Array = []
	var cb := _bbox(cutter)
	for p in pieces:
		if not _bbox(p).intersects(cb):
			out.append(p)
			continue
		for q in Geometry2D.clip_polygons(p, cutter):
			if not Geometry2D.is_polygon_clockwise(q) == Geometry2D.is_polygon_clockwise(p):
				continue
			if absf(_signed_area(q)) > 25.0:
				out.append(q)
	return out


func _bbox(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


func _centroid(p: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	for i in p.size():
		var p0 := p[i]
		var p1 := p[(i + 1) % p.size()]
		var cr := p0.x * p1.y - p1.x * p0.y
		a += cr
		c += (p0 + p1) * cr
	if absf(a) < 0.001:
		var s := Vector2.ZERO
		for v in p:
			s += v
		return s / p.size()
	return c / (3.0 * a)


func _extract_blocks() -> void:
	var faces := _faces()
	# 丢弃外轮廓面（面积最大者）与退化面
	var max_i := -1
	var max_a := 0.0
	for i in faces.size():
		var a := absf(_signed_area(faces[i]))
		if a > max_a:
			max_a = a
			max_i = i
	var road_cut_outer: Array = []
	var road_cut_inner: Array = []
	for r in roads:
		road_cut_outer.append(_buffer(r.pts, r.w * 0.5))
		road_cut_inner.append(_buffer(r.pts, r.w * 0.5 + SIDEWALK))
	var river_outer := _buffer(PackedVector2Array(MapData.RIVER), MapData.RIVER_W * 0.5 + 3.0, Geometry2D.END_SQUARE)
	var river_inner := _buffer(PackedVector2Array(MapData.RIVER), MapData.RIVER_W * 0.5 + 7.0, Geometry2D.END_SQUARE)
	for i in faces.size():
		if i == max_i:
			continue
		var f: PackedVector2Array = faces[i]
		if absf(_signed_area(f)) < 60.0:
			continue
		if Geometry2D.is_polygon_clockwise(f):
			f.reverse()
		var outer: Array = [f]
		for c in road_cut_outer:
			outer = _subtract(outer, c)
		outer = _subtract(outer, river_outer)
		for o in outer:
			var inner: Array = [o]
			for c in road_cut_inner:
				inner = _subtract(inner, c)
			inner = _subtract(inner, river_inner)
			var ip := PackedVector2Array()
			var ia := 0.0
			for q in inner:
				var a := absf(_signed_area(q))
				if a > ia:
					ia = a
					ip = q
			var cen := _centroid(o)
			blocks.append({"outer": o, "inner": ip, "zone": _zone_for(cen), "centroid": cen, "area": absf(_signed_area(o))})


func _zone_for(p: Vector2) -> String:
	for z in MapData.ZONES:
		if z.rect.has_point(p):
			return z.zone
	return "residential"


# ================================================================== 地块与建筑
class Box:
	var c := Vector2.ZERO
	var u := Vector2.RIGHT
	var v := Vector2.DOWN
	var hu := 1.0
	var hv := 1.0


## 最小面积有向包围盒；u 为长轴
func _obb(poly: PackedVector2Array) -> Box:
	var best := Box.new()
	var best_area := INF
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() < 0.5:
			continue
		var u := e.normalized()
		var v := Vector2(-u.y, u.x)
		var umin := INF
		var umax := -INF
		var vmin := INF
		var vmax := -INF
		for p in poly:
			var pu := p.dot(u)
			var pv := p.dot(v)
			umin = minf(umin, pu)
			umax = maxf(umax, pu)
			vmin = minf(vmin, pv)
			vmax = maxf(vmax, pv)
		var area := (umax - umin) * (vmax - vmin)
		if area < best_area:
			best_area = area
			best.c = u * (umin + umax) * 0.5 + v * (vmin + vmax) * 0.5
			best.u = u
			best.v = v
			best.hu = (umax - umin) * 0.5
			best.hv = (vmax - vmin) * 0.5
	if best_area == INF:
		best.c = _centroid(poly)
	if best.hv > best.hu:
		var ou := best.u
		best.u = best.v
		best.v = -ou
		var t := best.hu
		best.hu = best.hv
		best.hv = t
	return best


func _rect(c: Vector2, u: Vector2, v: Vector2, hu: float, hv: float) -> PackedVector2Array:
	return PackedVector2Array([c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv])


func _split(poly: PackedVector2Array, target: float, min_w: float, depth := 0) -> Array:
	var area := absf(_signed_area(poly))
	var o := _obb(poly)
	if area <= target or depth > 9 or o.hu < min_w:
		return [poly]
	var cut := o.c + o.u * o.hu * rng.randf_range(-0.18, 0.18)
	var big := 4000.0
	var half_a := _rect(cut - o.u * big * 0.5, o.u, o.v, big * 0.5, big)
	var half_b := _rect(cut + o.u * big * 0.5, o.u, o.v, big * 0.5, big)
	var out: Array = []
	for h in [half_a, half_b]:
		for piece in Geometry2D.intersect_polygons(poly, h):
			if absf(_signed_area(piece)) > 20.0:
				out.append_array(_split(piece, target, min_w, depth + 1))
	return out


func _inset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(poly, -d, Geometry2D.JOIN_MITER)
	var best := PackedVector2Array()
	var ba := 0.0
	for p in res:
		var a := absf(_signed_area(p))
		if a > ba:
			ba = a
			best = p
	return best


func _inside(poly: PackedVector2Array, pts: PackedVector2Array) -> bool:
	for p in pts:
		if not Geometry2D.is_point_in_polygon(p, poly):
			return false
	return true


func _add_building(poly: PackedVector2Array, h: float, style: String, color: Color) -> void:
	if poly.size() < 3 or absf(_signed_area(poly)) < 12.0:
		return
	buildings.append({"poly": poly, "h": h * HEIGHT_SCALE, "style": style, "color": color})


func _pick(colors: Array) -> Color:
	var c: Color = colors[rng.randi() % colors.size()]
	return c.lightened(rng.randf_range(-0.04, 0.05))


func _populate(b: Dictionary) -> void:
	var inner: PackedVector2Array = b.inner
	if inner.size() < 3:
		return
	var area := absf(_signed_area(inner))
	for f in MapData.FACILITIES:
		if Geometry2D.is_point_in_polygon(f.at, inner):
			b["facility"] = f
			return
	_fill_zone(b, inner, b.zone, area)


func _fill_zone(b: Dictionary, inner: PackedVector2Array, zone: String, area: float) -> void:
	match zone:
		"oldtown":
			patches.append({"poly": inner, "color": C_OLDTOWN})
			for lot in _split(inner, rng.randf_range(380.0, 650.0), 9.0):
				if rng.randf() < 0.1:
					continue
				var bp := _inset(lot, 1.2)
				_add_building(bp, rng.randf_range(7.0, 12.0), "tile", _pick([Color("132c63"), Color("142e66")]))
		"cbd":
			patches.append({"poly": inner, "color": C_PLAZA})
			var o := _obb(inner)
			var pod := _inset(inner, 5.0)
			if pod.size() >= 3:
				_add_building(pod, rng.randf_range(16.0, 26.0), "podium", _pick([Color("15306a"), Color("16316c")]))
				var core := _inset(pod, 3.0)
				var n := 2 if o.hu > 70.0 else 1
				for k in n:
					var off := 0.0 if n == 1 else (-o.hu * 0.42 if k == 0 else o.hu * 0.42)
					var tw := clampf(o.hv * 0.7, 16.0, 34.0)
					var tu := clampf(tw * rng.randf_range(1.0, 1.35), 16.0, o.hu * (0.95 if n == 1 else 0.5))
					var t := _rect(o.c + o.u * off, o.u, o.v, tu * 0.5, tw * 0.5)
					var best := PackedVector2Array()
					var ba := 0.0
					if core.size() >= 3:
						for q in Geometry2D.intersect_polygons(t, core):
							var a := absf(_signed_area(q))
							if a > ba:
								ba = a
								best = q
					if ba > 220.0:
						_add_building(best, rng.randf_range(110.0, 210.0), "tower", _pick([Color("1c3b80"), Color("1d3d84")]))
			_trees_along(inner, 10.0, 2.5)
		"commercial":
			patches.append({"poly": inner, "color": C_PLAZA.darkened(0.03)})
			for lot in _split(inner, rng.randf_range(600.0, 1200.0), 14.0):
				var bp := _inset(lot, 1.8)
				_add_building(bp, rng.randf_range(14.0, 48.0), "flat", _pick([Color("142e66"), Color("152f69")]))
		"residential":
			_residential(b, inner, area)
		"park":
			_park(inner)
		"riverside":
			_riverside(inner)
		"school":
			_school(inner)
		_:
			_residential(b, inner, area)


func _residential(_b: Dictionary, inner: PackedVector2Array, area: float) -> void:
	var comp := _inset(inner, 5.0)
	patches.append({"poly": inner, "color": C_PLAZA.darkened(0.04)})
	if comp.size() < 3:
		return
	patches.append({"poly": comp, "color": C_COMPOUND})
	# 小区内部环路
	var ring := _inset(comp, 3.5)
	if ring.size() >= 3:
		var rp := ring.duplicate()
		rp.append(ring[0])
		pass
	var bb := _bbox(comp)
	var placed := 0
	var roof := [Color("142e67"), Color("15306a")]
	# 南北朝向的板楼行列
	var z := bb.position.y + 9.0
	while z + 12.0 < bb.end.y - 6.0:
		var x := bb.position.x + rng.randf_range(6.0, 12.0)
		while x < bb.end.x - 20.0:
			var L := rng.randf_range(34.0, 58.0)
			var r := PackedVector2Array([Vector2(x, z), Vector2(x + L, z), Vector2(x + L, z + 12.5), Vector2(x, z + 12.5)])
			if _inside(comp, r):
				_add_building(r, rng.randi_range(11, 32) * 3.0, "slab", _pick(roof))
				placed += 1
				x += L + rng.randf_range(12.0, 18.0)
			else:
				x += 6.0
		# 楼间绿地的树
		for k in 3:
			var tp := Vector2(rng.randf_range(bb.position.x, bb.end.x), z + 12.5 + rng.randf_range(6.0, 18.0))
			if Geometry2D.is_point_in_polygon(tp, comp):
				_add_tree(tp, rng.randf_range(0.9, 1.3))
		z += rng.randf_range(34.0, 40.0)
	if placed == 0:
		for lot in _split(comp, 500.0, 12.0):
			var bp := _inset(lot, 2.5)
			_add_building(bp, rng.randi_range(6, 18) * 3.0, "slab", _pick(roof))
	_trees_along(inner, 11.0, 2.0)


func _park(inner: PackedVector2Array) -> void:
	patches.append({"poly": inner, "color": C_GRASS})
	var o := _obb(inner)
	# 环形园路 + 中心水池
	var ring := _inset(inner, 9.0)
	if ring.size() >= 3:
		var rp := ring.duplicate()
		rp.append(ring[0])
		pass
	var pond := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		var rr := 1.0 + 0.18 * sin(a * 3.0 + 1.0)
		pond.append(o.c + o.u * cos(a) * o.hu * 0.35 * rr + o.v * sin(a) * o.hv * 0.4 * rr)
	patches.append({"poly": pond, "color": C_WATER_EDGE, "water": true})
	_tree_in(inner, 70, pond)


func _riverside(inner: PackedVector2Array) -> void:
	patches.append({"poly": inner, "color": C_GRASS_D})
	var o := _obb(inner)
	# 滨江步道：沿长轴贯穿
	var pts := PackedVector2Array()
	for k in 25:
		var t := -1.0 + 2.0 * k / 24.0
		pts.append(o.c + o.u * o.hu * t + o.v * sin(t * 5.0 + o.c.x * 0.01) * o.hv * 0.25)
	_tree_in(inner, int(o.hu * 0.22))


func _school(inner: PackedVector2Array) -> void:
	patches.append({"poly": inner, "color": C_PLAZA})
	var o := _obb(inner)
	var bw := o.hv * 0.32
	var bldg := _rect(o.c - o.v * (o.hv - bw - 2.0), o.u, o.v, o.hu * 0.8, bw)
	if _inside(inner, bldg):
		_add_building(bldg, 18.0, "flat", Color("142e67"))
	var tc := o.c + o.v * (bw * 0.9)
	var ta := minf(o.hu * 0.72, 55.0)
	var tb := minf(o.hv - bw - 4.0, 30.0)
	if tb > 12.0:
		tracks.append({"c": tc, "u": o.u, "v": o.v, "a": ta, "b": tb})
	_trees_along(inner, 9.0, 2.0)


func _tree_in(poly: PackedVector2Array, count: int, avoid := PackedVector2Array()) -> void:
	var bb := _bbox(poly)
	var n := 0
	var tries := 0
	while n < count and tries < count * 8:
		tries += 1
		var p := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		if avoid.size() >= 3 and Geometry2D.is_point_in_polygon(p, avoid):
			continue
		_add_tree(p, rng.randf_range(0.8, 1.5))
		n += 1


func _trees_along(poly: PackedVector2Array, spacing: float, inset: float) -> void:
	var ring := _inset(poly, inset)
	if ring.size() < 3:
		return
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var L := a.distance_to(b)
		var n := int(L / spacing)
		for k in n:
			_add_tree(a.lerp(b, (k + 0.5) / n), rng.randf_range(0.8, 1.1))


func _add_tree(p: Vector2, s: float) -> void:
	if not DECOR:
		return
	trees.append(Vector3(p.x, s, p.y))


# ================================================================== 公安设施
func _place_facilities() -> void:
	for b in blocks:
		if not b.has("facility"):
			continue
		var f: Dictionary = b.facility
		var inner: PackedVector2Array = b.inner
		var o := _obb(inner)
		var cen3 := Vector3(o.c.x, 0, o.c.y)
		var near := graph.nearest_edge_point(cen3)
		var road_p := graph.point_on_edge(near.edge, near.t)
		var to_road := Vector2(road_p.x, road_p.z) - o.c
		var front: Vector2
		var side: Vector2
		var hf: float
		var hs: float
		if absf(to_road.dot(o.u)) > absf(to_road.dot(o.v)):
			front = o.u * signf(to_road.dot(o.u))
			side = o.v
			hf = o.hu
			hs = o.hv
		else:
			front = o.v * signf(to_road.dot(o.v))
			side = o.u
			hf = o.hv
			hs = o.hu
		# 设施只占临街的一块地，街区其余部分正常建设
		var lot_w := minf(hs, 30.0)
		var lot_d := minf(hf, 24.0)
		var lot_c := o.c + front * (hf - lot_d)
		var lot := _rect(lot_c, side, front, lot_w, lot_d)
		for q in Geometry2D.intersect_polygons(lot, inner):
			patches.append({"poly": q, "color": C_PLAZA.darkened(0.05)})
		var bdepth := minf(lot_d * 0.42, 9.0)
		var bwidth := minf(lot_w * 0.85, 22.0)
		var bc := lot_c - front * (lot_d - bdepth - 2.0)
		var bldg := _rect(bc, side, front, bwidth, bdepth)
		_add_building(bldg, 16.0 if f.type != "patrol_hq" else 22.0, "police", Color("2552a8"))
		var pdepth := minf(lot_d * 2.0 - bdepth * 2.0 - 6.0, 12.0)
		var pc := lot_c + front * (lot_d - pdepth * 0.5 - 1.0)
		var phs := minf(lot_w * 0.9, 26.0)
		var park := _rect(pc, side, front, phs, pdepth * 0.5)
		patches.append({"poly": park, "color": C_PARKING, "parking": {"c": pc, "side": side, "front": front, "hs": phs}})
		var spots: Array[Vector3] = []
		var n := clampi(int(phs * 2.0 / 4.6), 3, 8)
		for k in n:
			var t := -1.0 + (2.0 * k + 1.0) / n
			var sp := pc + side * phs * t
			spots.append(Vector3(sp.x, 0.1, sp.y))
		for rem in Geometry2D.clip_polygons(inner, lot):
			if absf(_signed_area(rem)) > 400.0:
				var zone: String = b.zone if b.zone != "riverside" else "park"
				_fill_zone(b, rem, zone, absf(_signed_area(rem)))
		var ed: Dictionary = graph.edges[near.edge]
		var yaw := atan2(-front.x, -front.y)
		facilities.append({
			"type": f.type, "name": f.name, "center": Vector3(bc.x, 0, bc.y), "spots": spots,
			"drive": road_p, "nodes": [ed.a, ed.b], "edge": near.edge, "yaw": yaw,
			"front": front, "roof_h": (16.0 if f.type != "patrol_hq" else 22.0) * HEIGHT_SCALE,
		})


# ================================================================== 行道树 / 路灯
func _street_trees_and_lights() -> void:
	for r in roads:
		var pts: PackedVector2Array = r.pts
		var w: float = r.w
		var cls: String = r.cls
		var acc := 0.0
		var lamp_side := 1.0
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var L := a.distance_to(b)
			var d := (b - a) / L
			var nrm := Vector2(-d.y, d.x)
			var s := 0.0
			while s < L:
				var p := a + d * s
				if not _near_junction(p, 6.0) and world_rect.has_point(p):
					var step_i := int((acc + s) / 9.0)
					if cls in ["A", "B"] and step_i % 1 == 0:
						for side in [-1.0, 1.0]:
							var tp: Vector2 = p + nrm * side * (w * 0.5 + 1.6)
							if not Geometry2D.is_point_in_polygon(tp, river_poly):
								_add_tree(tp, rng.randf_range(0.75, 0.95))
					if int((acc + s) / 27.0) != int((acc + s - 9.0) / 27.0) and cls != "D":
						var lp: Vector2 = p + nrm * lamp_side * (w * 0.5 - 1.0)
						var col := Color(1.0, 0.72, 0.42) if cls in ["C", "D"] else Color(0.95, 0.9, 0.82)
						lights.append([lp, 11.0 + w * 0.35, col, 0.9])
						lamp_side = -lamp_side
					if cls == "D" and int((acc + s) / 16.0) != int((acc + s - 9.0) / 16.0):
						lights.append([p, 7.0, Color(1.0, 0.66, 0.36), 0.8])
				s += 9.0
			acc += L
	# 商业与 CBD 沿街橱窗溢光
	for b in blocks:
		if not (b.zone in ["cbd", "commercial", "oldtown"]):
			continue
		var ring: PackedVector2Array = b.outer
		for i in ring.size():
			var a := ring[i]
			var c := ring[(i + 1) % ring.size()]
			var L := a.distance_to(c)
			var n := int(L / 8.0)
			for k in n:
				if rng.randf() < 0.45:
					continue
				var p := a.lerp(c, (k + 0.5) / n)
				var col := Color.from_hsv(rng.randf(), 0.25, 1.0) if rng.randf() < 0.4 else Color(1.0, 0.86, 0.66)
				lights.append([p, 5.0, col, 0.45 if b.zone != "oldtown" else 0.35])


func _near_junction(p: Vector2, extra: float) -> bool:
	for j in junctions:
		if p.distance_to(j.p) < j.r + extra:
			return true
	return false


# ================================================================== 3D 构建
func _build_3d() -> void:
	ground_mat = MeshKit.shader_mat("res://shaders/ground_map.gdshader")
	ground_mat.set_shader_parameter("world_rect", Vector4(world_rect.position.x, world_rect.position.y, world_rect.size.x, world_rect.size.y))
	ground_mat.set_shader_parameter("play_rect", Vector4(play_rect.position.x, play_rect.position.y, play_rect.size.x, play_rect.size.y))
	ground_mat.set_shader_parameter("detail", MeshKit.noise_texture(0.05, 256))
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = world_rect.size + Vector2(2000, 2000)
	ground.mesh = pm
	ground.position = Vector3(world_rect.get_center().x, 0, world_rect.get_center().y)
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	_build_water()
	_build_bridges()
	_build_buildings()
	_build_trees()


func _build_water() -> void:
	var clipped := Geometry2D.intersect_polygons(river_poly, _rect_poly(world_rect.grow(600)))
	var st := MeshKit.begin()
	for poly in clipped:
		_tri_fill(st, poly, 0.12)
	for p in patches:
		if p.get("water", false):
			_tri_fill(st, p.poly, 0.25)
	var water := MeshInstance3D.new()
	water.mesh = st.commit()
	var mat := MeshKit.shader_mat("res://shaders/water_map.gdshader")
	mat.set_shader_parameter("n1", MeshKit.noise_texture(0.03, 256, false))
	mat.set_shader_parameter("n2", MeshKit.noise_texture(0.06, 256, false))
	mat.set_shader_parameter("play_rect", Vector4(play_rect.position.x, play_rect.position.y, play_rect.size.x, play_rect.size.y))
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## 追加三角形，自动修正为 Godot 的顺时针正面（相对法线 n）
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, uv: Vector2) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uv)
		st.add_vertex(p)


func _tri_fill(st: SurfaceTool, poly: PackedVector2Array, y: float, color := Color.WHITE) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var b := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		_tri(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP, color, Vector2.ZERO)


func _build_bridges() -> void:
	var deck := MeshKit.begin()
	var rails := MeshKit.begin()
	for r in roads:
		var pts: PackedVector2Array = r.pts
		for k in pts.size() - 1:
			var seg := PackedVector2Array([pts[k], pts[k + 1]])
			var inter := Geometry2D.intersect_polyline_with_polygon(seg, river_poly)
			for part in inter:
				if part.size() < 2:
					continue
				var a: Vector2 = part[0]
				var b: Vector2 = part[part.size() - 1]
				var d := (b - a).normalized()
				a -= d * 6.0
				b += d * 6.0
				var w: float = r.w + 4.0
				var poly := _rect((a + b) * 0.5, d, Vector2(-d.y, d.x), a.distance_to(b) * 0.5, w * 0.5)
				bridges.append(poly)
				_tri_fill(deck, poly, 0.35)
				var n := Vector2(-d.y, d.x)
				for s in [-1.0, 1.0]:
					var c: Vector2 = (a + b) * 0.5 + n * s * (w * 0.5 - 0.4)
					var basis := Basis.looking_at(Vector3(d.x, 0, d.y), Vector3.UP)
					MeshKit.box(rails, Vector3(c.x, 0.9, c.y), Vector3(0.5, 1.1, a.distance_to(b)), Color(0.35, 0.6, 1.0), basis)
	var dm := MeshInstance3D.new()
	dm.mesh = deck.commit()
	dm.material_override = ground_mat
	add_child(dm)
	var rm := MeshInstance3D.new()
	rm.mesh = rails.commit()
	var rmat := StandardMaterial3D.new()
	rmat.vertex_color_use_as_albedo = true
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.material_override = rmat
	add_child(rm)


func _build_buildings() -> void:
	var st := MeshKit.begin()
	for b in buildings:
		var poly: PackedVector2Array = b.poly
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		var h: float = b.h
		var col: Color = b.color
		if b.style == "gable":
			_gable(st, b)
			continue
		var style_id: float = {"tile": 1.0, "podium": 2.0, "tower": 3.0, "flat": 4.0, "slab": 5.0, "police": 6.0}.get(b.style, 0.0)
		var y0 := 0.2
		var y1 := y0 + h
		# 墙面
		var cen := _centroid(poly)
		for i in poly.size():
			var a := poly[i]
			var c := poly[(i + 1) % poly.size()]
			var e := c - a
			var nrm := Vector3(e.y, 0, -e.x).normalized()
			var mid := (a + c) * 0.5
			if Vector2(nrm.x, nrm.z).dot(mid - cen) < 0.0 and Geometry2D.is_point_in_polygon(mid + Vector2(nrm.x, nrm.z) * 0.05, poly):
				nrm = -nrm
			var q0 := Vector3(a.x, y0, a.y)
			var q1 := Vector3(c.x, y0, c.y)
			var q2 := Vector3(c.x, y1, c.y)
			var q3 := Vector3(a.x, y1, a.y)
			_tri(st, q0, q1, q2, nrm, col.darkened(0.25), Vector2(style_id, 0.0))
			_tri(st, q0, q2, q3, nrm, col.darkened(0.25), Vector2(style_id, 0.0))
		# 屋顶（外沿 + 内缩层，形成女儿墙层次）
		_tri_fill_uv(st, poly, y1, col.darkened(0.1), Vector2(style_id, 1.0))
		var inset := _inset(poly, 0.9 if b.style != "tile" else 0.0)
		if b.style != "tile" and inset.size() >= 3:
			_tri_fill_uv(st, inset, y1 + 0.05, col, Vector2(style_id, 2.0))
			_roof_details(st, inset, y1 + 0.05, col, b.style)
		elif b.style == "tile":
			_tri_fill_uv(st, poly, y1 + 0.02, col, Vector2(style_id, 2.0))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	building_mat = MeshKit.shader_mat("res://shaders/building_map.gdshader")
	building_mat.set_shader_parameter("play_rect", Vector4(play_rect.position.x, play_rect.position.y, play_rect.size.x, play_rect.size.y))
	building_mat.set_shader_parameter("lm_rect", Vector4(world_rect.position.x, world_rect.position.y, world_rect.size.x, world_rect.size.y))
	mi.material_override = building_mat
	add_child(mi)


## 双坡屋顶小楼：墙体 + 沿长轴的屋脊
func _gable(st: SurfaceTool, b: Dictionary) -> void:
	var o: Box = b.obb
	var hu := o.hu * 0.96
	var hv := o.hv * 0.96
	var h: float = b.h
	var col: Color = b.color
	var y0 := 0.2
	var y1 := y0 + h
	var ridge_h := minf(hv * 0.55, 2.6)
	var c3 := func(p: Vector2, y: float) -> Vector3: return Vector3(p.x, y, p.y)
	var c := o.c
	var u := o.u
	var v := o.v
	var p00 := c - u * hu - v * hv
	var p10 := c + u * hu - v * hv
	var p11 := c + u * hu + v * hv
	var p01 := c - u * hu + v * hv
	var r0 := c - u * hu
	var r1 := c + u * hu
	var wall := col.darkened(0.3)
	# 四面墙
	var ring := [p00, p10, p11, p01]
	for i in 4:
		var a: Vector2 = ring[i]
		var bb: Vector2 = ring[(i + 1) % 4]
		var mid := (a + bb) * 0.5
		var n2 := (mid - c).normalized()
		var n := Vector3(n2.x, 0, n2.y)
		_tri(st, c3.call(a, y0), c3.call(bb, y0), c3.call(bb, y1), n, wall, Vector2(1, 0))
		_tri(st, c3.call(a, y0), c3.call(bb, y1), c3.call(a, y1), n, wall, Vector2(1, 0))
	# 山墙三角
	for e in [[p00, p01, r0, -u], [p10, p11, r1, u]]:
		var n := Vector3(e[3].x, 0, e[3].y)
		_tri(st, c3.call(e[0], y1), c3.call(e[1], y1), c3.call(e[2], y1 + ridge_h), n, wall, Vector2(1, 0))
	# 两坡屋面（略出挑）
	var ov := v * 0.35
	var ou := u * 0.35
	for side in [-1.0, 1.0]:
		var e0: Vector2 = c - u * hu - ou + v * hv * side + ov * side
		var e1: Vector2 = c + u * hu + ou + v * hv * side + ov * side
		var q0: Vector2 = r0 - ou
		var q1: Vector2 = r1 + ou
		var a: Vector3 = c3.call(e0, y1 - 0.15)
		var bq: Vector3 = c3.call(e1, y1 - 0.15)
		var cq: Vector3 = c3.call(q1, y1 + ridge_h)
		var dq: Vector3 = c3.call(q0, y1 + ridge_h)
		var n := (bq - a).cross(dq - a).normalized()
		if n.y < 0:
			n = -n
		var shade := col if side > 0 else col.darkened(0.06)
		_tri(st, a, bq, cq, n, shade, Vector2(1, 2))
		_tri(st, a, cq, dq, n, shade, Vector2(1, 2))


func _tri_fill_uv(st: SurfaceTool, poly: PackedVector2Array, y: float, color: Color, uv: Vector2) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var b := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		_tri(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP, color, uv)


func _roof_details(st: SurfaceTool, poly: PackedVector2Array, y: float, col: Color, style: String) -> void:
	if not DECOR:
		return
	var o := _obb(poly)
	var n := 0
	match style:
		"slab":
			n = int(o.hu / 9.0)
			for k in n:
				# 楼梯间 / 电梯机房
				var c: Vector2 = o.c + o.u * o.hu * (-0.8 + 1.6 * (k + 0.5) / n)
				_box_on_roof(st, c, o.u, o.v, 2.2, 2.6, y, 2.4, col.darkened(0.12))
		"tower":
			_box_on_roof(st, o.c, o.u, o.v, o.hu * 0.45, o.hv * 0.45, y, 3.0, col.darkened(0.18))
		_:
			var area := o.hu * o.hv * 4.0
			n = clampi(int(area / 90.0), 1, 10)
			for k in n:
				var c: Vector2 = o.c + o.u * o.hu * rng.randf_range(-0.7, 0.7) + o.v * o.hv * rng.randf_range(-0.6, 0.6)
				var tint := Color("9ea2a6") if rng.randf() < 0.7 else Color("d8d9d6")
				_box_on_roof(st, c, o.u, o.v, rng.randf_range(0.8, 2.4), rng.randf_range(0.8, 2.0), y, rng.randf_range(0.6, 1.6), tint)
			if area > 900.0 and rng.randf() < 0.6:
				# 采光天窗阵列
				var cols := int(o.hu / 5.0)
				for k in cols:
					var c2: Vector2 = o.c + o.u * o.hu * (-0.7 + 1.4 * (k + 0.5) / cols) + o.v * o.hv * 0.35
					_box_on_roof(st, c2, o.u, o.v, 1.4, o.hv * 0.18, y, 0.3, Color("6f7c88"))


func _box_on_roof(st: SurfaceTool, c: Vector2, u: Vector2, v: Vector2, hu: float, hv: float, y: float, h: float, col: Color) -> void:
	var basis := Basis(Vector3(u.x, 0, u.y), Vector3.UP, Vector3(v.x, 0, v.y))
	var pts := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
	var poly := PackedVector2Array(pts)
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	for i in 4:
		var a := poly[i]
		var b := poly[(i + 1) % 4]
		var e := b - a
		var nrm := Vector3(e.y, 0, -e.x).normalized()
		if Vector2(nrm.x, nrm.z).dot((a + b) * 0.5 - c) < 0.0:
			nrm = -nrm
		var q0 := Vector3(a.x, y, a.y)
		var q1 := Vector3(b.x, y, b.y)
		var q2 := Vector3(b.x, y + h, b.y)
		var q3 := Vector3(a.x, y + h, a.y)
		_tri(st, q0, q1, q2, nrm, col.darkened(0.2), Vector2.ZERO)
		_tri(st, q0, q2, q3, nrm, col.darkened(0.2), Vector2.ZERO)
	_tri_fill_uv(st, poly, y + h, col, Vector2(0, 2))
	var _unused := basis


func _build_trees() -> void:
	var mesh := ArrayMesh.new()
	var crown := SphereMesh.new()
	crown.radius = 3.0
	crown.height = 4.2
	crown.radial_segments = 9
	crown.rings = 5
	var st := MeshKit.begin()
	st.append_from(crown, 0, Transform3D(Basis.IDENTITY, Vector3(0, 5.0, 0)))
	st.append_from(crown, 0, Transform3D(Basis.from_scale(Vector3(0.6, 0.6, 0.6)), Vector3(1.1, 5.8, 0.6)))
	st.append_from(crown, 0, Transform3D(Basis.from_scale(Vector3(0.55, 0.55, 0.55)), Vector3(-1.0, 5.6, -0.8)))
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.albedo_color = Color.WHITE
	cmat.roughness = 0.95
	st.set_material(cmat)
	st.commit(mesh)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = trees.size()
	var greens := [Color("46612f"), Color("517037"), Color("3f5a2b"), Color("5a7a3e"), Color("3a5229"), Color("62783a")]
	for k in trees.size():
		var t: Vector3 = trees[k]
		var s: float = t.y
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.9, s))
		mm.set_instance_transform(k, Transform3D(basis, Vector3(t.x, 0.2, t.z)))
		mm.set_instance_color(k, greens[rng.randi() % greens.size()].lightened(rng.randf_range(-0.05, 0.08)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


# ================================================================== 2D 地面绘制
func _paint_ground() -> void:
	var tex_h := int(TEX_W * world_rect.size.y / world_rect.size.x)
	var vp := SubViewport.new()
	vp.size = Vector2i(TEX_W, tex_h)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.msaa_2d = Viewport.MSAA_4X
	vp.transparent_bg = false
	vp.disable_3d = true
	add_child(vp)
	var painter := MapPainter.new()
	painter.map = self
	var s := TEX_W / world_rect.size.x
	painter.scale = Vector2(s, s)
	painter.position = -world_rect.position * s
	vp.add_child(painter)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.generate_mipmaps()
	ground_tex = ImageTexture.create_from_image(img)
	vp.queue_free()


func _paint_lightmap() -> void:
	var tex_h := int(LM_W * world_rect.size.y / world_rect.size.x)
	var vp := SubViewport.new()
	vp.size = Vector2i(LM_W, tex_h)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = false
	vp.disable_3d = true
	add_child(vp)
	var painter := LightPainter.new()
	painter.lights = lights
	var s := LM_W / world_rect.size.x
	painter.scale = Vector2(s, s)
	painter.position = -world_rect.position * s
	vp.add_child(painter)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	lightmap_tex = ImageTexture.create_from_image(img)
	vp.queue_free()


# ================================================================== 查询
func random_incident_spot(r: RandomNumberGenerator) -> Dictionary:
	for attempt in 80:
		var e := r.randi() % graph.edges.size()
		var ed: Dictionary = graph.edges[e]
		var a: Vector3 = graph.positions[ed.a]
		var b: Vector3 = graph.positions[ed.b]
		var mid := (a + b) * 0.5
		if not play_rect.grow(-20).has_point(Vector2(mid.x, mid.z)):
			continue
		if ed.len < 12.0:
			continue
		if Geometry2D.is_point_in_polygon(Vector2(mid.x, mid.z), river_poly):
			continue
		var t := r.randf_range(0.2, 0.8)
		var dir := (b - a).normalized()
		var right := Vector3(-dir.z, 0, dir.x)
		var side := 1.0 if r.randf() < 0.5 else -1.0
		var road_p := a.lerp(b, t)
		var w: float = ed.width
		return {"edge": e, "t": t, "road_center": road_p, "road": road_p + right * side * RoadGraph.LANE_OFFSET,
			"pos": road_p + right * side * (w * 0.5 + 1.5), "desc": graph.describe(e, t)}
	return {}


## 地图上用于标注的道路名：辖区内每段足够长的路段各标一次
func road_labels() -> Array:
	var out: Array = []
	for r in roads:
		var pts: PackedVector2Array = r.pts
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var m := (a + b) * 0.5
			if not play_rect.grow(-12).has_point(m):
				continue
			if a.distance_to(b) < (70.0 if r.cls == "D" else 100.0):
				continue
			out.append({"name": r.name, "a": a, "b": b, "cls": r.cls})
	return out
