class_name DayReportPanel
extends Control
## 每日 00:00 弹出的值班日报（结算面板）。
## - 监听 GameState.day_report：暂停游戏并居中弹出
## - "继续值班"按钮恢复原速度并关闭
## - 当日数字 = 当前统计 - 上一次日报的快照

const W := 480.0
# 评价阈值（参考 Issue #1 验收标准）
const EVAL_FAILED_BAD := 3           # 失败 ≥ 此值即触发"约谈"
const EVAL_SAFETY_OK := 65.0         # 安全感 ≥ 此值且无失败 = "平安夜"
const EVAL_SAFETY_BAD := 45.0        # 安全感 < 此值即触发"约谈"

var _panel: TechPanel
var _tiles: Dictionary = {}
var _verdict: Label
var _snapshot: Dictionary = {}
var _was_paused := false
var _prev_speed := 1.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# 半透明遮罩
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_click)
	add_child(dim)
	_panel = TechPanel.new("值班日报", "bar_chart", UIKit.ACCENT, false)
	_panel.custom_minimum_size = Vector2(W, 0)
	add_child(_panel)
	var b := _panel.body
	b.add_theme_constant_override("separation", 12)
	_build_tiles(b)
	_verdict = UIKit.label("", 15, UIKit.TEXT, "bold")
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(_verdict)
	var btn := UIKit.accent_button("继续值班", UIKit.ACCENT, 15)
	btn.custom_minimum_size.y = 44
	btn.pressed.connect(close)
	b.add_child(btn)
	GameState.day_report.connect(_on_day_report)
	_snapshot = _snapshot_current()


func _on_dim_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		close()


func _build_tiles(parent: VBoxContainer) -> void:
	var rows: Array = [
		[["notifications", "当日接警", "total"], ["check_circle", "已结案", "resolved"], ["cancel", "处置失败", "failed"]],
		[["timer", "平均到场", "avg"], ["front_hand", "抓获 / 逃脱", "caught"], ["payments", "经费拨付", "grant"]],
		[["health_and_safety", "群众安全感", "safety"], ["campaign", "舆情", "opinion"], ["sentiment_satisfied", "圆满处置", "perfect"]],
	]
	for row in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		parent.add_child(h)
		for it in row:
			_tile(h, it[0], it[1], it[2])


func _tile(parent: HBoxContainer, icon_name: String, tip: String, key: String) -> void:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.18, 0.4, 0.5)
	sb.border_color = Color(0.3, 0.6, 1.0, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.tooltip_text = tip
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UIKit.icon_label(icon_name, 16, UIKit.TEXT_MUTED))
	var val := UIKit.label("—", 17, UIKit.TEXT, "bold")
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(val)
	_tiles[key] = val
	pc.add_child(v)
	parent.add_child(pc)


func _snapshot_current() -> Dictionary:
	return {
		"total": int(GameState.stats.get("total", 0)),
		"resolved": int(GameState.stats.get("resolved", 0)),
		"failed": int(GameState.stats.get("failed", 0)),
		"perfect": int(GameState.stats.get("perfect", 0)),
		"resp_sum": float(GameState.stats.get("resp_sum", 0.0)),
		"resp_n": int(GameState.stats.get("resp_n", 0)),
		"calls_ok": int(GameState.stats.get("calls_ok", 0)),
		"calls_total": int(GameState.stats.get("calls_total", 0)),
		"caught": int(GameState.stats.get("caught", 0)),
		"escaped": int(GameState.stats.get("escaped", 0)),
	}


func _set_tile(key: String, text: String, col := Color(-1, 0, 0)) -> void:
	if not _tiles.has(key):
		return
	var l: Label = _tiles[key]
	l.text = text
	if col.r >= 0.0:
		l.add_theme_color_override("font_color", col)


func _metric_color(v: float) -> Color:
	if v >= 55.0:
		return UIKit.TEXT
	if v >= 40.0:
		return UIKit.AMBER
	return UIKit.RED


