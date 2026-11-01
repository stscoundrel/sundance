extends SceneTree
## Where a big gunfight's frame time goes (a tool, not a pass/fail test). The --bot
## stranger shoots it out on main street, invulnerable, with the townsfolk about,
## for LENGTH seconds; every scripted thing is run by hand here and timed by kind,
## and each frame's time is split by kind. Reports the average and worst per kind,
## the slow frames (over a 60 fps budget) and what filled them, and how many rays
## and paths a frame asks for.
## Run it in a window (no --headless, vsync off) to time whole frames, drawing
## and all ("wall" below).
##   godot --headless --path . --fixed-fps 60 -s tests/profile.gd [-- --length=40]
##   godot --path . -s tests/profile.gd

const HERO := Vector2(26.0, 31.4)
const BUDGET := 16.6

var game: Node
var frame := 0
var clock := 0.0
var length := 40.0
var kinds := {}        # kind -> [total usec, worst usec]
var frames: Array = [] # per frame: {kind: usec}
var rays: Array[int] = []
var paths: Array[int] = []
var _last := {}
var walls: Array[float] = []
var render := {"draw calls": [], "objects": [], "primitives": [], "render cpu ms": [], "render gpu ms": []}
var _wall := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--length="):
			length = float(a.get_slice("=", 1))
	seed(9)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _kind(n: Node) -> String:
	if n is Enemy: return "bandits"
	if n is Civilian: return "townsfolk"
	if n is Player: return "stranger"
	if n is Chicken: return "hens"
	if n is Bullet: return "bullets"
	if n is Puff: return "smoke & bits"
	if n is Dynamite: return "dynamite"
	if n is Tumbleweed: return "tumbleweed"
	return ""


func _physics_process(delta: float) -> bool:
	return false


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.global_position = Iso.to_screen(HERO)
		game.player.hp = 1000000
		game.player.weapons["colt"].reserve = 1000
		game._args["bot"] = "1"
	if frame <= 3:
		return false
	clock += delta
	var now := Time.get_ticks_usec()
	if _wall > 0:
		walls.append((now - _wall) / 1000.0)
		var vp := root.get_viewport_rid()
		render["draw calls"].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		render["objects"].append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		render["primitives"].append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		render["render cpu ms"].append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		render["render gpu ms"].append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	_wall = now
	var f := {}
	var r0: int = game.counts["rays"]
	var p0: int = game.counts["paths"]
	# take over every scripted node in the world: off their own clocks, onto ours
	var t0 := Time.get_ticks_usec()
	game.set_physics_process(false)
	game._physics_process(delta)
	_add(f, "game (den, posse, harass)", Time.get_ticks_usec() - t0)
	for n in game.world.get_children():
		var k := _kind(n)
		if k == "" or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if n.is_physics_processing():
			n.set_physics_process(false)
		if n.is_processing() and (n is Puff or n is Tumbleweed):
			n.set_process(false)
		if n.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		var t := Time.get_ticks_usec()
		if n.has_method("_physics_process"):
			n._physics_process(delta)
		if (n is Puff or n is Tumbleweed) and is_instance_valid(n):
			n._process(delta)
		_add(f, k, Time.get_ticks_usec() - t)
	var cones := Time.get_ticks_usec()
	for c in game.cone_layer.get_children():
		c.queue_redraw()
	_add(f, "view cones", Time.get_ticks_usec() - cones)
	var g0 := Time.get_ticks_usec()
	game.set_process(false)
	game._process(delta)
	_add(f, "game _process (shutters, fades)", Time.get_ticks_usec() - g0)
	for k in game.counts:   # the bandits' insides, when they're timed (see Enemy._prof)
		if k in ["rays", "paths"]:
			continue
		var d: int = game.counts[k] - _last.get(k, 0)
		_last[k] = game.counts[k]
		if d > 0:
			f["  " + k] = d
	frames.append(f)
	rays.append(game.counts["rays"] - r0)
	paths.append(game.counts["paths"] - p0)
	if clock < length:
		return false
	_report()
	quit(0)
	return true


