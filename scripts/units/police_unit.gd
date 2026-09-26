class_name PoliceUnit
extends Node3D
## 警务单位：待命 / 巡逻 / 出警 / 处置 / 返回。沿路网右侧车道行驶。

enum State { IDLE, PATROL, ENROUTE, ONSCENE, RETURN, MOVE, CHASE }
const STATE_NAMES := ["待命", "巡逻", "出警", "处置", "返回", "机动", "追缉"]
const STATE_COLORS := [Color("8a96a3"), Color("4ea1ff"), Color("ff9f1a"),
	Color("ff4d4f"), Color("7f93aa"), Color("8fb8ff"), Color("ff3d4a")]

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
var resting := false
var patrol_center := Vector3.ZERO   # 巡区中心（默认驻地）
var patrol_radius := 0.0
var zone_set := false
var bought_in_setup := false
var chase_target = null            # Suspect       # 轮休中：返回驻地恢复体力

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
	# 战术图中单位由 HUD 卡片表示，3D 车辆模型隐藏
	_vis.root.visible = false
	patrol_center = facility.center
	patrol_radius = info.patrol_radius
	position = Vector3(spot.x, 0.2, spot.z)
	_yaw = facility.get("yaw", PI)
	rotation.y = _yaw


func state_name() -> String:
	return STATE_NAMES[state]


func state_color() -> Color:
	return STATE_COLORS[state]


func is_available() -> bool:
	return state in [State.IDLE, State.PATROL, State.RETURN, State.MOVE] and fatigue < 92.0 and chase_target == null


func force() -> int:
	return int(info.force)


func at_base() -> bool:
	return Vector2(position.x - spot.x, position.z - spot.z).length() < 4.0


func skill() -> String:
	return info.skill


func skill_name() -> String:
	return Data.SKILLS[info.skill].name


# ------------------------------------------------------------------ 规划
## 规划到达路段 dest_edge 上中线点 dest 的折线；返回 {pts, len}
func plan(dest: Vector3, dest_edge: int) -> Dictionary:
	var starts: Array = []
	var prefix := PackedVector3Array([global_position])
	if state == State.IDLE and at_base():
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
	resting = false
	var p := plan(inc.spot.road_center, inc.spot.edge)
	_follow(p)
	eta_min = p.len / _speed(true) * Data.MIN_PER_SEC
	state = State.ENROUTE
	_set_siren(true)


func release(resume_patrol: bool) -> void:
	incident = null
	chase_target = null
	_set_siren(false)
	if resume_patrol and info.patrol and zone_set and fatigue < 78.0:
		start_patrol()
	else:
		return_to_base()


func return_to_base() -> void:
	incident = null
	chase_target = null
	_set_siren(false)
	var p := plan(facility.drive, facility.edge)
	var pts: PackedVector3Array = p.pts
	pts.append(spot)
	p.pts = pts
	_follow(p)
	state = State.RETURN


func start_patrol() -> void:
	incident = null
	chase_target = null
	_set_siren(false)
	var e := _pick_patrol_edge()
	var dest := graph.point_on_edge(e, _rng.randf_range(0.3, 0.7))
	_follow(plan(dest, e))
	state = State.PATROL


func _plan_point(point: Vector3) -> Dictionary:
	var near := graph.nearest_edge_point(point)
	var e: int = near.edge
	var t := clampf(near.t, 0.05, 0.95)
	return plan(graph.point_on_edge(e, t), e)


func move_to(point: Vector3) -> void:
	if incident != null:
		incident.unassign(self)
		incident = null
	chase_target = null
	_set_siren(false)
	_follow(_plan_point(point))
	state = State.MOVE


## 追缉：鸣笛前往嫌疑人的位置（或最后出现位置）
func chase_to(target, point: Vector3) -> void:
	if incident != null:
		incident.unassign(self)
		incident = null
	chase_target = target
	var p := _plan_point(point)
	_follow(p)
	eta_min = p.len / _speed(true) * Data.MIN_PER_SEC
	state = State.CHASE
	_set_siren(true)
	resting = false


## 设定巡区：以某点为中心巡逻
func set_zone(center: Vector3, radius := 150.0, go := true) -> void:
	patrol_center = Vector3(center.x, 0, center.z)
	patrol_radius = radius
	zone_set = true
	if go and incident == null and chase_target == null:
		start_patrol()


func clear_zone() -> void:
	zone_set = false
	patrol_center = facility.center
	patrol_radius = info.patrol_radius


func _pick_patrol_edge() -> int:
	var cands: Array = []
	for e in graph.edges.size():
		if graph.edges[e].len < 8.0:
			continue
		if graph.point_on_edge(e, 0.5).distance_to(patrol_center) <= patrol_radius:
			cands.append(e)
	if cands.is_empty():
		return graph.nearest_edge_point(patrol_center).edge
	return cands[_rng.randi() % cands.size()]


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
		var emergency := state == State.ENROUTE or state == State.CHASE
		var move := _speed(emergency) * dt
		var guard := 0
		while move > 0.0 and _seg < _path.size() - 1 and guard < 64:
			guard += 1
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
		State.ENROUTE, State.ONSCENE, State.CHASE:
			fatigue = minf(fatigue + dm * 0.22, 100.0)
		State.IDLE:
			fatigue = maxf(fatigue - dm * 1.1, 0.0)
		_:
			fatigue = minf(fatigue + dm * 0.03, 100.0)

	# 轮休：疲劳过高的巡逻单位自动回所休整，恢复后重新上街
	if state == State.PATROL and fatigue > 78.0 and not resting:
		resting = true
		GameState.post(callsign, "连续执勤疲劳度过高，申请返所轮休。", "info")
		return_to_base()
	elif state == State.IDLE and resting and fatigue < 20.0:
		resting = false
		if info.patrol and zone_set:
			GameState.post(callsign, "轮休结束，返回巡区。", "unit")
			start_patrol()

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
			_yaw = facility.get("yaw", PI)
			rotation.y = _yaw
		elif state == State.PATROL:
			start_patrol()
			return false
		elif state == State.CHASE:
			return false
		elif state == State.MOVE:
			state = State.IDLE
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
