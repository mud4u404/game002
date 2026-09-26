class_name Game
extends Node3D
## 游戏主控：城市、单位、警情生成、自动派警、处置结算、玩家指令。

signal incident_added(inc: Incident)
signal incident_updated(inc: Incident)
signal incident_removed(inc: Incident)
signal call_incoming(inc: Incident)
signal selection_changed(obj)
signal units_changed

const SEED := 20260924
## 交接班时移交的基础警力（其余由玩家在班前部署中组建）
const INITIAL_UNITS := {
	"station": {"community": 1},
	"patrol_hq": {"patrol": 2},
	"traffic_hq": {"traffic": 1},
}
## 开班后的引导警情：依次体验交管 / 调解 / 处突三种专长
const OPENING := [[6.0, "traffic_minor"], [34.0, "dispute"], [64.0, "fight"]]

var city: CityMap
var env: EnvironmentRig
var traffic: Traffic
var cam: RTSCamera
var hud: HUD
var ops: Ops
var units: Array = []
var incidents: Array = []
var selected = null
var answering: Incident = null   # 接警台当前通话
var rng := RandomNumberGenerator.new()

var _next_inc := 1
var _next_uid := 1
var _numbers := {}
var _dispatch_t := 0.0
var _markers: Node3D
var _tut := {}
var _advisor_t := 0.0
var _finished: Array = []   # [Incident, remove_at_real_time]
var _time := 0.0
var _started := false
var phase := "setup"          # setup 班前部署 → shift 值班中
var _shift_t := 0.0
var _opening: Array = []


func _ready() -> void:
	GameState.reset()
	if DevTools.args.has("shot-hour"):
		GameState.minutes = float(DevTools.args["shot-hour"]) * 60.0
	rng.seed = SEED + 1
	city = CityMap.new()
	add_child(city)
	env = EnvironmentRig.new()
	add_child(env)
	cam = RTSCamera.new()
	add_child(cam)
	var pr := city.play_rect
	cam.bounds = pr.grow(-40)
	cam.set_view(Vector3(pr.get_center().x + 20, 0, pr.get_center().y), 600, 0)
	env.apply(GameState.time_of_day())
	await city.build(SEED)
	_markers = Node3D.new()
	add_child(_markers)
	ops = Ops.new(self)
	cam.clicked.connect(_on_click)
	cam.right_clicked.connect(_on_right_click)
	for f in city.facilities:
		var plan: Dictionary = INITIAL_UNITS.get(f.type, {})
		for kind in plan.keys():
			for k in plan[kind]:
				_spawn_unit(kind, f)
	GameState.staff_used = _staff_count()
	hud = HUD.new()
	add_child(hud)
	hud.setup(self)
	env.apply(GameState.time_of_day())
	GameState.post("指挥中心", "交接班：请指挥长完成班前部署——组建警力、划定巡区。", "sys")
	_started = true
	hud.enter_setup()
	if DevTools.args.has("bot"):
		for kind in ["swat", "patrol", "community", "traffic"]:
			recruit(kind)
		for u in units:
			if u.info.patrol:
				u.set_zone(u.facility.center, ZONE_RADIUS.get(u.kind, 150.0) * 1.6, false)
	if DevTools.args.has("skip-setup") or DevTools.args.has("quit-frames"):
		start_shift()
	_dev_hooks()


## 班前部署结束，开始值班
func start_shift() -> void:
	if phase != "setup":
		return
	phase = "shift"
	_shift_t = 0.0
	_opening = OPENING.duplicate(true)
	for u in units:
		if u.zone_set and u.incident == null:
			u.start_patrol()
	var zones := units.filter(func(u): return u.zone_set).size()
	GameState.post("指挥中心", "部署完毕：%d 组警力上路巡逻，%d 组驻地待命。开始值班！" % [zones, units.size() - zones], "sys")
	hud.enter_shift()
	# 缺少某个专长的警种：提醒该类警情将无人能处置
	var lacking := []
	for k in Data.SKILLS.keys():
		if not units.any(func(u): return u.skill() == k):
			lacking.append("%s（%s）" % [Data.SKILLS[k].name, Data.UNIT_TYPES[Data.SKILLS[k].unit].short])
	if not lacking.is_empty():
		GameState.post("值班长", "注意：没有%s警力，这类警情将无人能处置。" % "、".join(lacking), "lv3")
	_tut_once("shift", "开始值班。系统会按就近、警种对口自动派警；来电要你亲自研判定性。对口警力不够时，警情会亮红，需要你调度或组建。")


