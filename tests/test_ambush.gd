extends SceneTree
## Cruz Verde done with the knife: the five on guard go down without a shot. The
## quiet's noticed in the end: those indoors come out (no faster than the slowest
## wakes) and go looking, wary, not straight to a fight; and the waves start then.
##   godot --headless --path . --fixed-fps 60 -s tests/test_ambush.gd

var game: Node
var frame := 0
var failures := 0
var t := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "cruz_verde")
	Engine.set_meta("no_captive", true)   # (nobody at the pole: see test_captive)
	Engine.set_meta("no_civilians", true)
	seed(20)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
	if frame <= 3:
		return false
	t += delta
	if is_equal_approx(snappedf(t, 1.0 / 60.0), 2.0):
		for e in game.enemies:   # quietly, one by one
			e.die(Vector2.RIGHT, game.player, "death_slump")
	if t < 34.0:
		return false
	var d: Director = game.director
	print("roused by %s; %d came out; states %s; next wave in %.0f s" % [game.stats.get("roused by", "nothing"),
		game.stats.get("out of doors", 0), game.enemies.slice(5).map(func(e): return Enemy.St.keys()[e.st]), d.next_in()])
	check(game.last_gunfire < -1e8, "a shot was fired")
	check(game.stats.get("roused by", "") == "the quiet", "not roused by the quiet")
	check(d.indoors() == 0 and game.stats.get("out of doors", 0) == 10, "not all out")
	check(game.enemies.slice(5).all(func(e): return e.st in [Enemy.St.INVESTIGATE, Enemy.St.SEARCH]), "they didn't go looking")
	check(d.next_in() > 0.0, "the waves never started")
	check(game.state == "play", "won with the garrison still to come")
	print("ambush test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
