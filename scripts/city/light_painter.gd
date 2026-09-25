class_name LightPainter
extends Node2D
## 夜间路灯光照贴图：在 SubViewport 中叠加径向光斑。

var lights: Array = []
var _tex: GradientTexture2D


func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.45))
	_tex = GradientTexture2D.new()
	_tex.gradient = g
	_tex.fill = GradientTexture2D.FILL_RADIAL
	_tex.fill_from = Vector2(0.5, 0.5)
	_tex.fill_to = Vector2(1.0, 0.5)
	_tex.width = 128
	_tex.height = 128
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.position = Vector2(-5000, -5000)
	bg.size = Vector2(10000, 10000)
	bg.show_behind_parent = true
	add_child(bg)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	queue_redraw()


func _draw() -> void:
	for L in lights:
		var p: Vector2 = L[0]
		var r: float = L[1]
		var c: Color = L[2]
		var k: float = L[3]
		draw_texture_rect(_tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c.r * k, c.g * k, c.b * k, 1.0))
