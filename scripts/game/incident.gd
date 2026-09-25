class_name Incident
extends RefCounted
## 警情：真实类型（隐藏）与研判类型（调度依据）分离。

enum S { CALL, WAITING, DISPATCHED, ONSCENE, DONE, FAILED }
const STATE_NAMES := ["来电", "待派", "出警中", "处置中", "已结案", "失败"]

var id := 0
var true_type := ""
var shown_type := ""
var spot: Dictionary
var created := 0.0            # 游戏分钟
var state := S.WAITING
var deadline := 0.0           # 剩余升级时限（游戏分钟）
var units: Array = []         # PoliceUnit
var progress := 0.0
var call: Dictionary = {}     # 接警剧本
var call_wait := 0.0
var asked: Array = []         # 已问问题索引
var classified := false
var revealed := false
var arrival := -1.0           # 首个单位到场时刻
var stalled := false
var marker: Node3D
var ring_mat: ShaderMaterial
var beam_mat: ShaderMaterial
var escalations := 0
var suspect = null            # Suspect（抢劫等警情的逃逸嫌疑人）


func data() -> Dictionary:
	return Data.INCIDENTS[shown_type]


func true_data() -> Dictionary:
	return Data.INCIDENTS[true_type]


func level() -> int:
	return int(data().level)


func title() -> String:
	return data().name


func desc() -> String:
	return spot.desc


func is_active() -> bool:
	return state != S.DONE and state != S.FAILED


func on_scene_units() -> Array:
	var out := []
	for u in units:
		if u.state == PoliceUnit.State.ONSCENE:
			out.append(u)
	return out


func max_force(only_on_scene := false) -> int:
	var f := 0
	for u in (on_scene_units() if only_on_scene else units):
		f = maxi(f, u.force())
	return f


func unassign(u) -> void:
	units.erase(u)
	if units.is_empty() and state in [S.DISPATCHED, S.ONSCENE]:
		state = S.WAITING


func elapsed(now: float) -> float:
	return now - created


func build_marker(parent: Node3D) -> void:
	marker = Node3D.new()
	marker.position = Vector3(spot.pos.x, 0.3, spot.pos.z)
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(26, 26)
	q.orientation = PlaneMesh.FACE_Y
	ring.mesh = q
	ring_mat = MeshKit.shader_mat("res://shaders/marker_ring.gdshader")
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(ring)
	parent.add_child(marker)
	refresh_marker()


func refresh_marker() -> void:
	if ring_mat == null:
		return
	var c := Data.level_color(level())
	ring_mat.set_shader_parameter("color", c)
	var calm := state == S.ONSCENE
	ring_mat.set_shader_parameter("speed", 0.35 if calm else 0.8)
	ring_mat.set_shader_parameter("intensity", 1.6 if calm else 2.6)


func free_marker() -> void:
	if marker:
		marker.queue_free()
		marker = null
