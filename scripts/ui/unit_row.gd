class_name UnitRow
extends Control
## 警力列表行（自绘）

signal pressed(u: PoliceUnit)

var u: PoliceUnit
var game: Game
var _hover := false


func _init(p_u: PoliceUnit, p_game: Game) -> void:
	u = p_u
	game = p_game
	custom_minimum_size = Vector2(0, 36)
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
	var bg := Color(0.04, 0.08, 0.13, 0.75)
	if _hover or sel:
		bg = Color(0.07, 0.14, 0.22, 0.9)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	if sel:
		draw_rect(Rect2(0, 0, 3, size.y), UIKit.CYAN)
	var col: Color = u.state_color()
	var t := Time.get_ticks_msec() / 1000.0
	var led := col
	if u.state in [PoliceUnit.State.ENROUTE, PoliceUnit.State.ONSCENE]:
		led = UIKit.RED if fmod(t * 3.2, 1.0) < 0.5 else UIKit.BLUE
	draw_circle(Vector2(14, size.y * 0.5), 4.0, led)
	var fn := UIKit.font("num_bold")
	var fb := UIKit.font("bold")
	var fr := UIKit.font("reg")
	draw_string(fn, Vector2(26, 23), u.callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.TEXT)
	var st: String = u.state_name()
	if u.incident != null and u.state in [PoliceUnit.State.ENROUTE, PoliceUnit.State.ONSCENE]:
		st += " · " + u.incident.title()
	draw_string(fr, Vector2(104, 23), st, HORIZONTAL_ALIGNMENT_LEFT, size.x - 104 - 58, 13, col)
	# 疲劳
	var fw := 40.0
	var fx := size.x - fw - 10
	draw_rect(Rect2(fx, 16, fw, 4), Color(1, 1, 1, 0.08))
	var fc := UIKit.GREEN if u.fatigue < 50 else (UIKit.AMBER if u.fatigue < 80 else UIKit.RED)
	draw_rect(Rect2(fx, 16, fw * (1.0 - u.fatigue / 100.0), 4), fc)
	var _unused := fb