func _dev_hooks() -> void:
	var a: Dictionary = DevTools.args
	if a.has("test-busy"):
		for k in 6:
			spawn_incident()
	if a.has("test-call"):
		var inc := spawn_incident("armed")
		await get_tree().create_timer(0.5).timeout
		hud.open_call(inc)
		await get_tree().create_timer(1.0).timeout
		hud.call_panel._on_ask(0, hud.call_panel._q_box.get_child(0))
		await get_tree().create_timer(1.2).timeout
		hud.call_panel._on_ask(2, hud.call_panel._q_box.get_child(2))
	if a.has("test-recruit"):
		await get_tree().create_timer(0.5).timeout
		hud.toggle_recruit()
	if a.has("test-units"):
		await get_tree().create_timer(1.0).timeout
		hud._show_units()
	if a.has("test-levelup"):
		await get_tree().create_timer(2.0).timeout
		var target: PoliceUnit = null
		for u in units:
			if u.kind == "patrol":
				target = u
				break
		if target == null and not units.is_empty():
			target = units[0]
		if target != null:
			target.gain_xp(Data.XP_PER_LEVEL * float(target.level))
			target.gain_xp(Data.XP_PER_LEVEL * float(target.level))
			select(target)
			cam.focus_on(target.global_position, 280)
	if a.has("test-report"):
		await get_tree().create_timer(2.0).timeout
		hud.day_report_panel.show_for_test()
	if a.has("layers"):
		for id in str(a["layers"]).split(","):
			hud.toggle_layer(id)
	if a.has("test-suspect"):
		var inc := spawn_incident("robbery")
		if inc.state == Incident.S.CALL:
			classify(inc, "robbery")
		await get_tree().create_timer(float(a.get("suspect-wait", "4"))).timeout
		for sp in ops.suspects:
			if not a.has("suspect-hidden"):
				sp.mark_seen("天网")
			if a.has("test-checkpoint"):
				ops.place_checkpoint(sp.pos + sp.heading() * 160.0)
			select(sp)
			cam.focus_on(sp.pos, 380)
	if a.has("test-zone"):
		await get_tree().create_timer(1.0).timeout
		for u in units:
			if u.kind == "patrol":
				u.set_zone(Vector3(-150, 0, 40), 150.0)
				select(u)
				break
	if a.has("test-select"):
		await get_tree().create_timer(2.0).timeout
		for inc in incidents:
			if inc.state != Incident.S.CALL:
				select(inc)
				cam.focus_on(inc.spot.pos, 260)
				break


# ------------------------------------------------------------------ 单位
func _spawn_unit(kind: String, fac: Dictionary) -> PoliceUnit:
	var used := 0
	for u in units:
		if u.facility == fac:
			used += 1
	if used >= fac.spots.size():
		return null
	var n: int = _numbers.get(kind, 0) + 1
	_numbers[kind] = n
	var u := PoliceUnit.new()
	add_child(u)
	u.setup(_next_uid, kind, fac, fac.spots[used], city.graph, n)
	_next_uid += 1
	units.append(u)
	units_changed.emit()
	return u


func _staff_count() -> int:
	var s := 0
	for u in units:
		s += int(u.info.staff)
	return s


func facilities_of(kind: String) -> Array:
	var ftype: String = Data.UNIT_TYPES[kind].facility
	var out := []
	for f in city.facilities:
		if f.type == ftype:
			out.append(f)
	return out


func can_recruit(kind: String) -> String:
	var d: Dictionary = Data.UNIT_TYPES[kind]
	if GameState.money < d.cost:
		return "经费不足"
	if GameState.staff_used + int(d.staff) > GameState.staff_cap:
		return "编制不足"
	for f in facilities_of(kind):
		var used := 0
		for u in units:
			if u.facility == f:
				used += 1
		if used < f.spots.size():
			return ""
	return "车位已满"


