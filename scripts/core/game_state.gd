extends Node
## 全局运行状态：时间、资源、考核指标、电台消息总线。

signal stats_changed
signal speed_changed(speed: float)
signal radio(entry: Dictionary)          # {time, from, text, kind}
signal advisor(text: String)              # 值班长对讲提示
signal day_report(report: Dictionary)

const START_MINUTES := 17.0 * 60.0 + 10.0

var money := 600_000.0
var safety := 70.0          # 群众安全感 0..100
var opinion := 72.0         # 舆情 0..100（越高越好）
var staff_cap := 40         # 民警编制
var staff_used := 0
var minutes := START_MINUTES  # 自第 1 天 00:00 起的游戏分钟
var speed := 1.0
var paused := false
var slowmo := 1.0           # 接警时的时间减速
var auto_dispatch := true    # 就近、警种匹配、自动派警

var stats := {"total": 0, "resolved": 0, "failed": 0, "perfect": 0,
	"resp_sum": 0.0, "resp_n": 0, "calls_ok": 0, "calls_total": 0}
var _last_day := 1


func reset() -> void:
	money = 600_000.0
	safety = 70.0
	opinion = 72.0
	staff_used = 0
	minutes = START_MINUTES
	speed = 1.0
	paused = false
	slowmo = 1.0
	auto_dispatch = true
	for k in stats.keys():
		stats[k] = 0
	_last_day = 1


## 本帧游戏推进的"现实秒"（已考虑倍速、暂停和减速）
func scaled_delta(delta: float) -> float:
	if paused:
		return 0.0
	return delta * speed * slowmo


func advance(delta: float) -> float:
	var sd := scaled_delta(delta)
	var dm := sd * Data.MIN_PER_SEC
	minutes += dm
	var d := day()
	if d != _last_day:
		_last_day = d
		_new_day()
	return dm


func day() -> int:
	return int(minutes / 1440.0) + 1


func hour() -> int:
	return int(fmod(minutes, 1440.0) / 60.0)


func clock_str() -> String:
	var m := int(fmod(minutes, 1440.0))
	return "%02d:%02d" % [m / 60, m % 60]


func time_of_day() -> float:
	return fmod(minutes, 1440.0) / 60.0


func set_speed(s: float) -> void:
	if s <= 0.0:
		paused = true
	else:
		paused = false
		speed = s
	speed_changed.emit(0.0 if paused else speed)


func toggle_pause() -> void:
	paused = not paused
	speed_changed.emit(0.0 if paused else speed)


func spend(amount: float) -> bool:
	if money < amount:
		return false
	money -= amount
	stats_changed.emit()
	return true


func earn(amount: float) -> void:
	money += amount
	stats_changed.emit()


func adjust(d_safety: float, d_opinion: float) -> void:
	safety = clampf(safety + d_safety, 0.0, 100.0)
	opinion = clampf(opinion + d_opinion, 0.0, 100.0)
	stats_changed.emit()


func post(from: String, text: String, kind := "info") -> void:
	radio.emit({"time": clock_str(), "from": from, "text": text, "kind": kind})


func avg_response() -> float:
	if stats.resp_n == 0:
		return 0.0
	return stats.resp_sum / stats.resp_n


func _new_day() -> void:
	var grant := 160_000.0 + (safety - 60.0) * 3000.0
	grant = maxf(grant, 60_000.0)
	money += grant
	var report := {"day": day() - 1, "grant": grant, "safety": safety, "opinion": opinion,
		"resolved": stats.resolved, "failed": stats.failed, "avg": avg_response()}
	post("市局", "日终结算：财政拨付经费 %s。" % Data.money_str(grant), "good")
	day_report.emit(report)
	stats_changed.emit()
