class_name CityBuilder
extends Node3D
## 程序化生成虚构城市"江城"：路网、街区、江与桥、建筑、路灯、行道树、公安设施、夜间光照贴图。

const G := 17                 # 可视网格街区数（G+1 条路）
const P := 64.0               # 路网间距
const W := 14.0               # 道路宽度
const SIDEWALK := 3.5
const RIVER_ROW := 9
const BRIDGES := [1, 5, 8, 11, 15]
const INNER_MIN := 3          # 游戏区节点范围
const INNER_MAX := 14
const LM_SIZE := 1024
const SLAB_Y := 0.18

const FACILITY_SITES := [
	{"type": "station", "name": "滨江派出所", "block": Vector2i(7, 8)},
	{"type": "station", "name": "老城派出所", "block": Vector2i(5, 4)},
	{"type": "station", "name": "江南派出所", "block": Vector2i(10, 11)},
	{"type": "patrol_hq", "name": "巡特警大队", "block": Vector2i(10, 6)},
	{"type": "traffic_hq", "name": "交警二中队", "block": Vector2i(12, 8)},
	{"type": "swat_hq", "name": "特警支队", "block": Vector2i(4, 7)},
]

var graph := RoadGraph.new()
var rng := RandomNumberGenerator.new()
var half := G * P * 0.5
var xs: Array[float] = []    # 各纵向道路的 x 坐标（间距不等，打破网格感）
var zs: Array[float] = []
var _map_c := Vector2.ZERO    # 街区内布局：名义 43m 街区 → 实际尺寸的缩放
var _map_k := Vector2.ONE
var river_z0 := 0.0
var river_z1 := 0.0
var blocks := {}              # Vector2i -> {type, rect, inner}
var facilities: Array = []
var lm_rect := Vector4(-620, -620, 1240, 0)
var lightmap_tex: ImageTexture
var noise_tex: NoiseTexture2D

var _b_xf: Array[Transform3D] = []
var _b_cd: Array[Color] = []
var _tree_xf: Array[Transform3D] = []
var _pole_xf: Array[Transform3D] = []
var _beacon_xf: Array[Transform3D] = []
var _lights: Array = []       # [Vector2 pos, radius, Color, intensity]
var _font: Font


func line_x(i: int) -> float:
	return xs[i]


func line_z(j: int) -> float:
	return zs[j]


func build(seed_value: int) -> void:
	rng.seed = seed_value
	_make_lines()
	_font = load("res://assets/fonts/NotoSansSC-Bold.ttf")
	noise_tex = MeshKit.noise_texture(0.02, 512)
	river_z0 = line_z(RIVER_ROW) + W * 0.5 + 3.0
	river_z1 = line_z(RIVER_ROW + 1) - W * 0.5 - 3.0
	_build_graph()
	_classify_blocks()
	for b in blocks.keys():
		_populate_block(b)
	_street_lights()
	_paint_lightmap()
	_build_ground()
	_build_roads()
	_build_river()
	_build_instances()


# ------------------------------------------------------------------ 路网
func _make_lines() -> void:
	var need_wide := {}
	for f in FACILITY_SITES:
		need_wide[f.block.x] = true
	var need_tall := {}
	for f in FACILITY_SITES:
		need_tall[f.block.y] = true
	var choices := [50.0, 56.0, 62.0, 68.0, 76.0, 84.0]
	xs.clear()
	zs.clear()
	var x := 0.0
	var z := 0.0
	xs.append(0.0)
	zs.append(0.0)
	for k in G:
		var px: float = choices[rng.randi() % choices.size()]
		if need_wide.has(k):
			px = maxf(px, 66.0)
		x += px
		xs.append(x)
		var pz: float = choices[rng.randi() % choices.size()]
		if need_tall.has(k):
			pz = maxf(pz, 66.0)
		if k == RIVER_ROW:
			pz = 84.0
		z += pz
		zs.append(z)
	var ox := x * 0.5
	var oz := z * 0.5
	for k in xs.size():
		xs[k] -= ox
		zs[k] -= oz
	half = maxf(ox, oz)