func _add(f: Dictionary, k: String, us: int) -> void:
	f[k] = f.get(k, 0) + us
	if not kinds.has(k):
		kinds[k] = [0, 0]


func _report() -> void:
	var totals: Array[float] = []
	for f in frames:
		var sum := 0
		for k in f:
			if not kinds.has(k):
				kinds[k] = [0, 0]
			kinds[k][0] += f[k]
			kinds[k][1] = maxi(kinds[k][1], f[k])
			if not k.begins_with("  "):
				sum += f[k]
		totals.append(sum / 1000.0)
	var n := frames.size()
	var sorted := totals.duplicate()
	sorted.sort()
	print("%d frames; scripted time a frame: %.2f ms average, %.2f at the 95th percentile, %.2f worst" % [
		n, totals.reduce(func(a, b): return a + b, 0.0) / n, sorted[int(n * 0.95)], sorted[-1]])
	if not walls.is_empty():
		var ws := walls.duplicate()
		ws.sort()
		print("wall time a frame (everything, drawing too): %.2f ms average, %.2f at the 95th percentile, %.2f at the 99th, %.2f worst; %d frames over 16.6 ms" % [
			walls.reduce(func(a, b): return a + b, 0.0) / ws.size(), ws[int(ws.size() * 0.95)], ws[int(ws.size() * 0.99)], ws[-1],
			ws.filter(func(w): return w > 16.6).size()])
	if not walls.is_empty():
		var idx := range(walls.size())
		idx.sort_custom(func(a, b): return walls[a] > walls[b])
		print("worst frames (index, wall ms, render cpu ms): ", idx.slice(0, 6).map(func(i): return [i, snappedf(walls[i], 0.1),
			snappedf(render["render cpu ms"][i], 0.1)]))
	for k in render:
		var v: Array = render[k]
		if v.is_empty():
			continue
		var vs := v.duplicate()
		vs.sort()
		print("  %-14s %8.1f average, %8.1f at the 95th percentile, %8.1f worst" % [k,
			v.reduce(func(a, b): return a + b, 0.0) / v.size(), vs[int(vs.size() * 0.95)], vs[-1]])
	var order := kinds.keys()
	order.sort_custom(func(a, b): return kinds[a][0] > kinds[b][0])
	for k in order:
		print("  %-32s %6.2f ms avg   %6.2f ms worst" % [k, kinds[k][0] / 1000.0 / n, kinds[k][1] / 1000.0])
	var slow := []
	for i in n:
		if totals[i] > BUDGET * 0.6:
			slow.append(i)
	print("%d frames over %.1f ms; what filled them:" % [slow.size(), BUDGET * 0.6])
	var fill := {}
	for i in slow:
		for k in frames[i]:
			fill[k] = fill.get(k, 0) + frames[i][k]
	var fo := fill.keys()
	fo.sort_custom(func(a, b): return fill[a] > fill[b])
	for k in fo:
		print("  %-32s %6.2f ms avg in those frames" % [k, fill[k] / 1000.0 / maxi(slow.size(), 1)])
	var rs := rays.duplicate()
	rs.sort()
	print("rays a frame: %.0f average, %d at the 95th percentile, %d worst; paths: %.2f average, %d worst" % [
		rays.reduce(func(a, b): return a + b, 0) / float(n), rs[int(n * 0.95)], rs[-1],
		paths.reduce(func(a, b): return a + b, 0) / float(n), paths.max()])
	var ks: Array = game.counts.keys().filter(func(k): return k != "rays" and k != "paths")
	ks.sort_custom(func(a, b): return game.counts[a] > game.counts[b])
	print("inside (ms a frame on average): ", ", ".join(ks.map(func(k): return "%s %.2f" % [k, game.counts[k] / 1000.0 / n])))
	print("stats: ", game.stats)
