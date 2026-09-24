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


func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_count += 1
	if _count == _frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("[dev] screenshot saved: ", _shot_path)
		get_tree().quit()