func _build_graph() -> void:
	graph.names_h = Data.ROAD_NAMES_H
	graph.names_v = Data.ROAD_NAMES_V
	graph.setup_lines(xs, zs)
	graph.inner_min = Vector2i(INNER_MIN, INNER_MIN)
	graph.inner_max = Vector2i(INNER_MAX, INNER_MAX)
	for j in G + 1:
		for i in G:
			graph.add_edge(graph.node_id(i, j), graph.node_id(i + 1, j), true)
	for i in G + 1:
		for j in G:
			if j == RIVER_ROW and not (i in BRIDGES):
				continue
			graph.add_edge(graph.node_id(i, j), graph.node_id(i, j + 1), false)


func block_rect(b: Vector2i) -> Rect2:
	var x0 := line_x(b.x) + W * 0.5
	var z0 := line_z(b.y) + W * 0.5
	return Rect2(x0, z0, line_x(b.x + 1) - line_x(b.x) - W, line_z(b.y + 1) - line_z(b.y) - W)


func _classify_blocks() -> void:
	var fac_blocks := {}
	for f in FACILITY_SITES:
		fac_blocks[f.block] = f
	var center := Vector2(8.5, 5.2)
	for bj in G:
		for bi in G:
			var b := Vector2i(bi, bj)
			var inner := bi >= INNER_MIN and bi < INNER_MAX and bj >= INNER_MIN and bj < INNER_MAX
			var t := "residential"
			var d := Vector2(bi + 0.5, bj + 0.5).distance_to(center)
			var r := rng.randf()
			if bj == RIVER_ROW:
				t = "river"
			elif fac_blocks.has(b):
				t = "facility"
			elif b == Vector2i(6, 8) or b == Vector2i(9, 10):
				t = "park"
			elif b == Vector2i(12, 3):
				t = "school"
			elif bj < RIVER_ROW:
				if d < 2.0:
					t = "cbd"
				elif d < 3.6:
					t = "commercial" if r < 0.65 else ("cbd" if r < 0.8 else "residential")
				elif bi < 7 and bj > 2:
					t = "oldtown" if r < 0.6 else ("commercial" if r < 0.75 else "residential")
				else:
					t = "residential" if r < 0.6 else ("oldtown" if r < 0.8 else "commercial")
				if t != "cbd" and rng.randf() < 0.06:
					t = "park"
			else:
				if bj == RIVER_ROW + 1:
					t = "cbd" if bi >= 7 and bi <= 11 else "commercial"
				elif bj >= 15:
					t = "industrial" if r < 0.6 else "residential"
				else:
					t = "residential" if r < 0.68 else "commercial"
				if rng.randf() < 0.06:
					t = "park"
			blocks[b] = {"type": t, "rect": block_rect(b), "inner": inner}


# ------------------------------------------------------------------ 建筑
## 俯瞰地图：真实高度被压缩为低矮体块，只保留少量阴影层次
static func map_height(y: float) -> float:
	if y <= SLAB_Y + 0.01:
		return y
	return SLAB_Y + 1.2 + (y - SLAB_Y) * 0.035


func _add_building(cx: float, cz: float, w: float, d: float, h: float, style: int, lit: float, base := SLAB_Y) -> void:
	var b0 := map_height(base)
	var b1 := map_height(base + h)
	if base > SLAB_Y + 0.01:
		b0 += 0.05
	var mh := maxf(b1 - b0, 0.3)
	cx = _map_c.x + (cx - _map_c.x) * _map_k.x
	cz = _map_c.y + (cz - _map_c.y) * _map_k.y
	w *= _map_k.x
	d *= _map_k.y
	var xf := Transform3D(Basis.from_scale(Vector3(w, mh, d)), Vector3(cx, b0 + mh * 0.5, cz))
	_b_xf.append(xf)
	_b_cd.append(Color(rng.randf(), float(style), lit, b0 + mh))


