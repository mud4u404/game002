class_name PoliceUnit
extends Node3D
## 警务单位：待命 / 巡逻 / 出警 / 处置 / 返回。沿路网右侧车道行驶。

enum State { IDLE, PATROL, ENROUTE, ONSCENE, RETURN, MOVE }
const STATE_NAMES := ["待命", "巡逻", "出警", "处置", "返回", "机动"]
const STATE_COLORS := [Color(0.45, 0.62, 0.75), Color(0.21, 0.88, 1.0), Color(1.0, 0.72, 0.25),
	Color(1.0, 0.4, 0.3), Color(0.6, 0.7, 0.8), Color(0.7, 0.85, 1.0)]

var uid := 0
var kind := ""
var info: Dictionary
var callsign := ""
var facility: Dictionary
var spot := Vector3.ZERO
var state := State.IDLE
var incident: Incident = null
var fatigue := 0.0
var xp := 0.0
var level := 1
var leader := ""
var rank := ""
var graph: RoadGraph
var eta_min := 0.0

var _path := PackedVector3Array()
var _seg := 0
var _seg_s := 0.0
var _last_node := -1
var _yaw := PI
var _vis: Dictionary
var _siren := false
var _siren_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_uid: int, p_kind: String, p_fac: Dictionary, p_spot: Vector3, p_graph: RoadGraph, number: int) -> void:
	uid = p_uid
	kind = p_kind
	info = Data.UNIT_TYPES[kind]
	facility = p_fac
	spot = p_spot
	graph = p_graph
	_rng.seed = uid * 7919 + 13
	callsign = "%s%02d" % [info.callsign, number]
	leader = Data.random_name(_rng)
	rank = Data.RANKS[_rng.randi() % 3]
	_vis = VehicleFactory.build_police(kind, info.body, info.stripe)
	add_child(_vis.root)
	position = Vector3(spot.x, 0.2, spot.z)
	_yaw = PI
	rotation.y = _yaw


func state_name() -> String:
	return STATE_NAMES[state]


func state_color() -> Color:
	return STATE_COLORS[state]


func is_available() -> bool:
	return state in [State.IDLE, State.PATROL, State.RETURN, State.MOVE] and fatigue < 92.0


func force() -> int:
	return int(info.force)


# ------------------------------------------------------------------ 规划
## 规划到达路段 dest_edge 上中线点 dest 的折线；返回 {pts, len}
func plan(dest: Vector3, dest_edge: int) -> Dictionary:
	var starts: Array = []
	var prefix := PackedVector3Array([global_position])
	if state == State.IDLE:
		prefix.append(RoadGraph.offset_polyline(PackedVector3Array([facility.drive, graph.positions[facility.nodes[1]]]), RoadGraph.LANE_OFFSET)[0])
		starts = facility.nodes
	elif state == State.ONSCENE and incident != null:
		var ed: Dictionary = graph.edges[incident.spot.edge]
		starts = [ed.a, ed.b]
	elif _path.size() > 1 and _last_node >= 0:
		starts = [_last_node]
	else:
		starts = [graph.nearest_node(global_position)]
	var ed2: Dictionary = graph.edges[dest_edge]
	var best_len := INF
	var best_ids := PackedInt64Array()
	for sn in starts:
		for dn in [ed2.a, ed2.b]:
			var ids := graph.path(sn, dn)
			if ids.is_empty():
				continue
			var l: float = prefix[prefix.size() - 1].distance_to(graph.positions[sn]) + graph.path_length(ids) + graph.positions[dn].distance_to(dest)
			if l < best_len:
				best_len = l
				best_ids = ids
	var center := PackedVector3Array()
	for id in best_ids:
		center.append(graph.positions[id])
	center.append(dest)
	var lane := RoadGraph.offset_polyline(center, RoadGraph.LANE_OFFSET)
	var pts := prefix.duplicate()
	pts.append_array(lane)
	var nodes := best_ids
	return {"pts": pts, "len": best_len, "nodes": nodes, "prefix": prefix.size()}


func eta_to(dest: Vector3, dest_edge: int, emergency := true) -> float:
	var p := plan(dest, dest_edge)
	return p.len / _speed(emergency) * Data.MIN_PER_SEC


func _speed(emergency: bool) -> float:
	var s: float = info.speed
	if not emergency:
		s *= 0.55
	s *= 1.0 - clampf((fatigue - 60.0) / 100.0, 0.0, 0.25)
	return s


func _follow(p: Dictionary) -> void:
	_path = p.pts
	_seg = 0
	_seg_s = 0.0
	var nodes: PackedInt64Array = p.nodes
	_last_node = nodes[0] if nodes.size() > 0 else -1
	_route_nodes = nodes
	_prefix_len = p.prefix


var _route_nodes := PackedInt64Array()
var _prefix_len := 1


# ------------------------------------------------------------------ 指令
func dispatch_to(inc: Incident) -> void:
	incident = inc
	var p := plan(inc.spot.road_center, inc.spot.edge)
	_follow(p)
	eta_min = p.len / _speed(true) * Data.MIN_PER_SEC
	state = State.ENROUTE
	_set_siren(true)


func release(resume_patrol: bool) -> void:
	incident = null
	_set_siren(false)
	if resume_patrol and info.patrol:
		start_patrol()
	else:
		return_to_base()


func return_to_base() -> void:
	incident = null
	_set_siren(false)
	var p := plan(facility.drive, facility.edge)
	var pts: PackedVector3Array = p.pts
	pts.append(spot)
	p.pts = pts
	_follow(p)
	state = State.RETURN