func _on_day_report(report: Dictionary) -> void:
	var cur: Dictionary = _snapshot_current()
	var total: int = int(cur.get("total", 0)) - int(_snapshot.get("total", 0))
	var resolved: int = int(cur.get("resolved", 0)) - int(_snapshot.get("resolved", 0))
	var failed: int = int(cur.get("failed", 0)) - int(_snapshot.get("failed", 0))
	var perfect: int = int(cur.get("perfect", 0)) - int(_snapshot.get("perfect", 0))
	var resp_sum: float = float(cur.get("resp_sum", 0.0)) - float(_snapshot.get("resp_sum", 0.0))
	var resp_n: int = int(cur.get("resp_n", 0)) - int(_snapshot.get("resp_n", 0))
	var caught: int = int(cur.get("caught", 0)) - int(_snapshot.get("caught", 0))
	var escaped: int = int(cur.get("escaped", 0)) - int(_snapshot.get("escaped", 0))
	_snapshot = cur
	# 模拟（headless + quit-frames）跳过 UI 与暂停
	if DevTools.args.has("quit-frames"):
		return
	var day: int = int(report.get("day", GameState.day() - 1))
	_panel.set_title("第 %d 天 · 值班日报" % day, "", "bar_chart")
	_set_tile("total", str(total))
	_set_tile("resolved", str(resolved), UIKit.GREEN)
	_set_tile("failed", str(failed), UIKit.RED if failed > 0 else UIKit.TEXT)
	_set_tile("avg", UIKit.fmt_min(resp_sum / float(maxi(resp_n, 1))) if resp_n > 0 else "—")
	_set_tile("caught", "%d/%d" % [caught, escaped], UIKit.GREEN if caught > 0 else UIKit.TEXT)
	_set_tile("grant", "+%s" % Data.money_str(float(report.get("grant", 0.0))), UIKit.GREEN)
	_set_tile("safety", "%.0f" % GameState.safety, _metric_color(GameState.safety))
	_set_tile("opinion", "%.0f" % GameState.opinion, _metric_color(GameState.opinion))
	_set_tile("perfect", str(perfect))
	var v_color: Color = UIKit.AMBER
	var v_text: String = "平稳"
	if failed == 0 and GameState.safety >= EVAL_SAFETY_OK:
		v_color = UIKit.GREEN
		v_text = "平安夜"
	elif failed >= EVAL_FAILED_BAD or GameState.safety < EVAL_SAFETY_BAD:
		v_color = UIKit.RED
		v_text = "市局约谈"
	_verdict.text = v_text
	_verdict.add_theme_color_override("font_color", v_color)
	# 暂停游戏
	_was_paused = GameState.paused
	_prev_speed = GameState.speed
	GameState.set_speed(0.0)
	visible = true
	await get_tree().process_frame
	_panel.reset_size()
	_panel.position = (get_viewport_rect().size - _panel.size) * 0.5


func close() -> void:
	if not visible:
		return
	visible = false
	if not _was_paused:
		GameState.set_speed(_prev_speed)


## 测试钩子：合成一日数据并触发一次日报，方便截图。
func show_for_test() -> void:
	GameState.stats.total = int(GameState.stats.get("total", 0)) + 7
	GameState.stats.resolved = int(GameState.stats.get("resolved", 0)) + 5
	GameState.stats.failed = int(GameState.stats.get("failed", 0)) + 1
	GameState.stats.perfect = int(GameState.stats.get("perfect", 0)) + 3
	GameState.stats.resp_sum = float(GameState.stats.get("resp_sum", 0.0)) + 22.5
	GameState.stats.resp_n = int(GameState.stats.get("resp_n", 0)) + 5
	GameState.stats.calls_ok = int(GameState.stats.get("calls_ok", 0)) + 4
	GameState.stats.calls_total = int(GameState.stats.get("calls_total", 0)) + 5
	GameState.stats.caught = int(GameState.stats.get("caught", 0)) + 1
	GameState.safety = 68.0
	GameState.opinion = 72.0
	var report: Dictionary = {"day": GameState.day(), "grant": 180000.0, "safety": GameState.safety, "opinion": GameState.opinion,
		"resolved": GameState.stats.resolved, "failed": GameState.stats.failed, "avg": GameState.avg_response()}
	_on_day_report(report)