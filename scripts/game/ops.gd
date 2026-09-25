class_name Ops
extends RefCounted
## 中国警务创新玩法（与《112》的差异化核心）：
##   1. 治安热力 + 见警率：辖区划为 40 米网格，风险 = 片区基础 × 时段 × 近期发案记忆 ÷ 见警率。
##      警情按风险加权生成；街面见警率越高，整体发案越少（“以巡压案”）。
##   2. 1-3-5 快反圈：以可调度警力为起点在路网上计算到达时间，道路按 1 / 3 / 5 分钟分级着色，超出即盲区。
##   3. 合成作战：抢劫等警情会产生逃逸嫌疑人；天网摄像头与警力目视暴露其位置，
##      自动 / 手动追缉，玩家可在路面设卡拦截。

const CELL := 40.0
const CAM_RANGE := 70.0
const SEE_RANGE := 60.0
const CATCH_RANGE := 14.0
const CHECKPOINT_RANGE := 12.0
const CHECKPOINT_COST := 5000.0
const CHECKPOINT_LIFE := 40.0
const CHECKPOINT_MAX := 3
const MAX_CHASERS := 2
const REACH_MINUTES := [1.0, 3.0, 5.0]

## 片区基础风险与昼夜系数 [白天, 夜间]
const ZONE_RISK := {
	"oldtown": [1.2, 1.5], "cbd": [1.1, 0.8], "commercial": [1.2, 1.3], "riverside": [0.8, 1.4],
	"school": [0.9, 0.4], "park": [0.7, 1.1], "residential": [0.7, 0.8],
}

var game: Game
var city: CityMap
var cols := 0
var rows := 0
var origin := Vector2.ZERO
var base: PackedFloat32Array
var memory: PackedFloat32Array
var presence: PackedFloat32Array
var risk: PackedFloat32Array
var cell_edges: Array = []        # cell -> Array[int]
var suppress := 1.0               # 当前发案抑制系数（0.45~1）
var seen_rate := 0.0              # 见警率：人口加权后有警力可见的网格占比
var cover5 := 0.0                 # 5 分钟到达覆盖率
var node_eta: PackedFloat32Array  # 各路网节点最快到达分钟

var cameras: Array = []           # {pos: Vector3, name: String}
var checkpoints: Array = []       # {pos, edge, life, name}
var suspects: Array = []
var placing := false

var _t_grid := 0.0
var _t_reach := 0.0
var _t_chase := 0.0
var _next_sid := 1
var _acc_dm := 0.0


func _init(p_game: Game) -> void:
	game = p_game
	city = game.city
	var P := city.play_rect
	origin = P.position
	cols = int(ceil(P.size.x / CELL))
	rows = int(ceil(P.size.y / CELL))
	var n := cols * rows
	base.resize(n)
	memory.resize(n)
	presence.resize(n)
	risk.resize(n)
	cell_edges.resize(n)
	for i in n:
		cell_edges[i] = []
		var c := cell_center(i)
		if Geometry2D.is_point_in_polygon(c, city.river_poly):
			base[i] = 0.0
		else:
			base[i] = 1.0
	for e in city.graph.edges.size():
		var ed: Dictionary = city.graph.edges[e]
		if ed.len < 12.0:
			continue
		var m: Vector3 = (city.graph.positions[ed.a] + city.graph.positions[ed.b]) * 0.5
		var i := cell_of(Vector2(m.x, m.z))
		if i >= 0 and not Geometry2D.is_point_in_polygon(Vector2(m.x, m.z), city.river_poly):
			cell_edges[i].append(e)
	for i in n:
		if cell_edges[i].is_empty():
			base[i] = 0.0
	node_eta.resize(city.graph.positions.size())
	_place_cameras()


# ================================================================== 网格
func cell_of(p: Vector2) -> int:
	var cx := int(floor((p.x - origin.x) / CELL))
	var cy := int(floor((p.y - origin.y) / CELL))
	if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
		return -1
	return cy * cols + cx


func cell_center(i: int) -> Vector2:
	return origin + Vector2((i % cols) + 0.5, (i / cols) + 0.5) * CELL


func _zone_factor(i: int, night: bool) -> float:
	var z := city._zone_for(cell_center(i))
	var f: Array = ZONE_RISK.get(z, [0.7, 0.8])
	return f[1] if night else f[0]