func start_patrol() -> void:
	incident = null
	_set_siren(false)
	var e := _pick_patrol_edge()
	var dest := graph.point_on_edge(e, _rng.randf_range(0.3, 0.7))
	_follow(plan(dest, e))
	state = State.PATROL


func move_to(point: Vector3) -> void:
	if incident != null:
		incident.unassign(self)
		incident = null
	_set_siren(false)
	var n := graph.nearest_node(point, true)
	var best_e := -1
	var best_d := INF
	for nb in graph.adj[n]:
		var e := graph.edge_between(n, nb)
		var mid := graph.point_on_edge(e, 0.5)
		var d := mid.distance_to(point)
		if d < best_d:
			best_d = d
			best_e = e
	var ed: Dictionary = graph.edges[best_e]
	var a: Vector3 = graph.positions[ed.a]
	var b: Vector3 = graph.positions[ed.b]
	var ab := b - a
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.1, 0.9)
	_follow(plan(a.lerp(b, t), best_e))
	state = State.MOVE


func _pick_patrol_edge() -> int:
	var c: Vector3 = facility.center
	var rad: float = info.patrol_radius
	for tries in 40:
		var e := _rng.randi() % graph.edges.size()
		if not graph.is_inner_edge(e):
			continue
		if graph.point_on_edge(e, 0.5).distance_to(c) <= rad:
			return e
	return facility.edge


func _set_siren(on: bool) -> void:
	_siren = on
	if not on:
		_vis.light.light_energy = 0.0
		_vis.red.emission_energy_multiplier = 0.4
		_vis.blue.emission_energy_multiplier = 0.4


# ------------------------------------------------------------------ 更新
## 返回 true 表示本帧到达终点
func tick(dt: float, dm: float) -> bool:
	var arrived := false
	if _path.size() >= 2 and _seg < _path.size() - 1:
		var emergency := state == State.ENROUTE
		var move := _speed(emergency) * dt
		while move > 0.0 and _seg < _path.size() - 1:
			var a := _path[_seg]
			var b := _path[_seg + 1]
			var L := a.distance_to(b)
			var rem := L - _seg_s
			if move < rem:
				_seg_s += move
				move = 0.0
			else:
				move -= rem
				_seg += 1
				_seg_s = 0.0
				_advance_node()
		if _seg >= _path.size() - 1:
			position = _path[_path.size() - 1]
			arrived = true
		else:
			var a2 := _path[_seg]
			var b2 := _path[_seg + 1]
			var L2 := maxf(a2.distance_to(b2), 0.001)
			position = a2.lerp(b2, _seg_s / L2)
			var d := b2 - a2
			if d.length_squared() > 0.01:
				var target_yaw := atan2(-d.x, -d.z)
				_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-dt * 10.0))
		position.y = 0.06
		rotation.y = _yaw
		if state == State.ENROUTE:
			eta_min = _remaining() / _speed(true) * Data.MIN_PER_SEC

	# 疲劳
	match state:
		State.ENROUTE, State.ONSCENE:
			fatigue = minf(fatigue + dm * 0.32, 100.0)
		State.IDLE:
			fatigue = maxf(fatigue - dm * 0.5, 0.0)
		_:
			fatigue = minf(fatigue + dm * 0.03, 100.0)

	# 警灯
	if _siren or state == State.ONSCENE:
		_siren_t += dt if dt > 0 else 0.016
		var ph := fmod(_siren_t * 3.2, 1.0)
		var r_on := ph < 0.5
		_vis.red.emission_energy_multiplier = 9.0 if r_on else 0.3
		_vis.blue.emission_energy_multiplier = 0.3 if r_on else 11.0
		_vis.light.light_color = Color(1, 0.1, 0.1) if r_on else Color(0.15, 0.3, 1.0)
		_vis.light.light_energy = 3.0

	if arrived:
		_path = PackedVector3Array()
		if state == State.RETURN:
			state = State.IDLE
			_yaw = PI
			rotation.y = _yaw
		elif state == State.PATROL:
			start_patrol()
			return false
		elif state == State.MOVE:
			state = State.PATROL if info.patrol else State.IDLE
			if state == State.PATROL:
				start_patrol()
			return false
	return arrived


func _advance_node() -> void:
	# 记录正在驶向的路网节点（重新规划路线时的起点）
	if _route_nodes.is_empty():
		return
	var idx := clampi(_seg + 1 - _prefix_len, 0, _route_nodes.size() - 1)
	_last_node = _route_nodes[idx]


func _remaining() -> float:
	if _seg >= _path.size() - 1:
		return 0.0
	var l := _path[_seg].distance_to(_path[_seg + 1]) - _seg_s
	for k in range(_seg + 1, _path.size() - 1):
		l += _path[k].distance_to(_path[k + 1])
	return l


func remaining_points() -> PackedVector3Array:
	var out := PackedVector3Array([global_position])
	for k in range(_seg + 1, _path.size()):
		out.append(_path[k])
	return out


func heading() -> Vector3:
	return Vector3(-sin(_yaw), 0, -cos(_yaw))


func gain_xp(amount: float) -> void:
	xp += amount
	var need := 60.0 * level
	if xp >= need:
		xp -= need
		level += 1
		var ri := clampi(level / 2, 0, Data.RANKS.size() - 1)
		if Data.RANKS.find(rank) < ri:
			rank = Data.RANKS[ri]
		GameState.post(callsign, "带班民警%s晋升为 Lv.%d。" % [leader, level], "good")
