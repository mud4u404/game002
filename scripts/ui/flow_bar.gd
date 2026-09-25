class_name FlowBar
extends Control
## 警情流程条：接警 → 派警 → 到场 → 结案，当前步骤高亮，处置阶段显示进度。

var inc: Incident
const STEPS := [["phone_in_talk", "接警"], ["route", "派警"], ["my_location", "到场"], ["check_circle", "结案"]]


func _init(p_inc: Incident) -> void:
	inc = p_inc
	custom_minimum_size = Vector2(0, 62)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	queue_redraw()


func _step() -> int:
	match inc.state:
		Incident.S.CALL: return 0
		Incident.S.WAITING: return 1
		Incident.S.DISPATCHED: return 2
		Incident.S.ONSCENE: return 3
	return 4


func _draw() -> void:
	var cur := _step()
	var col := Data.level_color(inc.level())
	var n := STEPS.size()
	var x0 := 22.0
	var x1 := size.x - 22.0
	var y := 20.0
	var t := Time.get_ticks_msec() / 1000.0
	for k in n - 1:
		var a := Vector2(lerpf(x0, x1, float(k) / (n - 1)), y)
		var b := Vector2(lerpf(x0, x1, float(k + 1) / (n - 1)), y)
		draw_line(a, b, UIKit.LINE, 3.0)
		var fill := 0.0
		if k < cur - 1:
			fill = 1.0
		elif k == cur - 1:
			fill = inc.progress if inc.state == Incident.S.ONSCENE else 0.5 + 0.5 * sin(t * 3.0) * 0.0
			if inc.state != Incident.S.ONSCENE:
				fill = 1.0
		if fill > 0.0:
			draw_line(a, a.lerp(b, fill), col, 3.0)
	for k in n:
		var p := Vector2(lerpf(x0, x1, float(k) / (n - 1)), y)
		var done := k < cur
		var active := k == cur
		var c := col if done else (UIKit.BG3 if not active else UIKit.with_alpha(col, 0.25))
		if active:
			draw_circle(p, 17 + 2.0 * sin(t * 4.0), UIKit.with_alpha(col, 0.18))
		draw_circle(p, 14, c)
		if active:
			draw_arc(p, 14, 0, TAU, 32, col, 2.0, true)
		UIKit.draw_icon(self, STEPS[k][0], p, 16, Color.WHITE if done else (col if active else UIKit.TEXT_MUTED))
		UIKit.draw_text_c(self, STEPS[k][1], p + Vector2(0, 30), 11, UIKit.TEXT if done or active else UIKit.TEXT_MUTED, "reg")
