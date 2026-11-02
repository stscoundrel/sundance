extends SceneTree
## Cruz Verde's carpenter (the garrison out of the way, the stranger off the map):
##   worn     - the fort opens with crates, barrels and tables shot up in the last
##              battle, some holed, some wrecked flat (no cover, nothing in the way).
##   at work  - he's at them from the start, without waiting for the town's quiet.
##   far shot - shooting across the fort: he keeps at it.
##   near shot- shooting by him: he runs for a door; it moves off (the fort still
##              loud) and he's soon back out and at it again.
##   mended   - in the end every one of them is whole, and cover again.
##   godot --headless --path . --fixed-fps 60 -s tests/test_fort_carpenter.gd

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var step := "worn"
var c: Civilian
var worn: Array[Dictionary] = []
var fire_every := 0.0
var fire_t := 0.0
var fire_at := Vector2.ZERO
var went_in := false


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "cruz_verde")
	seed(3)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _next(s: String) -> void:
	print("%-9s done after %.1f s (%s, %d left)" % [step, t, Civilian.St.keys()[c.st], _left()])
	step = s
	t = 0.0


func _left() -> int:
	return worn.filter(func(p): return p["state"] > 0).size()


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(40, 60))
		if game.director:
			game.director.process_mode = Node.PROCESS_MODE_DISABLED   # (no waves called in by the test's shots)
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		for o in game.civilians:
			if o.carpenter:
				c = o
			else:
				o.process_mode = Node.PROCESS_MODE_DISABLED
				o.global_position += Vector2(0, -4000)   # (nobody standing where a crate goes back)
		check(c != null and c.local, "no carpenter in the fort, or he waits on the town's quiet")
		for p in game.props:
			if p["state"] > 0:
				worn.append(p)
		var wrecked := worn.filter(func(p): return p["state"] == 2)
		check(worn.size() == 11 and wrecked.size() == 3, "%d props worn, %d wrecked" % [worn.size(), wrecked.size()])
		check(wrecked.all(func(p): return p["body"] == null), "a wrecked prop still stands in the way")
		check(not game.stats.has("cover wrecked") and not game.stats.has("cover damaged"), "the old damage was counted")
	if frame <= 3:
		return false
	t += delta
	fire_t -= delta
	if fire_every > 0.0 and fire_t <= 0.0:
		fire_t = fire_every
		game.make_noise(fire_at, 380.0, "enemy_shot", null)
	match step:
		"worn":
			if c.st == Civilian.St.FIX:
				check(t < 10.0, "he took %.1f s to start" % t)
				fire_at = c.global_position + Vector2(400, -200)
				fire_every = 1.0
				_next("far shot")
			elif t > 30.0:
				check(false, "he never got to work (%s)" % Civilian.St.keys()[c.st])
				return _done()
		"far shot":
			check(c.st in [Civilian.St.FIX, Civilian.St.TO_FIX, Civilian.St.IDLE, Civilian.St.WALK],
				"he left off for shooting across the fort (%s)" % Civilian.St.keys()[c.st])
			if t > 8.0:
				fire_at = c.global_position + Vector2(60, 30)
				_next("near shot")
		"near shot":
			went_in = went_in or c.st == Civilian.St.GONE
			if went_in and fire_at.distance_to(c.home) < 300.0 and fire_at.distance_to(c.global_position) < 300.0:
				fire_at = Iso.to_screen(Vector2(4, 6))   # off away from him and his door: still loud
				t = 0.0
			elif went_in and c.st in [Civilian.St.TO_FIX, Civilian.St.FIX]:
				check(game.quiet_for() < 3.0, "(the fort went quiet)")
				check(t < Civilian.RETURN_T + 12.0, "he took %.1f s to get back to it" % t)
				fire_every = 0.0
				_next("mended")
			elif t > 40.0:
				check(false, "went in: %s, now %s" % [went_in, Civilian.St.keys()[c.st]])
				return _done()
		"mended":
			if _left() == 0:
				check(worn.all(func(p): return p["body"] != null and p["hp"] == game.PROP_HP[p["kind"]]),
					"a mended prop isn't cover again")
				return _done()
			elif t > 400.0:
				check(false, "%d still broken (%s)" % [_left(), Civilian.St.keys()[c.st]])
				return _done()
	return false


func _done() -> bool:
	print("stats: %s" % game.stats)
	print("fort carpenter test: " + ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
	return true
