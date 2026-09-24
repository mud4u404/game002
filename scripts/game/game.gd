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
const INITIAL_UNITS := {
	"station": {"community": 2},
	"patrol_hq": {"patrol": 4},
	"traffic_hq": {"traffic": 3},
	"swat_hq": {"swat": 1},
}

var city: CityBuilder
var env: EnvironmentRig
var traffic: Traffic
var cam: RTSCamera
var hud: HUD
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


func _ready() -> void:
	GameState.reset()
	rng.seed = SEED + 1
	city = CityBuilder.new()
	add_child(city)
	city.build(SEED)
	env = EnvironmentRig.new()
	add_child(env)
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(city.graph, 220, SEED)
	_markers = Node3D.new()
	add_child(_markers)
	cam = RTSCamera.new()
	add_child(cam)
	var inner0 := city.graph.positions[city.graph.node_id(CityBuilder.INNER_MIN, CityBuilder.INNER_MIN)]
	var inner1 := city.graph.positions[city.graph.node_id(CityBuilder.INNER_MAX, CityBuilder.INNER_MAX)]
	cam.bounds = Rect2(inner0.x - 60, inner0.z - 60, inner1.x - inner0.x + 120, inner1.z - inner0.z + 120)
	cam.set_view(Vector3((inner0.x + inner1.x) * 0.5, 0, (inner0.z + inner1.z) * 0.5 - 30), 620, 0)
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
	GameState.post("指挥中心", "夜班交接完毕，江城市公安局滨江分局指挥中心开始值守。", "sys")
	_dev_hooks()


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
	if a.has("test-recruit"):
		await get_tree().create_timer(0.5).timeout
		hud.toggle_recruit()
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
	if u.info.patrol:
		u.start_patrol()
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
			GameState.spend(d.cost)
			GameState.staff_used = _staff_count()
			GameState.post(f.name, "新编组 %s（%s）完成组建，已纳入指挥序列。" % [u.callsign, d.name], "good")
			GameState.stats_changed.emit()
			return u
	return null


# ------------------------------------------------------------------ 主循环
func _process(delta: float) -> void:
	_time += delta
	var dt := GameState.scaled_delta(delta)
	var dm := GameState.advance(delta)
	env.apply(GameState.time_of_day())

	for u in units:
		if u.tick(dt, dm):
			_on_unit_arrived(u)

	for inc in incidents.duplicate():
		_tick_incident(inc, dm)

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
	var rate := 0.19 * Data.hour_intensity(GameState.hour()) * (1.0 + (GameState.day() - 1) * 0.12)
	if active < 16 and rng.randf() < rate * dm:
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
		GameState.safety = clampf(GameState.safety + ((64.0 - GameState.safety) * 0.006 - load * 0.006) * dm, 0.0, 100.0)
		GameState.opinion = clampf(GameState.opinion + (62.0 - GameState.opinion) * 0.003 * dm, 0.0, 100.0)

	_tutorial_tick(delta)


# ------------------------------------------------------------------ 警情
func spawn_incident(force_type := "") -> Incident:
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
		spot = city.random_incident_spot(rng)
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
	var wants_call := lvl >= 3 or type_id == "prank" or (lvl == 2 and rng.randf() < 0.35)
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
	GameState.stats.total += 1
	if inc.state == Incident.S.CALL:
		GameState.post("110 接警台", "新来电：%s附近群众报警，等待接警研判。" % inc.desc(), "call")
		call_incoming.emit(inc)
	else:
		GameState.post("110 接警台", "%s，%s。" % [inc.desc(), inc.title()], "lv%d" % inc.level())
	incident_added.emit(inc)
	return inc


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
			if inc.true_type == "prank":
				inc.progress += dm / 3.0
			else:
				var ok := inc.max_force(true) >= int(td.force)
				if ok:
					var rate := 0.0
					for u in inc.on_scene_units():
						var m: float = td.match.get(u.kind, 0.5)
						rate += m * (1.0 - u.fatigue * 0.004) * (1.0 + (u.level - 1) * 0.05)
					inc.progress += rate / float(td.dur) * dm
				else:
					if not inc.stalled:
						GameState.post(inc.on_scene_units()[0].callsign, "现场武力不足，无法控制局面，请求增援！", "lv3")
						_tut_once("stall", "现场武力不足，处置停滞了。需要武力等级更高的警种支援，比如特警。")
					inc.deadline -= dm * 0.6
					if inc.deadline <= 0.0:
						_escalate(inc)
				inc.stalled = not ok
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
	if not GameState.auto_dispatch:
		return
	var list := incidents.filter(func(i): return i.state in [Incident.S.WAITING, Incident.S.DISPATCHED, Incident.S.ONSCENE])
	list.sort_custom(func(a, b): return a.level() > b.level())
	for inc in list:
		var d: Dictionary = inc.data()
		var need := int(d.need)
		var force := int(d.force) if inc.true_type != "prank" else 0
		if inc.revealed:
			force = int(inc.true_data().force)
		var have: int = inc.units.size()
		var fh: int = inc.max_force()
		if have >= need and fh >= force:
			continue
		if have >= need + 2:
			continue
		var want := force if fh < force else 0
		var u := best_unit(inc, want)
		if u == null and have < need:
			u = best_unit(inc, 0)
		if u:
			assign(u, inc, false)


