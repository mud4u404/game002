class_name CityEvent
extends RefCounted
## 大型活动安保：班前报备 → 预先布警 → 活动期人流警情 → 结算。

var id := ""
var data: Dictionary = {}
var pos := Vector3.ZERO
var day := 1
var guard: Array = []          # PoliceUnit
var failed := 0
var total_spawned := 0
var settled := false
var success := false
var started := false


func name() -> String:
	return String(data.get("name", "活动"))


func start_hour() -> float:
	return float(data.get("start", 19.0))


func end_hour() -> float:
	return float(data.get("end", 22.0))


func need() -> Dictionary:
	return data.get("need", {})


func types() -> Array:
	return data.get("types", [])


func base_rate() -> float:
	return float(data.get("rate", 0.02))


func is_now() -> bool:
	var h := GameState.hour()
	return h >= start_hour() and h < end_hour()


func is_upcoming() -> bool:
	return GameState.hour() < start_hour()


func contains(p: Vector3) -> bool:
	return Vector3(p.x, 0, p.z).distance_to(pos) <= Data.EVENT_RADIUS


## 到位警力数
func have(skill: String) -> int:
	var n := 0
	for u in guard:
		if u != null and u.skill() == skill:
			n += 1
	return n


## 覆盖率 0..1
func coverage(skill: String) -> float:
	var need_n := int(need().get(skill, 0))
	if need_n <= 0:
		return 1.0
	return clampf(float(have(skill)) / float(need_n), 0.0, 1.0)


## 平均覆盖率
func avg_coverage() -> float:
	var n := 0
	var s := 0.0
	for k in need().keys():
		s += coverage(String(k))
		n += 1
	return s / float(maxi(n, 1))


## 额外发案率倍率（覆盖越高越低）
func rate_mult() -> float:
	return clampf(1.0 - Data.EVENT_COVER_SUPPRESS * avg_coverage(), 0.05, 1.0)


## 覆盖不足的专长（<50%）：对应警情升 1 级
func weak_skills() -> Dictionary:
	var out := {}
	for k in need().keys():
		if coverage(String(k)) < 0.5:
			out[String(k)] = true
	return out


## 专长是否属于本活动弱项
func weak_for_type(type_id: String) -> bool:
	var weak := weak_skills()
	if weak.is_empty():
		return false
	var req: Dictionary = Data.INCIDENTS.get(type_id, {}).get("req", {})
	for k in req.keys():
		if weak.has(String(k)):
			return true
	return false
