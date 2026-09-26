class_name UnitRow
extends Control
## 警力列表行（参照《112》单位面板）：车辆卡片 + 呼号 + 车组人员 + 当前任务 + 状态。

signal pressed(u: PoliceUnit)

var u: PoliceUnit
var game: Game
var _hover := false


func _init(p_u: PoliceUnit, p_game: Game) -> void:
	u = p_u
	game = p_game
	custom_minimum_size = Vector2(0, 48)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): _hover = true)
	mouse_exited.connect(func(): _hover = false)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(u)
		accept_event()


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var sel: bool = UIKit.same(game.selected, u)
	var t := Time.get_ticks_msec() / 1000.0
	if _hover or sel:
		UIKit.draw_round_rect(self, Rect2(Vector2.ZERO, size), Color(0.2, 0.45, 0.95, 0.22 if sel else 0.12), 4, UIKit.CYAN if sel else Color(0, 0, 0, 0), 1 if sel else 0)
	var fill: Color = MarkerLayer.UNIT_FILL.get(u.kind, UIKit.ACCENT)
	var card := Rect2(6, 6, 56, 36)
	UIKit.draw_round_rect(self, card, fill, 4, Color(0.75, 0.9, 1.0, 0.8), 1)
	var inner := card.grow(-3)
	UIKit.draw_round_rect(self, inner, Color(0.78, 0.89, 1.0, 0.92), 2)
	var emergency := u.state == PoliceUnit.State.ENROUTE or u.state == PoliceUnit.State.ONSCENE
	VehicleArt.draw(self, u.kind, inner.grow(-1), Color("f4f8ff"), Color("15357a"), fmod(t * 3.2, 1.0) if emergency else -1.0)
	var fb := UIKit.font("bold")
	draw_string(fb, Vector2(72, 22), u.callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.TEXT)
	# 车组人员
	var n := int(u.info.staff) + (1 if u.kind == "community" else 0)
	for k in n:
		var pr := Rect2(72 + k * 16, 28, 13, 14)
		UIKit.draw_round_rect(self, pr, Color(0.12, 0.28, 0.6), 2)
		UIKit.draw_icon(self, "person", pr.get_center(), 12, Color(0.75, 0.88, 1.0))
	# 体力条
	var bx := 72.0 + n * 16 + 6
	var bw := 36.0
	UIKit.draw_round_rect(self, Rect2(bx, 34, bw, 3), Color(1, 1, 1, 0.1), 1)
	var fc := UIKit.GREEN if u.fatigue < 50 else (UIKit.AMBER if u.fatigue < 80 else UIKit.RED)
	UIKit.draw_round_rect(self, Rect2(bx, 34, bw * (1.0 - u.fatigue / 100.0), 3), fc, 1)
	# 当前任务：呼号下方、人员/体力条右侧，10px / TEXT_MUTED，超长截断
	var st: String = u.state_name() if not u.resting else "轮休"
	var sw := fb.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
	var task := _task_text()
	if task != "":
		var fr := UIKit.font("reg")
		var max_w: float = maxf(40.0, size.x - sw - 16.0 - (bx + bw + 8.0))
		var s := task
		if fr.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x > max_w:
			while s.length() > 1 and fr.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x > max_w:
				s = s.substr(0, s.length() - 1)
			s += "…"
		draw_string(fr, Vector2(bx + bw + 8, 41), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIKit.TEXT_MUTED)
	UIKit.draw_chip(self, st, Vector2(size.x - sw - 8, 14), u.state_color(), 11)


## 当前任务一行文案：警情 > 追缉 > 巡区 > 驻地
func _task_text() -> String:
	if u.incident != null:
		return u.incident.title()
	if u.chase_target != null:
		return "追缉嫌疑人"
	if u.zone_set:
		return "巡区"
	return "驻地待命"