func _update_grid(dm: float) -> void:
	var h := GameState.hour()
	var night := h >= 19 or h < 6
	# 当前见警：路面单位对周围网格的可见度
	var now := PackedFloat32Array()
	now.resize(base.size())
	for u in game.units:
		if u.state == PoliceUnit.State.IDLE:
			continue
		var p := Vector2(u.global_position.x, u.global_position.z)
		var r := 90.0 if u.state == PoliceUnit.State.PATROL else 60.0
		var k := int(ceil(r / CELL))
		var ci := cell_of(p)
		if ci < 0:
			continue
		var cx := ci % cols
		var cy := ci / cols
		for dy in range(-k, k + 1):
			for dx in range(-k, k + 1):
				var x := cx + dx
				var y := cy + dy
				if x < 0 or y < 0 or x >= cols or y >= rows:
					continue
				var j := y * cols + x
				var d := cell_center(j).distance_to(p)
				now[j] += maxf(0.0, 1.0 - d / r)
	for cp in checkpoints:
		var j := cell_of(Vector2(cp.pos.x, cp.pos.z))
		if j >= 0:
			now[j] += 1.0
	var a := 1.0 - exp(-dm / 18.0)       # 见警率时间平滑（约 18 游戏分钟）
	var decay := exp(-dm / 120.0)        # 发案记忆衰减（约 2 小时）
	var total := 0.0
	var raw := 0.0
	var seen_w := 0.0
	var all_w := 0.0
	for i in base.size():
		if base[i] <= 0.0:
			risk[i] = 0.0
			continue
		presence[i] = lerpf(presence[i], minf(now[i], 2.0), a)
		memory[i] *= decay
		var r0 := base[i] * _zone_factor(i, night) * (1.0 + memory[i] * 0.45)
		risk[i] = r0 / (1.0 + presence[i] * 1.8)
		total += risk[i]
		raw += r0
		all_w += r0
		if presence[i] > 0.25:
			seen_w += r0
	suppress = clampf(total / maxf(raw, 0.001), 0.0, 1.0)
	seen_rate = seen_w / maxf(all_w, 0.001)