func recruit(kind: String) -> PoliceUnit:
	if can_recruit(kind) != "":
		return null
	var d: Dictionary = Data.UNIT_TYPES[kind]
	for f in facilities_of(kind):
		var u := _spawn_unit(kind, f)
		if u:
			u.bought_in_setup = phase == "setup"
			GameState.spend(d.cost)
			GameState.staff_used = _staff_count()
			GameState.post(f.name, "新编组 %s（%s）完成组建，已纳入指挥序列。" % [u.callsign, d.name], "good")
			GameState.stats_changed.emit()
			return u
	return null


## 班前部署时撤销新组建的编组（全额退款）
func disband(kind: String) -> bool:
	if phase != "setup":
		return false
	for i in range(units.size() - 1, -1, -1):
		var u: PoliceUnit = units[i]
		if u.kind == kind and u.bought_in_setup:
			units.remove_at(i)
			GameState.earn(float(u.info.cost))
			GameState.stats.money_earned = int(GameState.stats.get("money_earned", 0))
			if UIKit.same(selected, u):
				select(null)
			u.queue_free()
			_numbers[kind] = int(_numbers.get(kind, 1)) - 1
			GameState.staff_used = _staff_count()
			GameState.stats_changed.emit()
			units_changed.emit()
			return true
	return false


func bought_count(kind: String) -> int:
	return units.filter(func(u): return u.kind == kind and u.bought_in_setup).size()


# ------------------------------------------------------------------ 主循环
func _process(delta: float) -> void:
	if not _started:
		return
	if phase == "setup":
		ops.tick(delta, 0.0, 0.0)
		return
	_time += delta
	_shift_t += delta
	var dt := GameState.scaled_delta(delta)
	var dm := GameState.advance(delta)
	env.apply(GameState.time_of_day())

	for u in units:
		if u.tick(dt, dm):
			_on_unit_arrived(u)

	for inc in incidents.duplicate():
		_tick_incident(inc, dm)
	ops.tick(delta, dt, dm)

	# 已结案警情延迟移除
	for pair in _finished.duplicate():
		if _time >= pair[1]:
			_finished.erase(pair)
			var inc: Incident = pair[0]
			incidents.erase(inc)
			inc.free_marker()
			if UIKit.same(selected, inc):
				select(null)
			incident_removed.emit(inc)

	# 警情生成
	var active := 0
	for inc in incidents:
		if inc.is_active():
			active += 1
	# 见警率压降发案：路面警力越密，整体发案率越低（0.45 ~ 1 倍）
	# 节奏：警情少而精，每一起都需要指挥长决策
	var rate := 0.045 * Data.hour_intensity(GameState.hour()) * (1.0 + (GameState.day() - 1) * 0.15) * (0.45 + 0.55 * ops.suppress) * 1.25
	var pending := 0
	for inc in incidents:
		if inc.state in [Incident.S.CALL, Incident.S.WAITING]:
			pending += 1
	if not _opening.is_empty():
		if _shift_t >= _opening[0][0]:
			var item: Array = _opening.pop_front()
			spawn_incident(item[1], true)
	elif _shift_t > 80.0 and active < 8 and pending < 3 and rng.randf() < rate * dm:
		spawn_incident()

	_dispatch_t -= delta
	if _dispatch_t <= 0.0:
		_dispatch_t = 0.3
		_auto_dispatch()

	# 经费维持与指标漂移
	if dm > 0.0:
		var upkeep := 0.0
		for u in units:
			upkeep += float(u.info.upkeep)
		GameState.money -= upkeep / 1440.0 * dm
		var load := 0.0
		for inc in incidents:
			if inc.is_active() and inc.state != Incident.S.CALL:
				load += inc.level()
		var target := 56.0 + 16.0 * ops.seen_rate
		GameState.safety = clampf(GameState.safety + ((target - GameState.safety) * 0.006 - load * 0.006) * dm, 0.0, 100.0)
		GameState.opinion = clampf(GameState.opinion + (62.0 - GameState.opinion) * 0.003 * dm, 0.0, 100.0)

	_tutorial_tick(delta)


