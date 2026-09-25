extends Node3D
## 城市预览场景（开发用）

func _ready() -> void:
	var city := CityMap.new()
	add_child(city)
	var t0 := Time.get_ticks_msec()
	var env := EnvironmentRig.new()
	add_child(env)
	var cam := RTSCamera.new()
	add_child(cam)
	var d := float(DevTools.args.get("cam-dist", "620"))
	var tx := float(DevTools.args.get("cam-x", "0"))
	var tz := float(DevTools.args.get("cam-z", "0"))
	cam.set_view(Vector3(tx, 0, tz), d, 0)
	cam.bounds = Rect2(-2000, -2000, 4000, 4000)
	env.apply(GameState.time_of_day())
	await city.build(20260924)
	print("[dev] city built in %d ms: %d blocks, %d buildings, %d trees, %d nodes, %d edges" % [
		Time.get_ticks_msec() - t0, city.blocks.size(), city.buildings.size(), city.trees.size(), city.graph.positions.size(), city.graph.edges.size()])
	var traffic := Traffic.new()
	add_child(traffic)
	traffic.setup(city.graph, 120, 7)
