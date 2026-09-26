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


func req(use_true := false) -> Dictionary:
	return (true_data() if use_true else data()).get("req", {})


func need() -> int:
	return Data.req_count(req())


## 缺口：{专长: 缺少数量}。only_on_scene 为 true 时只计已到场警力
func missing(only_on_scene := false, use_true := false) -> Dictionary:
	var have := {}
	for u in (on_scene_units() if only_on_scene else units):
		var k: String = u.skill()
		have[k] = int(have.get(k, 0)) + 1
	var out := {}
	var r := req(use_true)
	for k in r.keys():
		var gap := int(r[k]) - int(have.get(k, 0))
		if gap > 0:
			out[k] = gap
	if r.is_empty() and (on_scene_units() if only_on_scene else units).is_empty():
		out["any"] = 1
	return out


## 某专长的状态：done 已到场满足 / enroute 在途 / missing 缺
func skill_state(k: String) -> String:
	var r := req()
	var n := int(r.get(k, 0))
	var on := 0
	var all := 0
	for u in units:
		if u.skill() == k:
			all += 1
			if u.state == PoliceUnit.State.ONSCENE:
				on += 1
	if on >= n:
		return "done"
	if all >= n:
		return "enroute"
	return "missing"


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