# ------------------------------------------------------------------ 警情
func spawn_incident(force_type := "", guided := false) -> Incident:
	var hour := GameState.hour()
	var type_id := force_type
	if type_id == "":
		var total := 0.0
		var weights := {}
		for t in Data.INCIDENTS.keys():
			var w: float = Data.hour_weight(t, hour)
			weights[t] = w
			total += w
		var r := rng.randf() * total
		for t in weights.keys():
			r -= weights[t]
			if r <= 0.0:
				type_id = t
				break
		if type_id == "":
			type_id = "dispute"
	var spot := {}
	for tries in 12:
		spot = ops.pick_spot(rng) if force_type == "" else city.random_incident_spot(rng)
		var ok := true
		for other in incidents:
			if other.is_active() and other.spot.pos.distance_to(spot.pos) < 50.0:
				ok = false
				break
		if ok:
			break
	var inc := Incident.new()
	inc.id = _next_inc
	_next_inc += 1
	inc.true_type = type_id
	inc.shown_type = type_id
	inc.spot = spot
	inc.created = GameState.minutes
	inc.deadline = float(Data.INCIDENTS[type_id].deadline)
	var lvl: int = Data.INCIDENTS[type_id].level
	var wants_call := not guided and (lvl >= 3 or type_id == "prank" or (lvl == 2 and rng.randf() < 0.5))
	if wants_call:
		var pool := []
		for c in Data.CALLS:
			if c["true"] == type_id:
				pool.append(c)
		if not pool.is_empty():
			inc.call = pool[rng.randi() % pool.size()]
			inc.shown_type = inc.call.report
	if type_id == "prank" and inc.call.is_empty():
		inc.true_type = "dispute"
		inc.shown_type = "dispute"
	inc.state = Incident.S.CALL if not inc.call.is_empty() else Incident.S.WAITING
	incidents.append(inc)
	inc.build_marker(_markers)
	ops.note_incident(spot.pos, float(lvl))
	if Data.INCIDENTS[type_id].get("flee", false):
		ops.spawn_suspect(inc)
	GameState.stats.total += 1
	if inc.state == Incident.S.CALL:
		GameState.post("110 接警台", "新来电：%s附近群众报警，等待接警研判。" % inc.desc(), "call")
		call_incoming.emit(inc)
	else:
		GameState.post("110 接警台", "%s，%s。需要：%s。" % [inc.desc(), inc.title(), Data.req_text(inc.req())], "lv%d" % inc.level())
	incident_added.emit(inc)
	_focus_new(inc)
	return inc


## 新警情：玩家手上没有待处理对象时自动选中，让右侧面板直接给出派警名单
func _focus_new(inc: Incident) -> void:
	if hud == null or hud.call_panel.visible or answering != null:
		return
	# 玩家正在看警力列表、统计或招募面板时不抢焦点，新警情仍会出现在左侧警情栏
	if hud.is_browsing():
		return
	if inc.state == Incident.S.CALL:
		return
	var busy: bool = selected is Incident and selected.is_active() and selected.state in [Incident.S.CALL, Incident.S.WAITING]
	if busy:
		return
	select(inc)
	var p := cam.cam.unproject_position(inc.spot.pos)
	if not get_viewport().get_visible_rect().grow(-160).has_point(p):
		cam.focus_on(inc.spot.pos)


