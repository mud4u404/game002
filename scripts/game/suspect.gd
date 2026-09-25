class_name Suspect
extends RefCounted
## 逃逸嫌疑车辆：沿路网逃窜，倾向远离警力；只有经过天网摄像头或被警力目视时才暴露位置。

enum S { FLEE, CAUGHT, ESCAPED }

var id := 0
var graph: RoadGraph
var incident: Incident
var state := S.FLEE
var pos := Vector3.ZERO
var speed := 16.0            # 米 / 现实秒（1× 时），慢于警车
var time_left := 26.0        # 游戏分钟，超时即逃出辖区
var seen := false            # 当前是否可见
var last_seen := Vector3.ZERO
var seen_age := 0.0          # 距最后一次发现的游戏分钟
var last_seen_by := ""
var fade := 0.0              # 结束后的淡出计时（现实秒）

var _prev := -1
var _from := -1
var _to := -1
var _next := -1
var _s := 0.0
var _len := 1.0
var _p0 := Vector3.ZERO
var _p1 := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func setup(p_graph: RoadGraph, edge: int, t: float, seed_value: int) -> void:
	graph = p_graph
	_rng.seed = seed_value
	var ed: Dictionary = graph.edges[edge]
	_from = ed.a
	_to = ed.b
	_prev = _from
	_next = _choose(_from, _to, [])
	_segment()
	_s = _len * t
	pos = _p0.lerp(_p1, t)
	last_seen = pos


func _choose(from: int, at: int, threats: Array) -> int:
	var nb: Array = graph.adj[at]
	if nb.size() <= 1:
		return from
	var best := from
	var best_score := -INF
	for n in nb:
		if n == from:
			continue
		var p: Vector3 = graph.positions[n]
		var score := _rng.randf() * 60.0
		for tp in threats:
			score += minf(p.distance_to(tp), 260.0) * 0.6
		if score > best_score:
			best_score = score
			best = n
	return best


func _miter(a: int, b: int, c: int) -> Vector3:
	var P := graph.positions
	if a == b and c == b:
		return P[b]
	if a == b:
		return RoadGraph.offset_polyline(PackedVector3Array([P[b], P[c]]), RoadGraph.LANE_OFFSET)[0]
	if c == b:
		return RoadGraph.offset_polyline(PackedVector3Array([P[a], P[b]]), RoadGraph.LANE_OFFSET)[1]
	return RoadGraph.offset_polyline(PackedVector3Array([P[a], P[b], P[c]]), RoadGraph.LANE_OFFSET)[1]


func _segment() -> void:
	_p0 = _miter(_prev, _from, _to)
	_p1 = _miter(_from, _to, _next)
	_len = maxf(_p0.distance_to(_p1), 0.1)


func heading() -> Vector3:
	var d := _p1 - _p0
	d.y = 0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


## threats：警力位置，嫌疑人选路时尽量远离
func tick(dt: float, dm: float, threats: Array) -> void:
	if state != S.FLEE:
		return
	time_left -= dm
	seen_age += dm
	_s += speed * dt
	var guard := 0
	while _s >= _len and guard < 8:
		guard += 1
		_s -= _len
		_prev = _from
		_from = _to
		_to = _next
		_next = _choose(_from, _to, threats)
		_segment()
	pos = _p0.lerp(_p1, clampf(_s / _len, 0.0, 1.0))


func mark_seen(by: String) -> void:
	seen = true
	last_seen = pos
	seen_age = 0.0
	last_seen_by = by