func _roof_clutter(cx: float, cz: float, w: float, d: float, top: float) -> void:
	var n := rng.randi_range(0, 3)
	for k in n:
		var sw := rng.randf_range(2.0, 5.0)
		var sd := rng.randf_range(2.0, 5.0)
		var sx := cx + rng.randf_range(-w * 0.3, w * 0.3)
		var sz := cz + rng.randf_range(-d * 0.3, d * 0.3)
		_add_building(sx, sz, sw, sd, rng.randf_range(1.5, 3.5), 6, 0.0, top)


func _populate_block(b: Vector2i) -> void:
	var info: Dictionary = blocks[b]
	var r: Rect2 = info.rect
	var inner_r := r.grow(-SIDEWALK)
	var c := r.get_center()
	var lit_k := 1.0 if info.inner else 0.75
	_map_c = c
	_map_k = Vector2.ONE
	if info.type in ["cbd", "residential", "industrial", "school", "park"]:
		_map_k = inner_r.size / 43.0
	match info.type:
		"cbd":
			var pod_h := rng.randf_range(9.0, 15.0)
			_add_building(c.x, c.y, 41.0, 41.0, pod_h, 3, 0.4 * lit_k)
			var twin := rng.randf() < 0.35
			var dist := Vector2(b.x + 0.5, b.y + 0.5).distance_to(Vector2(8.5, 5.2))
			var towers := 2 if twin else 1
			for k in towers:
				var tw := rng.randf_range(15.0, 20.0) if twin else rng.randf_range(20.0, 28.0)
				var th := rng.randf_range(80.0, 170.0) * clampf(1.25 - dist * 0.14, 0.45, 1.2)
				if twin:
					th *= 0.8
				var ox := 0.0 if not twin else (-10.0 if k == 0 else 10.0)
				var oz := rng.randf_range(-4.0, 4.0)
				var style := 7 if rng.randf() < 0.12 else 0
				_add_building(c.x + ox, c.y + oz, tw, tw, th, style, 0.3 * lit_k, SLAB_Y + pod_h)
				var top := SLAB_Y + pod_h + th
				if rng.randf() < 0.7:
					var sh := rng.randf_range(8.0, 22.0)
					_add_building(c.x + ox, c.y + oz, tw * 0.7, tw * 0.7, sh, style, 0.25, top)
					top += sh
				if top > 70.0:
					_beacon_xf.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.6), Vector3(c.x + ox * _map_k.x, map_height(top) + 0.6, c.y + oz * _map_k.y)))
		"commercial":
			var hw := inner_r.size.x * 0.5
			for k in 4:
				var qx := c.x + (-hw * 0.5 if k % 2 == 0 else hw * 0.5)
				var qz := c.y + (-hw * 0.5 if k < 2 else hw * 0.5)
				if rng.randf() < 0.1:
					continue
				var h := rng.randf_range(12.0, 46.0)
				var w := hw - rng.randf_range(1.0, 3.0)
				_add_building(qx, qz, w, w, h, 3, 0.24 * lit_k)
				_roof_clutter(qx, qz, w, w, SLAB_Y + h)
		"residential":
			_add_courtyard(inner_r)
			if rng.randf() < 0.55:
				# 板楼：3 排
				for k in 3:
					var bz := c.y - 15.5 + k * 15.5
					var bw := rng.randf_range(28.0, 38.0)
					var floors := rng.randi_range(11, 32)
					var h := floors * 3.0
					if not info.inner:
						h *= 0.7
					_add_building(c.x + rng.randf_range(-3.0, 3.0), bz, bw, 10.5, h, 1, 0.26 * lit_k)
					_roof_clutter(c.x, bz, bw, 8.0, SLAB_Y + h)
			else:
				# 点式高层：2×2
				for k in 4:
					var qx := c.x + (-11.0 if k % 2 == 0 else 11.0)
					var qz := c.y + (-11.0 if k < 2 else 11.0)
					var h := rng.randi_range(18, 34) * 3.0
					if not info.inner:
						h *= 0.7
					_add_building(qx, qz, 15.0, 15.0, h, 1, 0.26 * lit_k)
			_trees_perimeter(r, 13.0)
		"oldtown":
			var cell := inner_r.size.x / 3.0
			for gy in 3:
				for gx in 3:
					if gx == 1 and gy == 1:
						continue
					if rng.randf() < 0.12:
						continue
					var bx := inner_r.position.x + cell * (gx + 0.5)
					var bz := inner_r.position.y + cell * (gy + 0.5)
					var h := rng.randi_range(4, 7) * 3.0
					var w := cell - rng.randf_range(1.0, 2.5)
					var d := cell - rng.randf_range(1.0, 2.5)
					_add_building(bx, bz, w, d, h, 2, 0.28 * lit_k)
					_roof_clutter(bx, bz, w, d, SLAB_Y + h)
			_add_courtyard(Rect2(c.x - cell * 0.5, c.y - cell * 0.5, cell, cell))
			_trees_rect(Rect2(c.x - cell * 0.4, c.y - cell * 0.4, cell * 0.8, cell * 0.8), 3)
		"industrial":
			_add_building(c.x - 6.0, c.y - 8.0, 30.0, 22.0, rng.randf_range(9.0, 14.0), 4, 0.12)
			_add_building(c.x + 10.0, c.y + 12.0, 18.0, 14.0, rng.randf_range(8.0, 12.0), 4, 0.1)
			if rng.randf() < 0.5:
				_add_building(c.x + 14.0, c.y - 14.0, 3.0, 3.0, rng.randf_range(24.0, 40.0), 6, 0.0)
		"park":
			_add_courtyard(r.grow(-1.0))
			_trees_rect(r.grow(-4.0), 34)
			_add_building(c.x, c.y, 6.0, 6.0, 4.0, 6, 0.0)
		"school":
			_add_courtyard(inner_r)
			_add_building(c.x, c.y - 14.5, 38.0, 12.0, 15.0, 1, 0.15)
			_add_building(c.x - 16.5, c.y + 6.0, 10.0, 22.0, 12.0, 1, 0.12)
			_trees_perimeter(r, 11.0)
		"facility":
			_build_facility(b)