## 按风险加权抽取警情地点
func pick_spot(rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for r in risk:
		total += r
	if total <= 0.0:
		return city.random_incident_spot(rng)
	var x := rng.randf() * total
	for i in risk.size():
		x -= risk[i]
		if x <= 0.0:
			var es: Array = cell_edges[i]
			if es.is_empty():
				break
			return city.spot_on_edge(es[rng.randi() % es.size()], rng)
	return city.random_incident_spot(rng)


func note_incident(pos: Vector3, weight: float) -> void:
	var c := cell_of(Vector2(pos.x, pos.z))
	if c < 0:
		return
	var cx := c % cols
	var cy := c / cols
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= cols or y >= rows:
				continue
			memory[y * cols + x] += weight * (1.0 if dx == 0 and dy == 0 else 0.35)


func risk_max() -> float:
	var m := 0.0
	for r in risk:
		m = maxf(m, r)
	return m


# ================================================================== 1-3-5 快反圈
func _update_reach() -> void:
	var g := city.graph
	var n := g.positions.size()
	for i in n:
		node_eta[i] = INF
	# 多源 Dijkstra（节点数少，简单 O(n²) 实现即可）
	var done := PackedByteArray()
	done.resize(n)
	for u in game.units:
		if not u.is_available():
			continue
		var s := g.nearest_node(u.global_position)
		var v: float = u.info.speed / Data.MIN_PER_SEC   # 米 / 游戏分钟
		var t0: float = u.global_position.distance_to(g.positions[s]) / v
		if u.state == PoliceUnit.State.IDLE:
			t0 += 0.5  # 出车准备
		# 以统一速度 25 m/s 归一化：不同警种按各自速度折算起点偏移
		var eff: float = t0 * (25.0 / u.info.speed)
		if eff < node_eta[s]:
			node_eta[s] = eff
	var vref := 25.0 / Data.MIN_PER_SEC
	while true:
		var best := -1
		var bd := INF
		for i in n:
			if done[i] == 0 and node_eta[i] < bd:
				bd = node_eta[i]
				best = i
		if best < 0:
			break
		done[best] = 1
		for nb in g.adj[best]:
			var nd := bd + g.positions[best].distance_to(g.positions[nb]) / vref
			if nd < node_eta[nb]:
				node_eta[nb] = nd
	# 5 分钟覆盖率（按辖区内路段长度）
	var cov := 0.0
	var all := 0.0
	for ed in g.edges:
		var m: Vector3 = (g.positions[ed.a] + g.positions[ed.b]) * 0.5
		if not city.play_rect.has_point(Vector2(m.x, m.z)):
			continue
		all += ed.len
		if minf(node_eta[ed.a], node_eta[ed.b]) <= REACH_MINUTES[2]:
			cov += ed.len
	cover5 = cov / maxf(all, 1.0)


# ================================================================== 天网 / 卡口
func _place_cameras() -> void:
	var g := city.graph
	var cands: Array = []
	for i in g.positions.size():
		var p: Vector3 = g.positions[i]
		if not city.play_rect.grow(-30).has_point(Vector2(p.x, p.z)):
			continue
		if g.adj[i].size() < 3:
			continue
		var score := 0.0
		for nb in g.adj[i]:
			var e := g.edge_between(i, nb)
			score += float(g.edges[e].width)
		cands.append([score, i])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for c in cands:
		var p: Vector3 = g.positions[c[1]]
		var ok := true
		for cam in cameras:
			if cam.pos.distance_to(p) < 150.0:
				ok = false
				break
		if ok:
			var roads: Array = g.node_roads[c[1]]
			var name := "%s与%s路口" % [roads[0], roads[1]] if roads.size() >= 2 else "%s" % roads[0]
			cameras.append({"pos": p, "name": name, "node": c[1]})
		if cameras.size() >= 10:
			break


func can_place_checkpoint() -> String:
	if checkpoints.size() >= CHECKPOINT_MAX:
		return "卡点已达上限"
	if GameState.money < CHECKPOINT_COST:
		return "经费不足"
	return ""


func place_checkpoint(ground: Vector3) -> bool:
	var why := can_place_checkpoint()
	if why != "":
		GameState.advisor.emit(why + "，无法设卡。")
		return false
	var near := city.graph.nearest_edge_point(ground)
	if near.d > 30.0:
		GameState.advisor.emit("卡点要设在道路上。")
		return false
	var e: int = near.edge
	var pos := city.graph.point_on_edge(e, near.t)
	GameState.spend(CHECKPOINT_COST)
	var name := city.graph.describe(e, near.t)
	checkpoints.append({"pos": pos, "edge": e, "life": CHECKPOINT_LIFE, "name": name})
	GameState.post("指挥中心", "%s设立临时查控卡点，持续 %d 分钟。" % [name, int(CHECKPOINT_LIFE)], "cmd")
	GameState.stats_changed.emit()
	return true


# ================================================================== 嫌疑人
func spawn_suspect(inc: Incident) -> Suspect:
	for s in suspects:
		if s.incident == inc and s.state == Suspect.S.FLEE:
			return s
	var sp := Suspect.new()
	sp.id = _next_sid
	_next_sid += 1
	sp.incident = inc
	sp.setup(city.graph, inc.spot.edge, inc.spot.t, 9001 + sp.id * 31)
	# 报警滞后：嫌疑人已先逃出一段（约 3 游戏分钟）
	for k in 60:
		sp.tick(0.1, 0.05, [])
	suspects.append(sp)
	inc.suspect = sp
	return sp


## 接警问到逃跑方向：暴露嫌疑人当前位置
func tip_off(inc: Incident) -> void:
	var sp: Suspect = inc.suspect
	if sp == null or sp.state != Suspect.S.FLEE:
		return
	sp.mark_seen("报警人")
	GameState.post("110 接警台", "报警人指认嫌疑人逃跑方向，已通报各巡组注意%s一带。" % _where(sp.pos), "call")


func _where(p: Vector3) -> String:
	var near := city.graph.nearest_edge_point(p)
	return city.graph.describe(near.edge, near.t)


func chasers(sp: Suspect) -> Array:
	return game.units.filter(func(u): return u.chase_target == sp)


func order_chase(u: PoliceUnit, sp: Suspect) -> void:
	if sp.state != Suspect.S.FLEE:
		return
	var target := sp.pos if sp.seen else sp.last_seen
	u.chase_to(sp, target)
	GameState.post(u.callsign, "收到，前往追缉嫌疑人！", "unit")
	game.units_changed.emit()


func _tick_suspects(dt: float, dm: float, delta: float) -> void:
	var threats: Array = []
	for u in game.units:
		if u.state != PoliceUnit.State.IDLE:
			threats.append(u.global_position)
	for sp in suspects.duplicate():
		if sp.state != Suspect.S.FLEE:
			sp.fade += delta
			if sp.fade > 6.0:
				suspects.erase(sp)
			continue
		var was_seen: bool = sp.seen
		sp.tick(dt, dm, threats)
		sp.seen = false
		var spotter := ""
		for cam in cameras:
			if cam.pos.distance_to(sp.pos) < CAM_RANGE:
				spotter = "天网"
				if not was_seen:
					GameState.post("天网系统", "%s摄像头比中嫌疑人，正向%s逃窜。" % [cam.name, _where(sp.pos + sp.heading() * 40.0)], "lv3")
				break
		for u in game.units:
			if u.state == PoliceUnit.State.IDLE:
				continue
			var d: float = u.global_position.distance_to(sp.pos)
			if d < SEE_RANGE:
				if spotter == "" and not was_seen:
					GameState.post(u.callsign, "发现嫌疑人！就在%s！" % _where(sp.pos), "lv3")
				spotter = u.callsign
			if d < CATCH_RANGE and u.chase_target == sp:
				_catch(sp, u.callsign, "")
				break
		if sp.state != Suspect.S.FLEE:
			continue
		for cp in checkpoints:
			if cp.pos.distance_to(sp.pos) < CHECKPOINT_RANGE:
				_catch(sp, "卡点民警", cp.name)
				break
		if sp.state != Suspect.S.FLEE:
			continue
		if spotter != "":
			sp.mark_seen(spotter)
		var out := not city.play_rect.grow(10).has_point(Vector2(sp.pos.x, sp.pos.z))
		if out or sp.time_left <= 0.0:
			_escape(sp, "已逃出辖区" if out else "脱离视线，追缉中止")


func _catch(sp: Suspect, who: String, where: String) -> void:
	sp.state = Suspect.S.CAUGHT
	GameState.earn(8000.0)
	GameState.adjust(2.0, 1.5)
	GameState.stats.caught = int(GameState.stats.get("caught", 0)) + 1
	if where != "":
		GameState.post(who, "%s卡点成功拦截嫌疑人，已控制！" % where, "good")
	else:
		GameState.post(who, "嫌疑人已被抓获！%s。" % _where(sp.pos), "good")
	if sp.incident and sp.incident.is_active() and sp.incident.state == Incident.S.ONSCENE:
		sp.incident.progress += 0.4
	_release_chasers(sp)


func _escape(sp: Suspect, why: String) -> void:
	sp.state = Suspect.S.ESCAPED
	GameState.adjust(-2.0, -2.0)
	GameState.stats.escaped = int(GameState.stats.get("escaped", 0)) + 1
	GameState.post("指挥中心", "抢劫嫌疑人%s，转侦查部门后续追查。" % why, "lv4")
	_release_chasers(sp)


func _release_chasers(sp: Suspect) -> void:
	for u in chasers(sp):
		u.release(true)
	game.units_changed.emit()


## 自动追缉 + 追缉路线重规划
func _chase_logic() -> void:
	for sp in suspects:
		if sp.state != Suspect.S.FLEE:
			continue
		var cs := chasers(sp)
		# 失去目标过久：收队
		if sp.seen_age > 10.0 and not cs.is_empty():
			for u in cs:
				u.release(true)
			GameState.post("指挥中心", "嫌疑人失去踪迹，追缉组恢复巡逻，天网持续布控。", "info")
			game.units_changed.emit()
			continue
		var target: Vector3 = sp.pos if sp.seen else sp.last_seen
		for u in cs:
			u.chase_to(sp, target)
		if not GameState.auto_dispatch or sp.seen_age > 3.0:
			continue
		var guard := 0
		while cs.size() < MAX_CHASERS and guard < MAX_CHASERS:
			guard += 1
			var best: PoliceUnit = null
			var bd := INF
			for u in game.units:
				if not u.is_available() or u.kind == "swat":
					continue
				var d: float = u.global_position.distance_to(target)
				if d < bd and d < 420.0:
					bd = d
					best = u
			if best == null:
				break
			best.chase_to(sp, target)
			GameState.post("指挥中心", "%s，嫌疑人在%s逃窜，立即追缉！" % [best.callsign, _where(target)], "cmd")
			cs.append(best)
			game.units_changed.emit()


# ================================================================== 主循环
func tick(delta: float, dt: float, dm: float) -> void:
	_t_grid -= delta
	_acc_dm += dm
	if _t_grid <= 0.0:
		_t_grid = 0.5
		_update_grid(_acc_dm)
		_acc_dm = 0.0
	_t_reach -= delta
	if _t_reach <= 0.0:
		_t_reach = 0.6
		_update_reach()
	for cp in checkpoints.duplicate():
		cp.life -= dm
		if cp.life <= 0.0:
			checkpoints.erase(cp)
			GameState.post("指挥中心", "%s卡点撤收。" % cp.name, "info")
	_tick_suspects(dt, dm, delta)
	_t_chase -= delta
	if _t_chase <= 0.0:
		_t_chase = 1.2
		_chase_logic()