func _tick_incident(inc: Incident, dm: float) -> void:
	match inc.state:
		Incident.S.CALL:
			if answering != inc:
				inc.call_wait += dm
				if inc.call_wait >= 10.0:
					inc.state = Incident.S.WAITING
					GameState.post("值班民警", "来电已按「%s」受理并转派。" % inc.title(), "info")
					inc.refresh_marker()
					incident_updated.emit(inc)
		Incident.S.WAITING, Incident.S.DISPATCHED:
			inc.deadline -= dm
			if inc.deadline <= 0.0:
				_escalate(inc)
		Incident.S.ONSCENE:
			var td := inc.true_data()
			if not inc.revealed:
				_reveal(inc)
			var miss: Dictionary = inc.missing(true, true)
			if inc.true_type == "prank":
				inc.progress += dm / 3.0
			elif miss.is_empty():
				var rate := 0.0
				var r := inc.req(true)
				for u in inc.on_scene_units():
					if r.has(u.skill()):
						rate += (1.0 - u.fatigue * 0.004) * (1.0 + (u.level - 1) * Data.LEVEL_BONUS)
				rate /= float(Data.req_count(r))
				inc.progress += minf(rate, 1.5) / float(td.dur) * dm
			else:
				if not inc.stalled:
					var names := []
					for k in miss.keys():
						names.append("%s（%s）" % [Data.SKILLS[k].name, Data.UNIT_TYPES[Data.SKILLS[k].unit].short])
					GameState.post(inc.on_scene_units()[0].callsign, "现场已控制，但处置需要%s警力，请求支援！" % "、".join(names), "lv3")
					_tut_once("stall", "派去的警种不对口，只能维持现场、拖慢恶化。看面板上红色的专长，派对应的警种过去。")
				# 维持现场：恶化速度降为 35%
				inc.deadline -= dm * 0.35
				if inc.deadline <= 0.0:
					_escalate(inc)
			inc.stalled = not miss.is_empty() and inc.true_type != "prank"
			if inc.progress >= 1.0:
				_resolve(inc)


func _reveal(inc: Incident) -> void:
	inc.revealed = true
	if inc.true_type == inc.shown_type:
		return
	var first: PoliceUnit = inc.on_scene_units()[0]
	if inc.true_type == "prank":
		GameState.post(first.callsign, "现场核实，未发现警情，系恶作剧报警。", "info")
	else:
		var old := inc.title()
		inc.shown_type = inc.true_type
		GameState.post(first.callsign, "现场核实：并非%s，实为%s！" % [old, inc.title()], "lv%d" % inc.level())
	inc.refresh_marker()
	incident_updated.emit(inc)


func _escalate(inc: Incident) -> void:
	var esc: String = inc.true_data().esc
	if esc == "":
		_fail(inc, "超时未能处置")
		return
	var lvl_before := inc.level()
	inc.true_type = esc
	inc.shown_type = esc
	inc.deadline = float(Data.INCIDENTS[esc].deadline)
	inc.escalations += 1
	if Data.INCIDENTS[esc].get("flee", false):
		ops.spawn_suspect(inc)
	GameState.adjust(-1.5 * lvl_before, -1.2)
	GameState.post("指挥中心", "注意！%s警情升级为「%s」！" % [inc.desc(), inc.title()], "lv%d" % inc.level())
	cam.shake(0.6)
	inc.refresh_marker()
	incident_updated.emit(inc)
	_tut_once("escalate", "警情升级了！到场越慢，事态越容易恶化。可以手动增派警力，或者招募更多单位。")


func _resolve(inc: Incident) -> void:
	inc.state = Incident.S.DONE
	var lvl := int(inc.true_data().level)
	var resp := inc.arrival - inc.created if inc.arrival >= 0 else 99.0
	var target: float = [0.0, 16.0, 12.0, 10.0, 10.0][clampi(lvl, 1, 4)]
	var perfect: bool = resp <= target and inc.escalations == 0
	if inc.true_type == "prank":
		GameState.post("指挥中心", "恶作剧警情已登记备案，%s恢复勤务。" % inc.units[0].callsign, "info")
	else:
		var reward := 2500.0 * lvl * (1.3 if perfect else 1.0)
		GameState.earn(reward)
		GameState.adjust(0.35 * lvl * (1.3 if perfect else 0.8), 0.3 * lvl * (1.4 if perfect else 0.6))
		GameState.stats.resolved += 1
		if perfect:
			GameState.stats.perfect += 1
		var who: String = inc.units[0].callsign if not inc.units.is_empty() else "现场"
		GameState.post(who, "%s处置完毕，%s。" % [inc.title(), "处置圆满" if perfect else "已妥善处置"], "good")
	for u in inc.units.duplicate():
		u.gain_xp(10.0 * lvl)
		u.release(true)
	inc.units.clear()
	_finish(inc)


