class_name RoadGraph
extends RefCounted
## 通用路网图：节点=路口/折点，边=路段。负责寻路、定位描述、车道偏移。

const LANE_OFFSET := 2.8

var positions: Array[Vector3] = []
var adj: Array = []            # node -> Array[int]
var edges: Array = []          # {a, b, len, name, road, width}
var node_roads: Array = []     # node -> Array[String]（经过该节点的道路名）
var edge_lookup := {}
var astar := AStar3D.new()


func add_node(p: Vector3) -> int:
	var id := positions.size()
	positions.append(p)
	adj.append([])
	node_roads.append([])
	astar.add_point(id, p)
	return id


func add_edge(a: int, b: int, road: String, width: float) -> int:
	var k := _key(a, b)
	if edge_lookup.has(k) or a == b:
		return edge_lookup.get(k, -1)
	var e := {"a": a, "b": b, "len": positions[a].distance_to(positions[b]), "name": road, "road": road, "width": width}
	edges.append(e)
	edge_lookup[k] = edges.size() - 1
	adj[a].append(b)
	adj[b].append(a)
	for n in [a, b]:
		if not (road in node_roads[n]):
			node_roads[n].append(road)
	astar.connect_points(a, b, true)
	return edges.size() - 1


func _key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func edge_between(a: int, b: int) -> int:
	return edge_lookup.get(_key(a, b), -1)


func is_inner_edge(_e: int) -> bool:
	return true


func nearest_node(p: Vector3, _inner_only := false) -> int:
	var best := 0
	var bd := INF
	for id in positions.size():
		if adj[id].is_empty():
			continue
		var d := positions[id].distance_squared_to(p)
		if d < bd:
			bd = d
			best = id
	return best


func nearest_edge_point(p: Vector3) -> Dictionary:
	var best := {"edge": 0, "t": 0.0, "d": INF}
	for e in edges.size():
		var a: Vector3 = positions[edges[e].a]
		var b: Vector3 = positions[edges[e].b]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := (a + ab * t).distance_to(p)
		if d < best.d:
			best = {"edge": e, "t": t, "d": d}
	return best


func path(a: int, b: int) -> PackedInt64Array:
	if a == b:
		return PackedInt64Array([a])
	return astar.get_id_path(a, b)


func path_length(ids: PackedInt64Array) -> float:
	var l := 0.0
	for k in range(1, ids.size()):
		l += positions[ids[k - 1]].distance_to(positions[ids[k]])
	return l


func point_on_edge(e: int, t: float) -> Vector3:
	return positions[edges[e].a].lerp(positions[edges[e].b], t)


## 路段上某点的中文位置描述：沿道路找最近的交叉路口
func describe(e: int, t: float) -> String:
	var road: String = edges[e].name
	var p := point_on_edge(e, t)
	var best := ""
	var bd := INF
	for n in positions.size():
		if node_roads[n].size() < 2 or not (road in node_roads[n]):
			continue
		var d := positions[n].distance_to(p)
		if d < bd:
			for r in node_roads[n]:
				if r != road:
					best = r
					bd = d
					break
	if best == "":
		return road
	if bd < 30.0:
		return "%s与%s交叉口" % [road, best]
	return "%s（近%s）" % [road, best]


## 由节点序列生成带右侧车道偏移的平滑折线（斜接点）
static func offset_polyline(pts: PackedVector3Array, off: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := pts.size()
	if n < 2:
		return pts
	for k in n:
		var d_in := Vector3.ZERO
		var d_out := Vector3.ZERO
		if k > 0:
			d_in = (pts[k] - pts[k - 1])
			d_in.y = 0
			d_in = d_in.normalized()
		if k < n - 1:
			d_out = (pts[k + 1] - pts[k])
			d_out.y = 0
			d_out = d_out.normalized()
		if d_in == Vector3.ZERO:
			d_in = d_out
		if d_out == Vector3.ZERO:
			d_out = d_in
		var n1 := Vector3(-d_in.z, 0, d_in.x)
		var n2 := Vector3(-d_out.z, 0, d_out.x)
		var denom := 1.0 + n1.dot(n2)
		var m: Vector3
		if denom < 0.2:
			m = n1 * off
		else:
			m = (n1 + n2) / denom * off
		out.append(pts[k] + m)
	return out