func _add_courtyard(r: Rect2) -> void:
	_courtyards.append(r)


var _courtyards: Array[Rect2] = []
var _parkings: Array[Rect2] = []


func _trees_perimeter(r: Rect2, spacing: float) -> void:
	var inset := SIDEWALK * 0.55
	var ir := r.grow(-inset)
	var n := int(ir.size.x / spacing)
	for k in n:
		var t := (k + 0.5) / n
		for p in [Vector2(ir.position.x + t * ir.size.x, ir.position.y), Vector2(ir.position.x + t * ir.size.x, ir.end.y),
				Vector2(ir.position.x, ir.position.y + t * ir.size.y), Vector2(ir.end.x, ir.position.y + t * ir.size.y)]:
			_add_tree(p)


func _trees_rect(r: Rect2, count: int) -> void:
	for k in count:
		_add_tree(Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y)))


func _add_tree(p: Vector2) -> void:
	var s := rng.randf_range(0.8, 1.3)
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
	_tree_xf.append(Transform3D(basis, Vector3(p.x, SLAB_Y, p.y)))


# ------------------------------------------------------------------ 公安设施
func _build_facility(b: Vector2i) -> void:
	_map_k = Vector2.ONE
	var site: Dictionary
	for f in FACILITY_SITES:
		if f.block == b:
			site = f
	var r: Rect2 = blocks[b].rect
	var ir := r.grow(-SIDEWALK)
	var c := r.get_center()
	var bh := 16.0 if site.type != "patrol_hq" else 20.0
	var bz := ir.position.y + 9.0
	_add_building(c.x, bz, 34.0, 16.0, bh, 5, 0.6)
	# 停车场
	var park := Rect2(ir.position.x + 1.0, ir.end.y - 17.0, ir.size.x - 2.0, 16.0)
	_parkings.append(park)
	var spots: Array[Vector3] = []
	for k in 8:
		spots.append(Vector3(park.position.x + 3.0 + k * 4.8, SLAB_Y, park.position.y + 7.0))
	var a := graph.node_id(b.x, b.y + 1)
	var bnode := graph.node_id(b.x + 1, b.y + 1)
	var fac := {
		"type": site.type, "name": site.name, "block": b, "center": Vector3(c.x, 0, c.y),
		"spots": spots, "drive": Vector3(c.x, 0, line_z(b.y + 1)), "nodes": [a, bnode],
		"edge": graph.edge_between(a, bnode), "sign_pos": Vector3(c.x, SLAB_Y + bh * 0.62, bz + 8.05),
		"roof": Vector3(c.x, SLAB_Y + bh, bz),
	}
	facilities.append(fac)
	# 屋顶标识（平铺，俯视可读）
	var roof_y := map_height(SLAB_Y + bh) + 0.08
	fac["roof"] = Vector3(c.x, roof_y, bz)
	var lbl := Label3D.new()
	lbl.text = site.name
	lbl.font = _font
	lbl.font_size = 64
	lbl.pixel_size = 0.09
	lbl.modulate = Color(0.08, 0.2, 0.55)
	lbl.outline_size = 0
	lbl.shaded = true
	lbl.double_sided = false
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.position = Vector3(c.x, roof_y, bz + 1.8)
	add_child(lbl)
	for s in spots:
		_lights.append([Vector2(s.x, s.z), 7.0, Color(0.75, 0.85, 1.0), 0.45])


