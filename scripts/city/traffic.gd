class_name Traffic
extends Node3D
## 社会车流：沿路网随机行驶，使用 MultiMesh 批量绘制车身与车头灯光斑。

const COLORS := [
	Color(0.92, 0.92, 0.92), Color(0.9, 0.9, 0.88), Color(0.05, 0.05, 0.06), Color(0.08, 0.08, 0.09),
	Color(0.55, 0.57, 0.6), Color(0.35, 0.37, 0.4), Color(0.12, 0.2, 0.38), Color(0.5, 0.08, 0.07),
	Color(0.15, 0.45, 0.3), Color(0.85, 0.7, 0.2),
]

var graph: RoadGraph
var count := 180
var _cars: Array = []
var _mm: MultiMesh
var _hl: MultiMesh
var _rng := RandomNumberGenerator.new()


func setup(p_graph: RoadGraph, p_count: int, seed_value: int) -> void:
	graph = p_graph
	count = p_count
	_rng.seed = seed_value
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = VehicleFactory.civilian_mesh()
	_mm.instance_count = count
	_hl = MultiMesh.new()
	_hl.transform_format = MultiMesh.TRANSFORM_3D
	_hl.mesh = VehicleFactory.headlight_mesh()
	_hl.instance_count = count
	var a := MultiMeshInstance3D.new()
	a.multimesh = _mm
	add_child(a)
	var b := MultiMeshInstance3D.new()
	b.multimesh = _hl
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)
	for k in count:
		var e: Dictionary = graph.edges[_rng.randi() % graph.edges.size()]
		var car := {"prev": -1, "from": e.a, "to": e.b, "next": -1, "s": 0.0, "len": 1.0,
			"p0": Vector3.ZERO, "p1": Vector3.ZERO, "speed": _rng.randf_range(11.0, 17.0), "yaw": 0.0}
		car.prev = _choose(car.to, car.from)
		car.next = _choose(car.from, car.to)
		_segment(car)
		car.s = _rng.randf() * car.len
		_cars.append(car)
		var c: Color = COLORS[_rng.randi() % COLORS.size()]
		_mm.set_instance_color(k, c)


func _choose(from: int, at: int) -> int:
	var nb: Array = graph.adj[at]
	if nb.size() <= 1:
		return from
	for tries in 6:
		var n: int = nb[_rng.randi() % nb.size()]
		if n != from:
			return n
	return from


func _miter(a: int, b: int, c: int) -> Vector3:
	var pts := PackedVector3Array([graph.positions[a], graph.positions[b], graph.positions[c]])
	if a == b:
		pts = PackedVector3Array([graph.positions[b], graph.positions[c]])
		return RoadGraph.offset_polyline(pts, RoadGraph.LANE_OFFSET)[0]
	if c == b:
		pts = PackedVector3Array([graph.positions[a], graph.positions[b]])
		return RoadGraph.offset_polyline(pts, RoadGraph.LANE_OFFSET)[1]
	return RoadGraph.offset_polyline(pts, RoadGraph.LANE_OFFSET)[1]


func _segment(car: Dictionary) -> void:
	car.p0 = _miter(car.prev, car.from, car.to)
	car.p1 = _miter(car.from, car.to, car.next)
	car.len = maxf(car.p0.distance_to(car.p1), 0.1)
	var d: Vector3 = car.p1 - car.p0
	car.yaw = atan2(-d.x, -d.z)


func _process(delta: float) -> void:
	var dt := GameState.scaled_delta(delta)
	for k in _cars.size():
		var car: Dictionary = _cars[k]
		car.s += car.speed * dt
		var guard := 0
		while car.s >= car.len and guard < 8:
			guard += 1
			car.s -= car.len
			car.prev = car.from
			car.from = car.to
			car.to = car.next
			car.next = _choose(car.from, car.to)
			_segment(car)
		var p: Vector3 = car.p0.lerp(car.p1, car.s / car.len)
		var basis := Basis(Vector3.UP, car.yaw).scaled(Vector3.ONE * VehicleFactory.SCALE)
		var xf := Transform3D(basis, Vector3(p.x, 0.04, p.z))
		_mm.set_instance_transform(k, xf)
		_hl.set_instance_transform(k, xf)