func _fail(inc: Incident, why: String) -> void:
	inc.state = Incident.S.FAILED
	var lvl := int(inc.true_data().level)
	GameState.adjust(-3.0 * lvl, -2.5 * lvl)
	GameState.stats.failed += 1
	GameState.post("指挥中心", "%s：%s，%s。群众安全感下降。" % [inc.desc(), inc.title(), why], "lv4")
	for u in inc.units.duplicate():
		u.release(true)
	inc.units.clear()
	_finish(inc)


func _finish(inc: Incident) -> void:
	inc.refresh_marker()
	incident_updated.emit(inc)
	if inc.marker:
		inc.marker.visible = false
	_finished.append([inc, _time + 5.0])


# ------------------------------------------------------------------ 接警
func begin_call(inc: Incident) -> void:
	if inc.state != Incident.S.CALL:
		return
	answering = inc
	GameState.slowmo = 0.2


func ask(inc: Incident, idx: int) -> String:
	if idx in inc.asked:
		return ""
	inc.asked.append(idx)
	if "{road}" in str(inc.call.questions[idx].a):
		ops.tip_off(inc)
	return answer_text(inc, idx)


func answer_text(inc: Incident, idx: int) -> String:
	var a: String = inc.call.questions[idx].a
	return a.replace("{loc}", inc.desc()).replace("{road}", city.graph.edges[inc.spot.edge].name)


func classify(inc: Incident, type_id: String) -> void:
	answering = null
	GameState.slowmo = 1.0
	if not inc.is_active():
		return
	GameState.stats.calls_total += 1
	inc.classified = true
	var correct := type_id == inc.true_type
	if correct:
		GameState.stats.calls_ok += 1
		GameState.adjust(0.4, 0.8)
	if type_id == "prank":
		if inc.true_type == "prank":
			GameState.post("110 接警台", "识别为恶作剧报警，已登记并通报属地派出所进行教育。", "good")
			inc.state = Incident.S.DONE
			GameState.adjust(0.2, 0.6)
			_finish(inc)
		else:
			GameState.post("110 接警台", "来电被定性为恶作剧……", "info")
			inc.state = Incident.S.WAITING
			inc.shown_type = inc.call.report
			_fail(inc, "群众再次报警，漏警")
			GameState.adjust(-4.0, -6.0)
		return
	inc.shown_type = type_id
	inc.state = Incident.S.WAITING
	GameState.post("110 接警台", "%s，研判为「%s」，%s级警情，立即派警。" % [inc.desc(), inc.title(), Data.level_name(inc.level())], "lv%d" % inc.level())
	inc.refresh_marker()
	incident_updated.emit(inc)


func cancel_call() -> void:
	answering = null
	GameState.slowmo = 1.0


# ------------------------------------------------------------------ 派警
func _auto_dispatch() -> void:
	if not GameState.auto_dispatch and not DevTools.args.has("bot"):
		return
	# 派警原则：就近、警种匹配、自动。按缺口专长派到场最快的对口警力，
	# 等级高的警情优先；没有对口警力时不乱派，留给指挥长决断。来电需先研判定性。
	var list := incidents.filter(func(i): return i.state in [Incident.S.WAITING, Incident.S.DISPATCHED, Incident.S.ONSCENE])
	list.sort_custom(func(a, b): return a.level() > b.level())
	for inc in list:
		var miss: Dictionary = inc.missing()
		for k in miss.keys():
			var u := best_unit(inc, "" if k == "any" else k)
			if u:
				assign(u, inc, false)
				break


func best_unit(inc: Incident, skill := "") -> PoliceUnit:
	var best: PoliceUnit = null
	var best_score := INF
	for u in units:
		if not u.is_available() or u.incident != null:
			continue
		if skill != "" and u.skill() != skill:
			continue
		var score: float = u.eta_to(inc.spot.road_center, inc.spot.edge) + u.fatigue * 0.04
		if score < best_score:
			best_score = score
			best = u
	return best


## 派警名单：对口专长优先，再按到场时间；返回 [{unit, eta, fit}]
func candidates(inc: Incident, limit := 6) -> Array:
	var miss: Dictionary = inc.missing()
	var out := []
	for u in units:
		if not u.is_available() or u.incident == inc:
			continue
		var fit := miss.has(u.skill()) or miss.has("any")
		out.append({"unit": u, "eta": u.eta_to(inc.spot.road_center, inc.spot.edge), "fit": fit})
	out.sort_custom(func(a, b):
		if a.fit != b.fit:
			return a.fit
		return a.eta < b.eta)
	return out.slice(0, limit)