# ------------------------------------------------------------------ 路灯
func _street_lights() -> void:
	for e in graph.edges.size():
		var ed: Dictionary = graph.edges[e]
		var a: Vector3 = graph.positions[ed.a]
		var b: Vector3 = graph.positions[ed.b]
		var dir := (b - a).normalized()
		var right := Vector3(-dir.z, 0, dir.x)
		var over_river: bool = (not ed.horizontal) and graph.node_ij(ed.a).y == RIVER_ROW
		var led := _is_bright_street(ed)
		var col := Color(0.85, 0.92, 1.0) if led else Color(1.0, 0.64, 0.33)
		var ts := [0.15, 0.38, 0.62, 0.85]
		for k in ts.size():
			var side := 1.0 if k % 2 == 0 else -1.0
			var p: Vector3 = a.lerp(b, ts[k])
			var pole_pos := p + right * side * (W * 0.5 + 0.9)
			var basis := Basis.looking_at(-right * side, Vector3.UP)
			_pole_xf.append(Transform3D(basis, Vector3(pole_pos.x, SLAB_Y, pole_pos.z)))
			var lp := p + right * side * (W * 0.5 - 2.2)
			_lights.append([Vector2(lp.x, lp.z), 13.0, col, 0.55])
	# 沿街商铺溢光
	for b in blocks.keys():
		var info: Dictionary = blocks[b]
		if not (info.type in ["commercial", "cbd", "oldtown"]):
			continue
		var r: Rect2 = info.rect
		var k := 0.55 if info.type != "oldtown" else 0.35
		var step := 7.0
		var n := int(r.size.x / step)
		for s in n:
			var t := (s + 0.5) / n
			for p in [Vector2(r.position.x + t * r.size.x, r.position.y + 1.5), Vector2(r.position.x + t * r.size.x, r.end.y - 1.5),
					Vector2(r.position.x + 1.5, r.position.y + t * r.size.y), Vector2(r.end.x - 1.5, r.position.y + t * r.size.y)]:
				if rng.randf() < 0.6:
					continue
				var hue := rng.randf()
				var col := Color.from_hsv(hue, 0.35, 1.0) if rng.randf() < 0.5 else Color(1.0, 0.85, 0.65)
				_lights.append([p, 7.0, col, k * 0.6])


