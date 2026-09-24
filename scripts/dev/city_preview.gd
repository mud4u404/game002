extends Node3D
## 城市预览场景（开发用）

func _ready() -> void:
	var city := CityBuilder.new()
	add_child(city)
	var t0 := Time.get_ticks_msec()
	city.build(20260924)
	print("[dev] city built in %d ms" % (Time.get_ticks_msec() - t0))
	var env := EnvironmentRig.new()
	add_child(env)
	var traffic := Traffic.new()
	add_child(traffic)
	traffic.setup(city.graph, 180, 7)
	var cam := RTSCamera.new()
	add_child(cam)
	var d := float(DevTools.args.get("cam-dist", "620"))
	var y := float(DevTools.args.get("cam-yaw", "0"))
	var tx := float(DevTools.args.get("cam-x", "0"))
	var tz := float(DevTools.args.get("cam-z", "-30"))
	cam.set_view(Vector3(tx, 0, tz), d, y)
	env.apply(GameState.time_of_day())