func assign(u: PoliceUnit, inc: Incident, manual: bool) -> void:
	if u.incident == inc:
		return
	if u.incident != null:
		u.incident.unassign(u)
	inc.units.append(u)
	u.dispatch_to(inc)
	if inc.state == Incident.S.WAITING:
		inc.state = Incident.S.DISPATCHED
	var eta: float = maxf(u.eta_min, 0.5)
	GameState.post("指挥中心", "%s，%s发生%s，请立即前往处置。" % [u.callsign, inc.desc(), inc.title()], "cmd")
	GameState.post(u.callsign, "收到，预计 %d 分钟到达。" % ceili(eta), "unit")
	if manual:
		_tut_once("manual", "手动派警成功。系统会继续按就近、对口的原则为其他警情自动补派。")
	inc.refresh_marker()
	incident_updated.emit(inc)
	units_changed.emit()


func _on_unit_arrived(u: PoliceUnit) -> void:
	if u.state != PoliceUnit.State.ENROUTE or u.incident == null:
		return
	var inc := u.incident
	u.state = PoliceUnit.State.ONSCENE
	if inc.arrival < 0.0:
		inc.arrival = GameState.minutes
		var resp := inc.arrival - inc.created
		GameState.stats.resp_sum += resp
		GameState.stats.resp_n += 1
	inc.state = Incident.S.ONSCENE
	GameState.post(u.callsign, "已到达现场，开始处置。", "unit")
	inc.refresh_marker()
	incident_updated.emit(inc)


func recall(u: PoliceUnit) -> void:
	if u.incident:
		u.incident.unassign(u)
	u.clear_zone()
	u.return_to_base()
	GameState.post(u.callsign, "收到，返回驻地。", "unit")
	units_changed.emit()


func patrol(u: PoliceUnit) -> void:
	if u.incident:
		u.incident.unassign(u)
	u.patrol_center = u.facility.center
	u.patrol_radius = u.info.patrol_radius
	u.zone_set = false
	u.start_patrol()
	GameState.post(u.callsign, "收到，恢复辖区巡逻。", "unit")
	units_changed.emit()


# ------------------------------------------------------------------ 选择与指令
func select(obj) -> void:
	selected = obj
	selection_changed.emit(obj)
	if obj is PoliceUnit and phase == "shift":
		_tut_once("select_unit", "选中单位后：右键点警情可派警；右键点路面可改巡区。")


func pick(screen: Vector2) -> Variant:
	var best = null
	var best_d := 26.0
	for inc in incidents:
		if not inc.is_active():
			continue
		var p := cam.cam.unproject_position(inc.spot.pos)
		var d := p.distance_to(screen)
		if d < best_d:
			best_d = d
			best = inc
	for sp in ops.suspects:
		if sp.state != Suspect.S.FLEE:
			continue
		var p := cam.cam.unproject_position(sp.pos if sp.seen else sp.last_seen)
		var d := minf(p.distance_to(screen), (p + Vector2(0, -24)).distance_to(screen))
		if d < best_d:
			best_d = d
			best = sp
	var unit_best = null
	var ubd := 22.0
	for u in units:
		var p := cam.cam.unproject_position(u.global_position)
		var d := minf(p.distance_to(screen), (p + Vector2(0, -28)).distance_to(screen))
		if d < ubd:
			ubd = d
			unit_best = u
	if unit_best != null and (best == null or ubd < best_d * 0.8):
		return unit_best
	if best != null:
		return best
	for f in city.facilities:
		var p := cam.cam.unproject_position(f.center)
		if (p + Vector2(0, -30)).distance_to(screen) < 22.0 or p.distance_to(screen) < 12.0:
			return f
	return null


func _on_click(pos: Vector2) -> void:
	if ops.placing:
		if ops.place_checkpoint(cam.ground_point(pos)):
			_tut_once("checkpoint", "卡点设好了。嫌疑人从卡点经过就会被当场拦截，提前卡住逃跑方向的主干道最有效。")
		ops.placing = false
		hud.update_dock()
		return
	select(pick(pos))


