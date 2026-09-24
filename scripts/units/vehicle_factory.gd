class_name VehicleFactory
extends RefCounted
## 车辆几何：社会车辆（单网格 + 实例色）、警车（分部件，警灯可控）。

const SCALE := 1.35


static func civilian_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0, 0.62, 0), Vector3(1.85, 0.8, 4.4))
	MeshKit.box(st, Vector3(0, 1.3, 0.25), Vector3(1.65, 0.56, 2.3))
	var mesh := st.commit()
	mesh.surface_set_material(0, MeshKit.shader_mat("res://shaders/car.gdshader"))
	return mesh


## 车头灯光斑四边形：从车头向前延伸
static func headlight_mesh(length := 16.0, width := 7.0) -> ArrayMesh:
	var st := MeshKit.begin()
	var z0 := -2.1
	var z1 := z0 - length
	var hw := width * 0.5
	var p0 := Vector3(-hw, 0.06, z0)
	var p1 := Vector3(hw, 0.06, z0)
	var p2 := Vector3(hw, 0.06, z1)
	var p3 := Vector3(-hw, 0.06, z1)
	var verts := [p0, p1, p2, p0, p2, p3]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for k in 6:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[k])
		st.add_vertex(verts[k])
	var mesh := st.commit()
	mesh.surface_set_material(0, MeshKit.shader_mat("res://shaders/headlight.gdshader"))
	return mesh


## 警用车辆：返回 {root, bar_red, bar_blue, light}
static func build_police(kind: String, body: Color, stripe: Color) -> Dictionary:
	var root := Node3D.new()
	var st := MeshKit.begin()
	var moto := kind == "traffic"
	var big := kind == "swat"
	var bar_y := 1.62
	if moto:
		MeshKit.box(st, Vector3(0, 0.55, 0), Vector3(0.55, 0.6, 2.1), body)
		MeshKit.box(st, Vector3(0, 1.05, 0.25), Vector3(0.5, 0.55, 0.6), Color(0.1, 0.12, 0.15))
		MeshKit.box(st, Vector3(0, 0.62, 0), Vector3(0.6, 0.12, 2.12), stripe)
		bar_y = 1.45
	elif big:
		MeshKit.box(st, Vector3(0, 0.95, 0), Vector3(2.3, 1.5, 5.4), body)
		MeshKit.box(st, Vector3(0, 1.95, 0.2), Vector3(2.2, 0.55, 4.2), body.darkened(0.2))
		MeshKit.box(st, Vector3(0, 1.05, 0), Vector3(2.32, 0.28, 5.42), stripe)
		MeshKit.box(st, Vector3(0, 1.55, -2.72), Vector3(2.0, 0.5, 0.05), Color(0.03, 0.03, 0.04))
		bar_y = 2.35
	else:
		MeshKit.box(st, Vector3(0, 0.62, 0), Vector3(1.9, 0.8, 4.6), body)
		MeshKit.box(st, Vector3(0, 1.3, 0.25), Vector3(1.7, 0.56, 2.4), body)
		MeshKit.box(st, Vector3(0, 1.28, 0.25), Vector3(1.72, 0.44, 2.2), Color(0.03, 0.035, 0.045))
		MeshKit.box(st, Vector3(0, 0.72, 0), Vector3(1.92, 0.22, 4.62), stripe)
		# 前后机盖字样区
		MeshKit.box(st, Vector3(0, 1.03, -1.6), Vector3(1.1, 0.02, 0.6), stripe)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.35
	mat.metallic = 0.3
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)

	# 车灯
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	var hl_w := 0.35 if moto else (2.0 if big else 1.7)
	hb.size = Vector3(hl_w, 0.18, 0.05)
	head.mesh = hb
	head.material_override = MeshKit.emissive(Color(1, 0.96, 0.9), 6.0)
	head.position = Vector3(0, 0.75 if not big else 0.9, -(1.06 if moto else (2.71 if big else 2.31)))
	root.add_child(head)
	var tail := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(hl_w, 0.14, 0.05)
	tail.mesh = tb
	tail.material_override = MeshKit.emissive(Color(1, 0.05, 0.03), 3.0)
	tail.position = Vector3(0, 0.8, (1.06 if moto else (2.71 if big else 2.31)))
	root.add_child(tail)

	# 警灯条
	var bw := 0.22 if moto else 0.62
	var red := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(bw, 0.16, 0.3)
	red.mesh = rb
	var red_mat := MeshKit.emissive(Color(1.0, 0.08, 0.1), 0.4)
	red.material_override = red_mat
	red.position = Vector3(-bw * 0.5 - 0.02, bar_y, 0.1 if not moto else 0.5)
	root.add_child(red)
	var blue := MeshInstance3D.new()
	blue.mesh = rb
	var blue_mat := MeshKit.emissive(Color(0.1, 0.3, 1.0), 0.4)
	blue.material_override = blue_mat
	blue.position = Vector3(bw * 0.5 + 0.02, bar_y, 0.1 if not moto else 0.5)
	root.add_child(blue)

	var light := OmniLight3D.new()
	light.omni_range = 22.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.position = Vector3(0, bar_y + 1.2, 0)
	root.add_child(light)

	var hl := MeshInstance3D.new()
	hl.mesh = headlight_mesh(12.0 if moto else 16.0, 4.0 if moto else 7.0)
	hl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hl)

	root.scale = Vector3.ONE * SCALE
	return {"root": root, "red": red_mat, "blue": blue_mat, "light": light}