func _is_bright_street(ed: Dictionary) -> bool:
	var ij := graph.node_ij(ed.a)
	if ed.horizontal:
		return ij.y in [4, 6, 9, 10, 12]
	return ij.x in [5, 8, 11, 13]


func _paint_lightmap() -> void:
	var n := LM_SIZE
	var buf := PackedFloat32Array()
	buf.resize(n * n * 3)
	var sc := n / lm_rect.z
	for L in _lights:
		var pos: Vector2 = L[0]
		var rad: float = L[1]
		var col: Color = L[2]
		var inten: float = L[3]
		var cx := (pos.x - lm_rect.x) * sc
		var cy := (pos.y - lm_rect.y) * sc
		var rp := rad * sc
		var x0 := maxi(int(cx - rp), 0)
		var x1 := mini(int(cx + rp) + 1, n - 1)
		var y0 := maxi(int(cy - rp), 0)
		var y1 := mini(int(cy + rp) + 1, n - 1)
		var inv := 1.0 / (rp * rp)
		for y in range(y0, y1 + 1):
			var dy := y + 0.5 - cy
			for x in range(x0, x1 + 1):
				var dx := x + 0.5 - cx
				var f := 1.0 - (dx * dx + dy * dy) * inv
				if f <= 0.0:
					continue
				f = f * f * inten
				var i := (y * n + x) * 3
				buf[i] += col.r * f
				buf[i + 1] += col.g * f
				buf[i + 2] += col.b * f
	var bytes := PackedByteArray()
	bytes.resize(n * n * 3)
	for i in buf.size():
		var v := buf[i]
		v = v / (1.0 + v * 0.35)
		bytes[i] = clampi(int(v * 200.0), 0, 255)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGB8, bytes)
	lightmap_tex = ImageTexture.create_from_image(img)


func _ground_mat(kind: int) -> ShaderMaterial:
	var m := MeshKit.shader_mat("res://shaders/ground.gdshader")
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("road_w", W)
	m.set_shader_parameter("lightmap", lightmap_tex)
	m.set_shader_parameter("lm_rect", lm_rect)
	m.set_shader_parameter("noise_tex", noise_tex)
	return m


