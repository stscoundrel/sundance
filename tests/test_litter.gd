extends SceneTree
## Cruz Verde the morning after (the garrison out of the way, the stranger off the
## map): broken bottles lie about the fort from the leaders' night of it, and the
## two sweepers are at them from the start, without waiting for the town's quiet,
## until every one is swept into the dirt.
##   godot --headless --path . --fixed-fps 60 -s tests/test_litter.gd

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var sweepers: Array[Civilian] = []
var spots: Array[Vector2] = []
var started := -1.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "cruz_verde")
	Engine.set_meta("no_captive", true)   # (nobody at the pole: see test_captive)
	seed(3)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


## Litter spots with glass still lying at them.
func _left() -> int:
	var n := 0
	for p in spots:
		if game.decals.splats.any(func(s): return s[0].distance_to(p) < 9.0):
			n += 1
	return n


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		if game.director:
			game.director.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(40, 60))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		for c in game.civilians:
			if c.sweeper:
				sweepers.append(c)
			else:
				c.process_mode = Node.PROCESS_MODE_DISABLED
				c.global_position += Vector2(0, -4000)
		for p in game.level["litter"]:
			spots.append(Iso.to_screen(Vector2(p[0], p[1])))
		check(sweepers.size() == 2 and sweepers.all(func(c): return c.local), "no pair of local sweepers in the fort")
		check(spots.size() >= 12 and _left() == spots.size(), "only %d of %d bottles lying" % [_left(), spots.size()])
	if frame <= 3:
		return false
	t += delta
	if started < 0.0 and sweepers.any(func(c): return c.st == Civilian.St.SWEEP):
		started = t
		check(t < 15.0, "they took %.1f s to start" % t)
	if _left() == 0:
		print("all swept after %.1f s (first broom at %.1f s)" % [t, started])
		check(game.stats.get("swept", 0) > 0, "nothing counted as swept")
		return _done()
	if t > 300.0:
		check(false, "%d of %d still lying (%s)" % [_left(), spots.size(), sweepers.map(func(c): return Civilian.St.keys()[c.st])])
		return _done()
	return false


func _done() -> bool:
	print("litter test: " + ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
	return true
