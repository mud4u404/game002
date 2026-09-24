class_name RTSCamera
extends Node3D
## 俯瞰地图镜头（正交投影，正上方俯视）：平移（WASD/拖拽）、缩放（滚轮）、旋转（Q/E/中键，可选）。

signal clicked(screen_pos: Vector2)
signal right_clicked(screen_pos: Vector2)

const MIN_DIST := 70.0     # 正交视口可见高度（米）
const MAX_DIST := 1150.0

var cam: Camera3D
var target := Vector3(0, 0, -40)
var yaw := 0.0
var dist := 520.0
var bounds := Rect2(-520, -520, 1040, 1040)
var input_enabled := true
var auto_orbit := false
var orbit_speed := 0.05

var _t_target := target
var _t_yaw := yaw
var _t_dist := dist
var _press_pos := Vector2.ZERO
var _left_down := false
var _dragging := false
var _mid_down := false
var _shake := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = dist
	cam.near = 1.0
	cam.far = 2000.0
	add_child(cam)
	cam.current = true
	_apply()


func set_view(p_target: Vector3, p_dist: float, p_yaw: float, instant := true) -> void:
	_t_target = p_target
	_t_dist = p_dist
	_t_yaw = p_yaw
	if instant:
		target = p_target
		dist = p_dist
		yaw = p_yaw
		_apply()


func focus_on(p: Vector3, zoom := -1.0) -> void:
	_t_target = Vector3(p.x, 0, p.z)
	if zoom > 0:
		_t_dist = zoom


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _apply() -> void:
	cam.size = dist
	cam.global_position = target + Vector3(0, 800.0, 0)
	cam.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5)
	if _shake > 0.01:
		cam.h_offset = randf_range(-1, 1) * _shake
		cam.v_offset = randf_range(-1, 1) * _shake
	else:
		cam.h_offset = 0
		cam.v_offset = 0


func _process(delta: float) -> void:
	if auto_orbit:
		_t_yaw += orbit_speed * delta
	if input_enabled:
		var mv := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			mv.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			mv.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			mv.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			mv.x += 1
		if Input.is_key_pressed(KEY_Q):
			_t_yaw += 1.4 * delta
		if Input.is_key_pressed(KEY_E):
			_t_yaw -= 1.4 * delta
		if mv != Vector2.ZERO:
			_pan(mv.normalized() * delta * dist * 0.9)
	_t_target.x = clampf(_t_target.x, bounds.position.x, bounds.end.x)
	_t_target.z = clampf(_t_target.z, bounds.position.y, bounds.end.y)
	var k := 1.0 - exp(-delta * 9.0)
	target = target.lerp(_t_target, k)
	dist = lerpf(dist, _t_dist, k)
	yaw = lerp_angle(yaw, _t_yaw, k)
	_shake = maxf(_shake - delta * 3.0, 0.0)
	_apply()


func _pan(screen_move: Vector2) -> void:
	var fwd := Vector3(-sin(_t_yaw), 0, -cos(_t_yaw))
	var right := Vector3(cos(_t_yaw), 0, -sin(_t_yaw))
	_t_target += right * screen_move.x - fwd * screen_move.y


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_t_dist = clampf(_t_dist * 0.88, MIN_DIST, MAX_DIST)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_t_dist = clampf(_t_dist * 1.13, MIN_DIST, MAX_DIST)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_down = true
					_dragging = false
					_press_pos = mb.position
				else:
					if _left_down and not _dragging:
						clicked.emit(mb.position)
					_left_down = false
					_dragging = false
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					right_clicked.emit(mb.position)
			MOUSE_BUTTON_MIDDLE:
				_mid_down = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left_down:
			if not _dragging and mm.position.distance_to(_press_pos) > 6.0:
				_dragging = true
			if _dragging:
				_pan(-mm.relative * _px_to_m())
		if _mid_down:
			_t_yaw -= mm.relative.x * 0.006


func _px_to_m() -> float:
	return dist / maxf(get_viewport().get_visible_rect().size.y, 1.0)


## 屏幕坐标 → 地面（y=0）交点
func ground_point(screen: Vector2) -> Vector3:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return from
	var t := -from.y / dir.y
	return from + dir * t