func best_unit(inc: Incident, min_force: int) -> PoliceUnit:
	var best: PoliceUnit = null
	var best_score := INF
	var d := inc.data()
	for u in units:
		if not u.is_available() or u.incident != null:
			continue
		var m: float = d.match.get(u.kind, 0.0)
		if m <= 0.0:
			continue
		if min_force > 0 and u.force() < min_force:
			continue
		var eta: float = u.eta_to(inc.spot.road_center, inc.spot.edge)
		var score: float = eta / sqrt(m) + u.fatigue * 0.04
		if u.kind == "swat" and int(d.force) < 3:
			score += 30.0
		if score < best_score:
			best_score = score
			best = u
	return best


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
		_tut_once("manual", "手动调度成功。系统会继续为其他警情自动补派警力。")
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
	u.return_to_base()
	GameState.post(u.callsign, "收到，返回驻地。", "unit")
	units_changed.emit()


func patrol(u: PoliceUnit) -> void:
	if u.incident:
		u.incident.unassign(u)
	u.start_patrol()
	GameState.post(u.callsign, "收到，恢复街面巡逻。", "unit")
	units_changed.emit()


# ------------------------------------------------------------------ 选择与指令
func select(obj) -> void:
	selected = obj
	selection_changed.emit(obj)
	if obj is PoliceUnit:
		_tut_once("select_unit", "选中单位后：右键点警情可手动派警，右键点路面可机动部署。")


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
	var unit_best = null
	var ubd := 18.0
	for u in units:
		var p := cam.cam.unproject_position(u.global_position)
		var d := p.distance_to(screen)
		if d < ubd:
			ubd = d
			unit_best = u
	if unit_best != null and (best == null or ubd < best_d * 0.8):
		return unit_best
	if best != null:
		return best
	for f in city.facilities:
		var p := cam.cam.unproject_position(f.center)
		if p.distance_to(screen) < 34.0:
			return f
	return null


func _on_click(pos: Vector2) -> void:
	select(pick(pos))


func _on_right_click(pos: Vector2) -> void:
	if not (selected is PoliceUnit):
		return
	var u: PoliceUnit = selected
	var target = pick(pos)
	if target is Incident:
		assign(u, target, true)
	else:
		var g := cam.ground_point(pos)
		u.move_to(g)
		GameState.post(u.callsign, "收到，前往指定区域布控。", "unit")
		units_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
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
			KEY_ESCAPE:
				if hud.close_overlays():
					return
				select(null)
			KEY_F:
				if selected is PoliceUnit:
					cam.focus_on(selected.global_position, 220)
				elif selected is Incident:
					cam.focus_on(selected.spot.pos, 220)


# ------------------------------------------------------------------ 教学（值班长对讲）
func _tut_once(key: String, text: String) -> void:
	if _tut.has(key):
		return
	_tut[key] = true
	GameState.advisor.emit(text)


func _tutorial_tick(delta: float) -> void:
	_advisor_t += delta
	if _advisor_t > 1.5:
		_tut_once("hello", "指挥长，晚上好，我是值班长老周。今晚滨江分局由你坐镇，大屏已经就绪。")
	if _advisor_t > 9.0:
		_tut_once("auto", "系统默认开启自动派警，一般警情会自己运转。重大警情会进接警台，得你亲自研判。")
	if _advisor_t > 18.0 and not incidents.is_empty():
		_tut_once("first_inc", "来警情了。左边是警情队列，地图上的光圈就是位置，点一下能看详情。")
	for inc in incidents:
		if inc.state == Incident.S.CALL:
			_tut_once("first_call", "接警台有来电！按空格或点来电卡片接听。多问一句，少跑一趟。")
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
