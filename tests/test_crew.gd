extends SceneTree
## The town putting itself right once it's quiet (bandits out of town; a short
## quiet period):
##   mend   - a wrecked crate (no cover, walkable) and a holed barrel, a smashed
##            chair: the carpenter mends them all, the one the mayor tutted over
##            first though it's further; the crate is cover again and solid. The
##            saloon keeper sets his own broken table and chair right.
##   sweep  - a trail of the stranger's blood and some broken glass in the street:
##            swept away, the trail with them.
##   hens   - hens loose from a shot crate: the hen women shoo them home.
##   scare  - a shot near the carpenter at work: he runs, and leaves the job free.
##   godot --headless --path . --fixed-fps 60 -s tests/test_crew.gd

const QUIET := 2.0
const DIRT := Vector2(30.0, 31.2)   # main street, by the hotel

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var crate: Dictionary
var barrel: Dictionary
var chair: Dictionary
var table: Dictionary
var schair: Dictionary
var order: Array = []        # carpenter's jobs, in the order they're done
var by_keeper: Array = []
var watching: Array = []
var carpenter: Civilian
var keeper: Civilian


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_reserve", true)
	seed(9)
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
		game.quiet_after = QUIET
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		for c in game.civilians:
			if c.carpenter:
				carpenter = c
			if c.keeper:
				keeper = c
			if c.mayor:
				c._go_inside(false)   # (his tour would put things on the list too)
		check(carpenter != null and keeper != null, "no carpenter or keeper")
		check(game.civilians.filter(func(c): return c.sweeper).size() == 2, "two sweepers")
		check(game.civilians.filter(func(c): return c.henwife).size() == 2, "two hen women")
		_mend()
	if frame <= 3:
		return false
	t += delta
	for item in watching:   # who mends what, and in what order
		var f = item.get("fixer")
		if f == keeper and not item in by_keeper:
			by_keeper.append(item)
		if item["state"] == 0 and not item in order:
			order.append(item)
	if queue.is_empty():
		print("stats: ", game.stats)
		print("crew test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


## Broken without a sound (as if long ago in the fight).
func _wreck(item: Dictionary, n: int) -> void:
	if item.has("hp"):
		if n >= 2:
			item["hp"] = 0
		game._prop_state(item, n)
	else:
		while item["state"] < n:
			game.hit_fragile(item, game.job_at(item))


func _mend() -> void:
	step = "mend"
	var cp := carpenter.global_position
	var crates: Array = game.props.filter(func(p): return p["kind"] == "crate")
	crates.sort_custom(func(a, b): return game.prop_centre(a).distance_to(cp) < game.prop_centre(b).distance_to(cp))
	crate = crates[0]
	var barrels: Array = game.props.filter(func(p): return p["kind"] == "barrel")
	barrels.sort_custom(func(a, b): return game.prop_centre(a).distance_to(cp) > game.prop_centre(b).distance_to(cp))
	barrel = barrels.filter(func(b): return game.prop_centre(b).distance_to(cp) < 900.0)[0]
	chair = _of("chair").filter(func(c): return c["at"].distance_to(keeper.home) > game.KEEPS)[0]
	table = _of("table").filter(func(c): return c["at"].distance_to(keeper.home) < game.KEEPS)[0]
	schair = _of("chair").filter(func(c): return c["at"].distance_to(keeper.home) < game.KEEPS)[0]
	_wreck(crate, 2)
	_wreck(barrel, 1)
	_wreck(chair, 2)
	_wreck(table, 2)
	_wreck(schair, 2)
	watching = [crate, barrel, chair, table, schair]
	var cells: Array = crate["cells"].duplicate()
	check(crate["body"] == null, "a wrecked crate still stands")
	# the mayor has seen the barrel (further off than the crate)
	for s in game.scars:
		if s["prop"] == barrel:
			s["seen"] = true
	queue = [[150.0, func():
		print("mended in order: %s" % [order.map(func(i): return i["kind"])])
		for item in watching:
			check(item["state"] == 0, "the %s wasn't mended" % item["kind"])
		var mine: Array = order.filter(func(i): return i in [crate, barrel, chair])
		check(not mine.is_empty() and mine[0] == barrel, "the mayor's barrel should come first")
		check(crate["body"] != null and cells.all(func(c): return game.astar.is_point_solid(c)) and crate["hp"] == game.PROP_HP["crate"],
			"the mended crate isn't solid")
		check(crate["covers"].any(func(p): return p in game.cover_points), "the mended crate isn't cover")
		check(table in by_keeper and schair in by_keeper, "the keeper didn't see to his own table and chair")
		check(not chair in by_keeper, "the keeper mended a chair that isn't his")
		check(not game.scars.any(func(s): return s["prop"] in watching), "mended things still on the mayor's list")
		_sweep()]]


func _sweep() -> void:
	step = "sweep"
	var at := Iso.to_screen(DIRT)
	for i in 8:
		game.drip(game.player, at + Vector2(i * 9.0, i * 2.0))
	game._shards(at + Vector2(20, 10), 20.0, Color(0.82, 0.9, 0.96), 6)
	var near := func(): return game.decals.splats.filter(func(s): return s[0].distance_to(at + Vector2(30, 6)) < 50.0).size()
	print("dirt by the hotel: %d marks, %d drops" % [near.call(), game.trails.size()])
	queue.append([90.0, func():
		check(near.call() == 0, "%d marks left unswept" % near.call())
		check(game.trails.filter(func(d): return d["at"].distance_to(at) < 90.0).is_empty(), "the blood trail is still there")
		_hens()])


func _hens() -> void:
	step = "hens"
	var crates: Array = _of("hencrate")
	var c: Dictionary = crates[0]
	game.hit_fragile(c, c["at"])
	queue.append([120.0, func():
		var strays: Array = game.hens.filter(func(h): return h.position.distance_to(game.coop_for(h.position)["at"]) >= game.STRAY)
		print("hens: %d strays left; %s cooped, %s home" % [strays.size(), game.stats.get("hens cooped", 0),
			game.stats.get("hens home", 0)])
		check(strays.size() <= 1, "%d hens still astray" % strays.size())
		check(game.stats.get("hens cooped", 0) + game.stats.get("hens home", 0) >= 2, "nobody shooed the hens home")
		_scare()])


func _scare() -> void:
	step = "scare"
	var crates: Array = game.props.filter(func(p): return p["kind"] == "crate" and p["state"] == 0)
	crates.sort_custom(func(a, b): return game.prop_centre(a).distance_to(carpenter.global_position) \
		< game.prop_centre(b).distance_to(carpenter.global_position))
	crate = crates[0]
	_wreck(crate, 2)
	queue.append([0.2, func(): _wait_fixing(0.0)])


func _wait_fixing(waited: float) -> void:
	if carpenter.st != Civilian.St.FIX and waited < 120.0:
		queue.push_front([0.5, func(): _wait_fixing(waited + 0.5)])
		return
	check(carpenter.st == Civilian.St.FIX, "the carpenter never got to work")
	var job: Dictionary = carpenter.job
	game.make_noise(carpenter.global_position + Vector2(60, 0), 380.0, "shot", game.player)
	queue.push_front([0.5, func():
		check(carpenter.st in [Civilian.St.FLEE, Civilian.St.COWER, Civilian.St.GONE], "the carpenter worked on through gunfire")
		check(job.get("fixer") == null, "the job is still his")])