func _mesh_node(mesh: Mesh, mat: Material, shadows := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# ------------------------------------------------------------------ 地面与道路
func _build_ground() -> void:
	var far := 1400.0
	var st := MeshKit.begin()
	var nz0 := -half - far
	MeshKit.box(st, Vector3(0, -4.0, (nz0 + river_z0) * 0.5), Vector3(half * 2 + far * 2, 8.0, river_z0 - nz0))
	var sz1 := half + far
	MeshKit.box(st, Vector3(0, -4.0, (river_z1 + sz1) * 0.5), Vector3(half * 2 + far * 2, 8.0, sz1 - river_z1))
	_mesh_node(st.commit(), _ground_mat(4))

	# 人行道街区台
	var sw := MeshKit.begin()
	for b in blocks.keys():
		var info: Dictionary = blocks[b]
		if info.type == "river":
			continue
		var r: Rect2 = info.rect
		MeshKit.box(sw, Vector3(r.get_center().x, SLAB_Y * 0.5, r.get_center().y), Vector3(r.size.x, SLAB_Y, r.size.y))
	# 滨江步道
	for zz in [line_z(RIVER_ROW) + W * 0.5 + 1.5, line_z(RIVER_ROW + 1) - W * 0.5 - 1.5]:
		MeshKit.box(sw, Vector3(0, SLAB_Y * 0.5, zz), Vector3(half * 2 + 200.0, SLAB_Y, 3.0))
	_mesh_node(sw.commit(), _ground_mat(2))

	var gr := MeshKit.begin()
	for r in _courtyards:
		MeshKit.rect_xz(gr, r, SLAB_Y + 0.02)
	_mesh_node(gr.commit(), _ground_mat(3))
	var pk := MeshKit.begin()
	for r in _parkings:
		MeshKit.rect_xz(pk, r, SLAB_Y + 0.02)
	_mesh_node(pk.commit(), _ground_mat(5))


func _build_roads() -> void:
	var st := MeshKit.begin()
	for ed in graph.edges:
		var a: Vector3 = graph.positions[ed.a]
		var b: Vector3 = graph.positions[ed.b]
		var dir := (b - a).normalized()
		var pa := a + dir * W * 0.5
		var pb := b - dir * W * 0.5
		MeshKit.quad_xz(st, pa, pb, W, 0.04, Vector2(pa.distance_to(pb), 0))
	_mesh_node(st.commit(), _ground_mat(0))
	var js := MeshKit.begin()
	for id in graph.positions.size():
		if graph.adj[id].is_empty():
			continue
		var p := graph.positions[id]
		MeshKit.rect_xz(js, Rect2(p.x - W * 0.5, p.z - W * 0.5, W, W), 0.04)
	_mesh_node(js.commit(), _ground_mat(1))
	# 桥体与桥栏灯带
	var deck := MeshKit.begin()
	var rail := MeshKit.begin()
	for i in BRIDGES:
		var x := line_x(i)
		var z0 := line_z(RIVER_ROW) + W * 0.5
		var z1 := line_z(RIVER_ROW + 1) - W * 0.5
		var blen := z1 - z0
		MeshKit.box(deck, Vector3(x, -0.7, (z0 + z1) * 0.5), Vector3(W + 3.0, 1.5, blen + 2.0))
		for s in [-1.0, 1.0]:
			MeshKit.box(deck, Vector3(x + s * (W * 0.5 + 1.1), 0.5, (z0 + z1) * 0.5), Vector3(0.6, 1.0, blen))
			MeshKit.box(rail, Vector3(x + s * (W * 0.5 + 1.1), 1.05, (z0 + z1) * 0.5), Vector3(0.25, 0.12, blen))
			MeshKit.box(rail, Vector3(x + s * (W * 0.5 + 1.5), -1.0, (z0 + z1) * 0.5), Vector3(0.1, 0.18, blen))
		for k in 3:
			var pz := z0 + blen * (k + 0.5) / 3.0
			MeshKit.box(deck, Vector3(x, -3.0, pz), Vector3(W * 0.6, 4.0, 2.5))
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color(0.32, 0.33, 0.34)
	deck_mat.roughness = 0.8
	_mesh_node(deck.commit(), deck_mat, true)
	# 江岸护栏灯带
	for zz in [river_z0 - 0.3, river_z1 + 0.3]:
		MeshKit.box(rail, Vector3(0, SLAB_Y + 0.9, zz), Vector3(half * 2 + 200.0, 0.1, 0.1))
	_mesh_node(rail.commit(), MeshKit.emissive(Color(0.35, 0.85, 1.0), 5.0))


func _build_river() -> void:
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2 + 2800.0, river_z1 - river_z0 + 2.0)
	pm.subdivide_depth = 0
	water.mesh = pm
	var mat := MeshKit.shader_mat("res://shaders/water.gdshader")
	mat.set_shader_parameter("n1", MeshKit.noise_texture(0.03, 256, true))
	mat.set_shader_parameter("n2", MeshKit.noise_texture(0.06, 256, true))
	water.material_override = mat
	water.position = Vector3(0, -1.6, (river_z0 + river_z1) * 0.5)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


