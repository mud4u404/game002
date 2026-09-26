class_name IncidentRail
extends Control
## 左侧警情栏：只有六边形图标 + 边框倒计时 + 已派单位小点；名称与位置在悬停提示里。

var game: Game
var items: Array = []        # Incident
var _hover := -1
const ITEM_H := 56.0


func _init(p_game: Game) -> void:
	game = p_game
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_items(list: Array) -> void:
	items = list
	custom_minimum_size = Vector2(64, maxf(list.size(), 0) * ITEM_H)
	size = custom_minimum_size


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var i := int(e.position.y / ITEM_H)
		_hover = i if i >= 0 and i < items.size() else -1
		if _hover >= 0:
			var inc: Incident = items[_hover]
			tooltip_text = "%s\n%s\n需要：%s" % ["110 来电，点击接听" if inc.state == Incident.S.CALL else inc.title(), inc.desc(), Data.req_text(inc.req())]
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var i := int(e.position.y / ITEM_H)
		if i >= 0 and i < items.size():
			var inc: Incident = items[i]
			game.select(inc)
			game.cam.focus_on(inc.spot.pos)
			if inc.state == Incident.S.CALL:
				game.hud.open_call(inc)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in items.size():
		var inc: Incident = items[i]
		var c := Vector2(32, i * ITEM_H + ITEM_H * 0.5)
		var calling := inc.state == Incident.S.CALL
		var col := UIKit.RED if calling else Data.level_color(inc.level())
		if not inc.is_active():
			col = UIKit.GREEN if inc.state == Incident.S.DONE else UIKit.TEXT_MUTED
		var sel: bool = UIKit.same(game.selected, inc)
		var R := 19.0 if (sel or i == _hover) else 17.0
		if calling:
			var ph := fmod(t * 1.2, 1.0)
			UIKit.draw_hex(self, c, R + 3 + ph * 7.0, UIKit.with_alpha(col, 0.35 * (1.0 - ph)))
		UIKit.draw_hex(self, c, R + 2, Color(0.02, 0.06, 0.15, 0.85))
		UIKit.draw_hex(self, c, R, col.darkened(0.2), Color.WHITE if sel else col.lightened(0.3), 2.0 if sel else 1.2)
		UIKit.draw_icon(self, "phone_in_talk" if calling else inc.data().gi, c, 18, Color.WHITE)
		var frac := -1.0
		var rc := Color.WHITE
		match inc.state:
			Incident.S.WAITING, Incident.S.DISPATCHED:
				frac = clampf(inc.deadline / float(inc.true_data().deadline), 0, 1)
				rc = Color.WHITE if frac > 0.3 else UIKit.RED
			Incident.S.ONSCENE:
				frac = clampf(inc.progress, 0, 1)
				rc = UIKit.GREEN
			Incident.S.CALL:
				frac = clampf(1.0 - inc.call_wait / 10.0, 0, 1)
				rc = UIKit.RED
		if frac >= 0.0:
			UIKit.draw_hex_progress(self, c, R + 4, frac, rc, 2.0)
		# 已派单位（右侧小点）与缺口
		var need := inc.need()
		for k in maxi(need, inc.units.size()):
			var dp := c + Vector2(R + 10, -6 + k * 7)
			if k < inc.units.size():
				draw_circle(dp, 2.6, inc.units[k].state_color())
			else:
				draw_arc(dp, 2.4, 0, TAU, 10, UIKit.TEXT_MUTED, 1.0, true)
		if inc.stalled:
			draw_circle(c + Vector2(-R + 2, -R + 4), 6, UIKit.RED)
			UIKit.draw_text_c(self, "!", c + Vector2(-R + 2, -R + 4), 10, Color.WHITE)
