class_name MeterBar
extends Control
## 分段指示条

var value := 0.5
var color := UIKit.CYAN
var segments := 20


func _init(p_color := UIKit.CYAN, h := 6.0, segs := 20) -> void:
	color = p_color
	segments = segs
	custom_minimum_size = Vector2(60, h)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_value(v: float, c := Color(-1, 0, 0)) -> void:
	value = clampf(v, 0.0, 1.0)
	if c.r >= 0:
		color = c
	queue_redraw()


func _draw() -> void:
	var gap := 2.0
	var w := (size.x - gap * (segments - 1)) / segments
	var lit := value * segments
	for k in segments:
		var r := Rect2(k * (w + gap), 0, w, size.y)
		var a := 0.13
		if k < floor(lit):
			a = 1.0
		elif k < lit:
			a = 0.13 + 0.87 * (lit - k)
		draw_rect(r, UIKit.with_alpha(color, a))
