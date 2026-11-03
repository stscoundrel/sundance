extends SceneTree
## Hens (everyone held still, out of town):
##   yard    - hens peck about each coop, and with nothing happening they stay
##             about their yard.
##   shot    - gunfire near a coop: its hens bolt, flapping, well away, then settle
##             wherever they've got to.
##   boots   - a man walking right up to a hen sends her off a little way.
##   release - a round into a crate of hens or a coop lets them all out at once,
##             bolting; a second round lets nobody else out.
##   no mark - nothing can hit a hen: she has no body for a round to strike.
##   godot --headless --path . --fixed-fps 60 -s tests/test_hens.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var start: Dictionary = {}   # hen -> position
var coop: Dictionary
var near: Array = []


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _of(kind: String) -> Array:
	return game.fragile.filter(func(i): return i["kind"] == kind)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		_yard()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("stats: ", game.stats)
		print("hens test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _yard() -> void:
	step = "yard"
	var coops := _of("coop")
	check(coops.size() >= 4 and _of("hencrate").size() >= 2, "too few coops (%d) or crates (%d)" % [coops.size(),
		_of("hencrate").size()])
	check(game.hens.size() == coops.size() * game.HENS_OUT, "%d hens about %d coops" % [game.hens.size(), coops.size()])
	for h in game.hens:
		check(game.is_free(h.position), "a hen stands in a wall")
		start[h] = h.position
	queue = [[12.0, func():
		var far := 0.0
		for h in game.hens:
			far = maxf(far, h.position.distance_to(start[h]))
		print("calm: the furthest a hen wandered in 12 s: %.0f px" % far)
		check(far < 80.0, "a hen wandered %.0f px from her yard with nothing happening" % far)
		_shot()]]


func _shot() -> void:
	step = "shot"
	coop = _of("coop")[0]
	near = game.hens.filter(func(h): return h.position.distance_to(coop["at"]) < 60.0)
	for h in near:
		start[h] = h.position
	game.make_noise(coop["at"] + Vector2(70, 0), 380.0, "shot", game.player)
	queue.append([0.3, func():
		for h in near:
			check(h.st == Chicken.S.BOLT, "a hen by the coop didn't bolt at the shot")])
	queue.append([2.5, func():
		for h in near:
			check(h.position.distance_to(start[h]) > 40.0, "a hen only got %.0f px" % h.position.distance_to(start[h]))
			check(game.is_free(h.position), "a bolting hen ran into a wall")])
	queue.append([4.0, func():
		for h in near:
			check(h.st != Chicken.S.BOLT, "a hen never settled")
		_boots()])


func _boots() -> void:
	step = "boots"
	var h: Chicken = game.hens[game.hens.size() - 1]
	var p: Player = game.player
	p.global_position = h.position + Vector2(-20, 0)
	p.velocity = Vector2(40, 0)   # (walking at her)
	queue.append([0.5, func():
		check(h.st == Chicken.S.BOLT, "a hen let a man walk right up to her")
		p.velocity = Vector2.ZERO
		p.global_position = Iso.to_screen(Vector2(-40, -40))
		_release()])


func _release() -> void:
	step = "release"
	var crate: Dictionary = _of("hencrate")[0]
	var c2: Dictionary = _of("coop")[1]
	var n0: int = game.hens.size()
	game.hit_fragile(crate, crate["at"])
	check(game.hens.size() == n0 + game.HENS_IN["hencrate"], "a shot crate let out %d hens" % (game.hens.size() - n0))
	game.hit_fragile(crate, crate["at"])
	check(game.hens.size() == n0 + game.HENS_IN["hencrate"], "a second round let out more")
	game.hit_fragile(c2, c2["at"])
	check(game.hens.size() == n0 + game.HENS_IN["hencrate"] + game.HENS_IN["coop"], "a shot coop let out %d" %
		(game.hens.size() - n0 - game.HENS_IN["hencrate"]))
	for h in game.hens.slice(n0):
		check(h.st == Chicken.S.BOLT, "a hen out of the crate didn't bolt")
	check(game.stats.get("hens loose", 0) == game.HENS_IN["hencrate"] + game.HENS_IN["coop"], "hens loose: %s" %
		game.stats.get("hens loose", 0))
	step = "no mark"
	for h in game.hens:
		check(h.get_children().all(func(c): return not c is CollisionObject2D), "a hen has a body to hit")