## 巡区半径（米）：社区警务车守片，巡逻车与铁骑覆盖更大
const ZONE_RADIUS := {"community": 110.0, "patrol": 150.0, "traffic": 190.0}


func _on_right_click(pos: Vector2) -> void:
	if ops.placing:
		ops.placing = false
		hud.update_dock()
		return
	if not (selected is PoliceUnit):
		return
	var u: PoliceUnit = selected
	var target = pick(pos)
	if target is Incident:
		assign(u, target, true)
	elif target is Suspect:
		ops.order_chase(u, target)
	else:
		var g := cam.ground_point(pos)
		if u.info.patrol:
			u.set_zone(g, ZONE_RADIUS.get(u.kind, 150.0), phase == "shift")
			var near := city.graph.nearest_edge_point(g)
			GameState.post(u.callsign, "收到，转入%s巡区，守点巡逻。" % city.graph.describe(near.edge, near.t), "unit")
			if phase == "shift":
				_tut_once("zone", "巡区设好了。这组警力会在这片巡逻，处警后也会回到这里。")
		elif phase == "setup":
			GameState.advisor.emit("特警不上街巡逻，在支队待命，接到持械、劫持警情再出动。")
			return
		else:
			u.move_to(g)
			GameState.post(u.callsign, "收到，前往指定区域布控。", "unit")
		units_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _started:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if answering == null:
					for inc in incidents:
						if inc.state == Incident.S.CALL:
							hud.open_call(inc)
							break
			KEY_P, KEY_PAUSE:
				GameState.toggle_pause()
			KEY_1:
				GameState.set_speed(1.0)
			KEY_2:
				GameState.set_speed(2.0)
			KEY_3:
				GameState.set_speed(4.0)
			KEY_R:
				hud.toggle_recruit()
			KEY_L:
				hud.toggle_log()
			KEY_C:
				hud.toggle_checkpoint()
			KEY_H:
				hud.toggle_layer("heat")
			KEY_ESCAPE:
				if ops.placing:
					ops.placing = false
					hud.update_dock()
					return
				if hud.close_overlays():
					return
				select(null)
			KEY_F:
				if selected is PoliceUnit:
					cam.focus_on(selected.global_position, 220)
				elif selected is Incident:
					cam.focus_on(selected.spot.pos, 220)
				elif selected is Suspect:
					cam.focus_on(selected.last_seen, 260)


# ------------------------------------------------------------------ 教学（值班长对讲）
func _tut_once(key: String, text: String) -> void:
	if _tut.has(key):
		return
	_tut[key] = true
	GameState.advisor.emit(text)


func _tutorial_tick(delta: float) -> void:
	_advisor_t += delta
	for inc in incidents:
		if inc.state == Incident.S.WAITING:
			_tut_once("first_inc", "来警情了！系统已按就近、对口自动派警。右侧面板能看到专长是否到位，想增派或改派，点名单里的警力即可。")
			break
	for inc in incidents:
		if inc.state == Incident.S.CALL:
			_tut_once("first_call", "接警台有来电！按空格或点来电卡片接听。多问一句，少跑一趟。")
			break
	for sp in ops.suspects:
		if sp.state == Suspect.S.FLEE:
			_tut_once("suspect", "抢劫嫌疑人正在逃窜！红色标记是天网最后比中的位置。选中巡逻车右键嫌疑人可以追缉，按 C 在他逃跑方向的路上设卡拦截。")
			break
	if _advisor_t > 150.0:
		_tut_once("recruit", "经费宽裕的话，按 R 打开警力部署，招募新的编组。")
	if GameState.safety < 50.0:
		_tut_once("low_safety", "群众安全感在下滑，警力快顶不住了。赶紧按 R 增派编组，别让经费躺在账上。")
	if GameState.safety < 40.0 and not _tut.has("warn40"):
		_tut["warn40"] = true
		GameState.post("市局", "考核预警：群众安全感低于 40，请分局立即采取措施！", "lv4")
	if GameState.safety > 55.0:
		_tut.erase("warn40")
