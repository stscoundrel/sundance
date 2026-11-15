extends SceneTree
## The funeral's posse (A Good Man Never Dies; see Posse, Director.all_in):
##   waits  - seven guests left, but one faction's help still on its way: no posse yet.
##   untouched - a faction that's lost nobody, its help never sent for: once the rest's
##            help is in, it sends its runner, and the posse waits for its men too.
##   forms  - every faction's help in (or not coming): the last seven band together,
##            whatever their faction, all in it.
##   route  - they sweep the burial ground's own places: the grave, the mission, both
##            dinners, the undertaker's, the cantina, the town, the road, the old
##            graves; every one of them in reach from the grave.
##   stands - nobody in it runs: no fleeing at a fright, no losing heart.
##   sweep  - they gather and set off, and the leader gets to the first place with
##            the rest about him (the whole round would take minutes: not tested).
##   godot --headless --path . --fixed-fps 60 -s tests/test_funeral_posse.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var t0 := 0.0
var phase := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "funeral")
	Engine.set_meta("no_coffin", true)
	Engine.set_meta("no_downed", true)
	Engine.set_meta("no_gasp", true)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game._to_loadout()
		game.player.hp = 1000000
		game.player.global_position = Iso.to_screen(Vector2(3.0, 96.0))   # (off in the far corner, out of their way)
	if frame <= 3:
		return false
	t += delta
	if t > 100.0:   # (a test that loses its way ends, failing, rather than run on)
		check(false, "ran out of time in phase %d" % phase)
		return _done()
	var d: Director = game.director
	match phase:
		0:
			if t < 2.0:
				return false
			step = "waits"
			for g in d.camps:   # (every faction's runner already home, its men a long way off yet; the northerners untouched)
				if g != "northerners":
					d.camps[g]["state"] = "fetching"
					d.camps[g]["due"] = 1e9
			var alive: Array = game.enemies.filter(func(e): return e.alive and e.gang != "northerners")
			for i in game.alive_enemies() - 7:   # (dead of nothing anyone saw: nobody runs off after the stranger)
				alive[i].silent_death = true
				alive[i].take_hit(1000, Vector2.RIGHT, null)
			phase = 1
			t0 = t
		1:
			if t - t0 < 1.0:
				return false
			check(game.alive_enemies() == 7, "seven left: %d" % game.alive_enemies())
			check(game.posse == null, "a posse with help still on its way")
			for g in d.camps:   # (three came in)
				if g != "northerners":
					d.camps[g]["state"] = "sent"
			phase = 4
			t0 = t
		4:   # the untouched send for theirs
			if d.camps["northerners"]["state"] == "" and t - t0 < 2.0:
				return false
			step = "untouched"
			check(d.camps["northerners"]["state"] in ["running", "fetching"], "the northerners never sent: %s" % d.camps["northerners"]["state"])
			check(game.posse == null, "a posse with the northerners' help not in")
			d.camps["northerners"]["state"] = "sent"   # (their men in)
			phase = 2
			t0 = t
		2:
			if game.posse == null and t - t0 < 2.0:
				return false
			step = "forms"
			var p: Posse = game.posse
			check(p != null, "no posse with every faction's help in")
			if p == null:
				return _done()
			check(p.members.size() == 7, "all seven in it: %d" % p.members.size())
			var gangs := {}
			for e in p.members:
				gangs[e.gang] = true
			check(gangs.size() >= 2, "a posse of one faction only: %s" % [gangs.keys()])
			step = "route"
			var route: Array = game.level["posse_route"]
			check(p.points.size() == route.size(), "places on the route: %d of %d" % [p.points.size(), route.size()])
			var names: Array = route.map(func(r): return r["name"])
			for want in ["the grave", "the mission", "the west dinner", "the east dinner", "the main street", "the road west", "the road east"]:
				check(want in names, "%s not on the route" % want)
			var grave := Iso.to_screen(Vector2(float(route[0]["x"]), float(route[0]["y"])))
			for i in p.points.size():
				var way: PackedVector2Array = game.find_path(grave, p.points[i])
				check(way.size() > 0 and way[way.size() - 1].distance_to(p.points[i]) < 30.0, "%s out of reach from the grave" % names[i])
			step = "stands"
			var e0: Enemy = p.members[0]
			var fled := 0
			for i in 200:
				fled += 1 if e0._pick_reaction(true, true) == "flee" else 0
			check(fled == 0, "a posse man fled %d times in 200 frights" % fled)
			phase = 3
			t0 = t
		3:   # gathered, off, and to the first place
			var p: Posse = game.posse
			if p.visited.is_empty() and t - t0 < 85.0:
				return false
			step = "sweep"
			check(not p.gathering, "never set off")
			check(not p.visited.is_empty(), "never got anywhere in %.0f s" % (t - t0))
			var near := 0
			for e in p.members:
				if e.alive and e.global_position.distance_to(p.leader.global_position) < Posse.LAG * 1.5:
					near += 1
			check(near >= 5, "the posse strung out: %d near the leader" % near)
			print("first place in %.1f s" % (t - t0))
			return _done()
	return false


func _done() -> bool:
	print("funeral posse test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
