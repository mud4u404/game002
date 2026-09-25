class_name UnitRow
extends Control
## 警力列表行（自绘）：车型图标、呼号、任务、状态标签、疲劳条。

signal pressed(u: PoliceUnit)

var u: PoliceUnit
var game: Game
var _hover := false


func _init(p_u: PoliceUnit, p_game: Game) -> void:
	u = p_u
	game = p_game
	custom_minimum_size = Vector2(0, 46)
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
	var bg := UIKit.BG2 if not (_hover or sel) else UIKit.BG3
	UIKit.draw_round_rect(self, Rect2(Vector2.ZERO, size), bg, 8, UIKit.ACCENT if sel else Color(0, 0, 0, 0), 2 if sel else 0)
	var col: Color = u.state_color()
	var c := Vector2(24, size.y * 0.5)
	draw_circle(c, 15, UIKit.with_alpha(col, 0.18))
	UIKit.draw_icon(self, u.info.gi, c, 18, col)
	var fb := UIKit.font("bold")
	var fr := UIKit.font("reg")
	draw_string(fb, Vector2(48, 21), u.callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.TEXT)
	var task := u.info.short as String
	if u.incident != null:
		task = u.incident.title()
	elif u.resting:
		task = "轮休中"
	draw_string(fr, Vector2(48, 38), task, HORIZONTAL_ALIGNMENT_LEFT, size.x - 48 - 90, 12, UIKit.TEXT_DIM)
	var st: String = u.state_name()
	var fw := fb.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
	UIKit.draw_chip(self, st, Vector2(size.x - fw - 10, 7), col, 11)
	# 疲劳
	var bw := 44.0
	var br := Rect2(size.x - bw - 10, 33, bw, 3)
	UIKit.draw_round_rect(self, br, Color(1, 1, 1, 0.08), 2)
	var fc := UIKit.GREEN if u.fatigue < 50 else (UIKit.AMBER if u.fatigue < 80 else UIKit.RED)
	UIKit.draw_round_rect(self, Rect2(br.position, Vector2(bw * (1.0 - u.fatigue / 100.0), 3)), fc, 2)
