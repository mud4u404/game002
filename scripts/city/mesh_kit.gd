class_name MeshKit
extends RefCounted
## 程序化几何的小工具集。


## 向 SurfaceTool 追加一个轴对齐盒子（带法线、UV、顶点色）
static func box(st: SurfaceTool, center: Vector3, size: Vector3, color := Color.WHITE, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var uu := u * h
		var vv := v * h
		var p0 := c - uu - vv
		var p1 := c + uu - vv
		var p2 := c + uu + vv
		var p3 := c - uu + vv
		# Godot 以顺时针为正面
		var pts := [p0, p2, p1, p0, p3, p2]
		var uvs := [Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)]
		for k in 6:
			st.set_color(color)
			st.set_normal((basis * n).normalized())
			st.set_uv(uvs[k])
			st.add_vertex(center + basis * (pts[k] as Vector3))


## 水平四边形（y 向上），UV.x 横向 0..1，UV.y 纵向为米
static func quad_xz(st: SurfaceTool, a: Vector3, b: Vector3, width: float, y: float, uv2 := Vector2.ZERO) -> void:
	var d := b - a
	d.y = 0
	var L := d.length()
	var dir := d / L
	var side := Vector3(-dir.z, 0, dir.x) * width * 0.5
	var p0 := a - side
	var p1 := a + side
	var p2 := b + side
	var p3 := b - side
	p0.y = y; p1.y = y; p2.y = y; p3.y = y
	var verts := [p0, p2, p1, p0, p3, p2]
	var uvs := [Vector2(0, 0), Vector2(1, L), Vector2(1, 0), Vector2(0, 0), Vector2(0, L), Vector2(1, L)]
	for k in 6:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[k])
		st.set_uv2(uv2)
		st.add_vertex(verts[k])


static func rect_xz(st: SurfaceTool, r: Rect2, y: float) -> void:
	var p0 := Vector3(r.position.x, y, r.position.y)
	var p1 := Vector3(r.end.x, y, r.position.y)
	var p2 := Vector3(r.end.x, y, r.end.y)
	var p3 := Vector3(r.position.x, y, r.end.y)
	for p in [p0, p1, p2, p0, p2, p3]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p.x, p.z))
		st.set_uv2(Vector2.ZERO)
		st.add_vertex(p)


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func unit_box_mesh() -> ArrayMesh:
	var st := begin()
	box(st, Vector3.ZERO, Vector3.ONE)
	return st.commit()


static func shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


static func emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func noise_texture(freq: float, size := 256, normal := false) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 4
	t.noise = n
	t.width = size
	t.height = size
	t.seamless = true
	t.as_normal_map = normal
	if normal:
		t.bump_strength = 6.0
	t.generate_mipmaps = true
	return t
