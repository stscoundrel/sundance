extends SceneTree
## Frame cost with and without the townsfolk: the same 30 s firefight (the --bot
## autopilot on main street, invulnerable) run twice, timing every physics frame.
## Reports the average and the 95th percentile; fails if physics and AI alone can't
## hold 60 fps on average, or the town with townsfolk runs clearly slower (the two
## fights differ a little, so the comparison is loose):
##   godot --headless --path . --fixed-fps 60 -s tests/test_perf.gd

const HERO := Vector2(26.0, 31.4)
const LENGTH := 30.0
const BUDGET_MS := 16.6   # a whole 60 fps frame (debug build: an export runs faster)

var game: Node
var run := 0
var frame := 0
var clock := 0.0
var times: Array[float] = []
var results := []
var failures := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	_start()


func _start() -> void:
	seed(9)
	if game:
		game.queue_free()
	if run == 1:
		Engine.set_meta("no_civilians", true)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	frame = 0
	clock = 0.0
	times.clear()


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


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
	times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if clock < LENGTH:
		return false
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	var p95: float = sorted[int(sorted.size() * 0.95)]
	results.append([avg, p95, game.civilians.size()])
	print("%2d townsfolk: physics %.2f ms a frame on average, %.2f ms at the 95th percentile" % [game.civilians.size(), avg, p95])
	if run == 0:
		run = 1
		_start()
		return false
	var with: Array = results[0]
	var without: Array = results[1]
	check(with[0] < BUDGET_MS, "%.2f ms a frame is over budget" % with[0])
	check(with[0] < without[0] * 1.25 + 1.0, "townsfolk cost too much: %.2f vs %.2f ms" % [with[0], without[0]])
	print("perf test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
