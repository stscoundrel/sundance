extends SceneTree
## El General, Cruz Verde's coordinator (the garrison roused, then held still):
##   orders   - while he lives the gang's alarm is organised: lose enough men and the
##              rest fall back on a holdout.
##   head     - down he goes: the garrison's lost its head. Every man shaken to the
##              core; the faint-hearted run; no more falling back or sending men out,
##              however badly it goes; the next lot down the road arrive shaken.
##   godot --headless --path . --fixed-fps 60 -s tests/test_general.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var general: Enemy


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "cruz_verde")
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_downed", true)
	seed(21)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		# a shot: out they come
		game.seen_pos = Iso.to_screen(Vector2(32, 31))
		game.make_noise(Iso.to_screen(Vector2(32, 31)), 380.0, "shot", game.player)
		queue = [[32.0, _orders]]
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("stats: ", game.stats)
		print("general test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _orders() -> void:
	step = "orders"
	var d: Director = game.director
	check(d.indoors() == 0, "%d still indoors" % d.indoors())
	for e in game.enemies:
		if e.kind == "general":
			general = e
	check(general != null and general.tdata.get("coordinator", false), "no general, or he gives no orders")
	check(not game.leaderless, "headless with the general alive")
	_head()


func _head() -> void:
	step = "head"
	general.take_hit(10, Vector2.RIGHT, game.player)
	check(game.leaderless and game.stats.get("lost its head", 0) == 1, "the garrison didn't lose its head")
	check(game.hud.banner_text.contains("general"), "no word of it: %s" % game.hud.banner_text)
	var others: Array = game.enemies.filter(func(e): return e.alive)
	check(others.all(func(e): return e.shaken >= 1.0), "not all shaken")
	var ran: int = game.stats.get("loses heart", 0)
	print("of %d left: %d ran, %d wavered" % [others.size(), ran, game.stats.get("wavers at the news", 0)])
	check(ran >= 1 and ran + game.stats.get("wavers at the news", 0) == others.size(), "nobody ran, or some took no notice")
	# going badly as it could: no holdout, no men sent out
	var stage: int = game.alarm_stage
	game.fallen += 20
	game.raise_alarm(200.0)
	queue.append([2.0, func():
		check(game.alarm_stage == stage and game.holdout.is_empty(), "orders given with nobody to give them")
		check(not game.enemies.any(func(e): return e.alive and e.alarm_role == "fortified"), "men fell back on a holdout")
		game.director.clock += 28.0])   # (on to the next wave)
	queue.append([6.0, func():
		var late: Array = game.enemies.slice(15)
		print("%d walked in since" % late.size())
		check(late.size() >= 1 and game.stats.get("arrive headless", 0) == late.size(), "they walked in with their nerve")])
