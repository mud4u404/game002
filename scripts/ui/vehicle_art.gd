class_name VehicleArt
extends RefCounted
## 侧视车辆剪影（矢量绘制），用于地图单位卡片和界面列表。车头朝右。


static func _p(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x * r.size.x, y * r.size.y)


static func _poly(r: Rect2, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(_p(r, q[0], q[1]))
	return out


static func draw(ci: CanvasItem, kind: String, r: Rect2, body := Color.WHITE, glass := Color("12306e"), siren := -1.0) -> void:
	var wheel := Color("0b1a3a")
	match kind:
		"traffic":
			# 摩托：两轮 + 车身 + 骑手
			ci.draw_circle(_p(r, 0.2, 0.74), r.size.y * 0.2, wheel)
			ci.draw_circle(_p(r, 0.8, 0.74), r.size.y * 0.2, wheel)
			ci.draw_circle(_p(r, 0.2, 0.74), r.size.y * 0.08, body)
			ci.draw_circle(_p(r, 0.8, 0.74), r.size.y * 0.08, body)
			ci.draw_colored_polygon(_poly(r, [[0.22, 0.62], [0.45, 0.45], [0.72, 0.42], [0.86, 0.6], [0.7, 0.66], [0.3, 0.7]]), body)
			ci.draw_colored_polygon(_poly(r, [[0.42, 0.44], [0.5, 0.18], [0.6, 0.18], [0.62, 0.44]]), body.darkened(0.15))
			ci.draw_circle(_p(r, 0.56, 0.12), r.size.y * 0.1, body)
			ci.draw_colored_polygon(_poly(r, [[0.72, 0.42], [0.8, 0.3], [0.84, 0.32], [0.78, 0.44]]), glass)
			_bar(ci, r, 0.3, 0.38, 0.36, siren)
		"swat":
			# 特警突击车：方正车厢
			ci.draw_colored_polygon(_poly(r, [[0.04, 0.2], [0.72, 0.2], [0.84, 0.36], [0.96, 0.42], [0.96, 0.76], [0.04, 0.76]]), body)
			ci.draw_colored_polygon(_poly(r, [[0.74, 0.25], [0.83, 0.38], [0.74, 0.38]]), glass)
			ci.draw_colored_polygon(_poly(r, [[0.5, 0.26], [0.68, 0.26], [0.68, 0.4], [0.5, 0.4]]), glass)
			ci.draw_rect(Rect2(_p(r, 0.08, 0.28), Vector2(r.size.x * 0.36, r.size.y * 0.08)), glass)
			ci.draw_rect(Rect2(_p(r, 0.04, 0.54), Vector2(r.size.x * 0.92, r.size.y * 0.08)), Color("2f7bff"))
			_wheels(ci, r, [0.22, 0.78], wheel, body)
			_bar(ci, r, 0.3, 0.52, 0.14, siren)
		_:
			# 轿车 / 警车
			ci.draw_colored_polygon(_poly(r, [[0.03, 0.5], [0.08, 0.42], [0.28, 0.38], [0.38, 0.2], [0.66, 0.2], [0.8, 0.38], [0.96, 0.44], [0.98, 0.64], [0.94, 0.74], [0.04, 0.74]]), body)
			ci.draw_colored_polygon(_poly(r, [[0.34, 0.37], [0.42, 0.25], [0.51, 0.25], [0.51, 0.37]]), glass)
			ci.draw_colored_polygon(_poly(r, [[0.54, 0.37], [0.54, 0.25], [0.64, 0.25], [0.74, 0.37]]), glass)
			ci.draw_rect(Rect2(_p(r, 0.04, 0.52), Vector2(r.size.x * 0.92, r.size.y * 0.07)), Color("2f7bff"))
			_wheels(ci, r, [0.24, 0.76], wheel, body)
			_bar(ci, r, 0.44, 0.58, 0.14, siren)


static func _wheels(ci: CanvasItem, r: Rect2, xs: Array, wheel: Color, hub: Color) -> void:
	for x in xs:
		var c := _p(r, x, 0.76)
		ci.draw_circle(c, r.size.y * 0.16, wheel)
		ci.draw_circle(c, r.size.y * 0.06, hub.darkened(0.2))


## 顶部警灯条：siren < 0 为熄灭，否则按相位红蓝交替
static func _bar(ci: CanvasItem, r: Rect2, x0: float, x1: float, y: float, siren: float) -> void:
	var a := _p(r, x0, y - 0.06)
	var w := (x1 - x0) * r.size.x
	var h := r.size.y * 0.07
	var on := siren >= 0.0
	var red := Color("ff2a3a") if (on and siren < 0.5) else Color("7a2030")
	var blue := Color("3a8bff") if (on and siren >= 0.5) else Color("1d3a7a")
	ci.draw_rect(Rect2(a, Vector2(w * 0.5, h)), red)
	ci.draw_rect(Rect2(a + Vector2(w * 0.5, 0), Vector2(w * 0.5, h)), blue)
