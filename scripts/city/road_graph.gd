class_name RoadGraph
extends RefCounted
## 规则网格路网：节点=路口，边=路段。负责寻路、定位描述、车道偏移。

const LANE_OFFSET := 3.2

var cols := 0          # 节点列数
var rows := 0
var xs: Array[float] = []
var zs: Array[float] = []
var positions: Array[Vector3] = []
var adj: Array = []            # node -> Array[int]
var edges: Array = []          # {a, b, len, name, horizontal}
var edge_lookup := {}          # "a:b" -> edge index
var names_h: Array = []
var names_v: Array = []
var inner_min := Vector2i.ZERO
var inner_max := Vector2i.ZERO
var astar := AStar3D.new()


func setup_lines(p_xs: Array[float], p_zs: Array[float]) -> void:
	xs = p_xs
	zs = p_zs
	cols = xs.size()
	rows = zs.size()
	positions.clear()
	adj.clear()
	for j in rows:
		for i in cols:
			var p := Vector3(xs[i], 0.0, zs[j])
			positions.append(p)
			adj.append([])
			astar.add_point(node_id(i, j), p)


func node_id(i: int, j: int) -> int:
	return j * cols + i


func node_ij(id: int) -> Vector2i:
	return Vector2i(id % cols, id / cols)


func add_edge(a: int, b: int, horizontal: bool) -> void:
	var e := {"a": a, "b": b, "len": positions[a].distance_to(positions[b]), "horizontal": horizontal}
	var ij := node_ij(a)
	e["name"] = names_h[ij.y] if horizontal else names_v[ij.x]
	edges.append(e)
	edge_lookup[_key(a, b)] = edges.size() - 1
	adj[a].append(b)
	adj[b].append(a)
	astar.connect_points(a, b, true)


func _key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func edge_between(a: int, b: int) -> int:
	return edge_lookup.get(_key(a, b), -1)


func is_inner_node(id: int) -> bool:
	var ij := node_ij(id)
	return ij.x >= inner_min.x and ij.x <= inner_max.x and ij.y >= inner_min.y and ij.y <= inner_max.y


func is_inner_edge(e: int) -> bool:
	return is_inner_node(edges[e].a) and is_inner_node(edges[e].b)


func nearest_node(p: Vector3, inner_only := false) -> int:
	var i := _closest(xs, p.x)
	var j := _closest(zs, p.z)
	var best := node_id(i, j)
	if adj[best].is_empty() or (inner_only and not is_inner_node(best)):
		var bd := INF
		for id in positions.size():
			if adj[id].is_empty() or (inner_only and not is_inner_node(id)):
				continue
			var d := positions[id].distance_squared_to(p)
			if d < bd:
				bd = d
				best = id
	return best


func _closest(arr: Array[float], v: float) -> int:
	var best := 0
	for k in arr.size():
		if absf(arr[k] - v) < absf(arr[best] - v):
			best = k
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


## 路段上某点的中文位置描述
func describe(e: int, t: float) -> String:
	var ed: Dictionary = edges[e]
	var road: String = ed.name
	var ca := _cross_name(ed.a, ed.horizontal)
	var cb := _cross_name(ed.b, ed.horizontal)
	if t < 0.2:
		return "%s与%s交叉口" % [road, ca]
	if t > 0.8:
		return "%s与%s交叉口" % [road, cb]
	return "%s（%s—%s段）" % [road, ca, cb]


func _cross_name(node: int, horizontal: bool) -> String:
	var ij := node_ij(node)
	return names_v[ij.x] if horizontal else names_h[ij.y]


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