# ------------------------------------------------------------------ 实例化
func _build_instances() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = MeshKit.unit_box_mesh()
	mm.instance_count = _b_xf.size()
	for k in _b_xf.size():
		mm.set_instance_transform(k, _b_xf[k])
		mm.set_instance_custom_data(k, _b_cd[k])
	var bmat := MeshKit.shader_mat("res://shaders/building.gdshader")
	bmat.set_shader_parameter("lightmap", lightmap_tex)
	bmat.set_shader_parameter("lm_rect", lm_rect)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bmat
	add_child(mmi)

	# 行道树
	var tree_mesh := _tree_mesh()
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.mesh = tree_mesh
	tm.instance_count = _tree_xf.size()
	for k in _tree_xf.size():
		tm.set_instance_transform(k, _tree_xf[k])
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tm
	add_child(tmi)

	# 航空障碍灯
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.use_custom_data = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.9
	sphere.height = 1.8
	sphere.radial_segments = 8
	sphere.rings = 4
	bm.mesh = sphere
	bm.instance_count = _beacon_xf.size()
	for k in _beacon_xf.size():
		bm.set_instance_transform(k, _beacon_xf[k])
		bm.set_instance_custom_data(k, Color(rng.randf(), 0, 0, 0))
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = bm
	bmi.material_override = MeshKit.shader_mat("res://shaders/blink.gdshader")
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)


func _tree_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.25
	trunk.height = 2.6
	trunk.radial_segments = 5
	var st := MeshKit.begin()
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)))
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.16, 0.12, 0.09)
	st.set_material(tmat)
	st.commit(mesh)
	var crown := SphereMesh.new()
	crown.radius = 2.4
	crown.height = 4.2
	crown.radial_segments = 7
	crown.rings = 4
	var st2 := MeshKit.begin()
	st2.append_from(crown, 0, Transform3D(Basis.IDENTITY, Vector3(0, 4.2, 0)))
	st2.append_from(crown, 0, Transform3D(Basis.from_scale(Vector3(0.7, 0.7, 0.7)), Vector3(0.8, 5.6, 0.4)))
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.1, 0.19, 0.08)
	cmat.roughness = 0.95
	st2.set_material(cmat)
	st2.commit(mesh)
	return mesh


func _pole_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0, 4.5, 0), Vector3(0.22, 9.0, 0.22))
	MeshKit.box(st, Vector3(0, 8.9, -1.6), Vector3(0.14, 0.14, 3.2))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.21, 0.23)
	m.metallic = 0.6
	m.roughness = 0.5
	st.set_material(m)
	st.commit(mesh)
	var st2 := MeshKit.begin()
	MeshKit.box(st2, Vector3(0, 8.8, -3.0), Vector3(0.5, 0.18, 1.1))
	st2.set_material(MeshKit.emissive(Color(1.0, 0.8, 0.55), 5.0))
	st2.commit(mesh)
	return mesh


# ------------------------------------------------------------------ 查询
func random_incident_spot(r: RandomNumberGenerator) -> Dictionary:
	for attempt in 50:
		var e := r.randi() % graph.edges.size()
		if not graph.is_inner_edge(e):
			continue
		var ed: Dictionary = graph.edges[e]
		if (not ed.horizontal) and graph.node_ij(ed.a).y == RIVER_ROW:
			continue
		var t := r.randf_range(0.2, 0.8)
		var a: Vector3 = graph.positions[ed.a]
		var b: Vector3 = graph.positions[ed.b]
		var dir := (b - a).normalized()
		var right := Vector3(-dir.z, 0, dir.x)
		var side := 1.0 if r.randf() < 0.5 else -1.0
		var road_p := a.lerp(b, t)
		return {"edge": e, "t": t, "road": road_p + right * side * RoadGraph.LANE_OFFSET,
			"pos": road_p + right * side * (W * 0.5 + 1.5), "desc": graph.describe(e, t)}
	return {}
