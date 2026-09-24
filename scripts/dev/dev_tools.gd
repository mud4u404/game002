extends Node
## 开发工具：命令行截图。用法：
##   godot -- --shot=/tmp/a.png --shot-frames=90 [--shot-hour=22.5] [--shot-script=name]

var _shot_path := ""
var _frames := 60
var _count := 0
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
		elif a.begins_with("--"):
			args[a.substr(2)] = "1"
	_shot_path = args.get("shot", "")
	_frames = int(args.get("shot-frames", "60"))
	if args.has("shot-hour"):
		GameState.minutes = float(args["shot-hour"]) * 60.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	if args.has("speed"):
		GameState.set_speed.call_deferred(float(args["speed"]))


func _process(_delta: float) -> void:
	if args.has("quit-frames"):
		_count += 1
		if _count % int(args.get("print-every", "600")) == 0:
			print("[t] ", Time.get_ticks_msec())
			var st := GameState.stats
			print("[sim] day %d %s money=%d safety=%.1f opinion=%.1f total=%d resolved=%d failed=%d perfect=%d calls=%d/%d" % [
				GameState.day(), GameState.clock_str(), GameState.money, GameState.safety, GameState.opinion,
				st.total, st.resolved, st.failed, st.perfect, st.calls_ok, st.calls_total])
			var g = get_tree().current_scene
			if g is Game and args.has("units-debug"):
				var parts := []
				for u in g.units:
					parts.append("%s:%s:%d%s" % [u.callsign, u.state_name(), int(u.fatigue), "R" if u.resting else ""])
				print("  ", " ".join(parts))
				var ip := []
				for inc in g.incidents:
					ip.append("%s/%s/%d" % [inc.title(), Incident.STATE_NAMES[inc.state], inc.units.size()])
				print("  inc: ", " ".join(ip))
		if _count >= int(args["quit-frames"]):
			get_tree().quit()
		return
	if _shot_path == "":
		return
	_count += 1
	if _count == _frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("[dev] screenshot saved: ", _shot_path)
		get_tree().quit()
