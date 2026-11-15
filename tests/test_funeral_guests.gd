extends SceneTree
## The townsfolk at the stranger's funeral (Civilian, role "guest"):
##   ring   - twenty of them from the four towns, in their own clothes, round the
##            grave in a looser ring behind the gunmen, every one further out than
##            any of them; they stand there, not wandering off.
##   shot   - one shot anywhere about the burial ground and they're away (none
##            not one of them stopping to gape), each down a road off the map, the furthest
##            from the shooting for the least running; gone, and not back.
##   murder - the stranger shooting one: "AN INNOCENT", as anywhere.
##   godot --headless --path . --fixed-fps 60 -s tests/test_funeral_guests.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var t0 := 0.0
var phase := 0
var guests: Array = []
var at0 := {}


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "funeral")
	Engine.set_meta("no_sermon", true)
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
	if frame <= 3:
		return false
	t += delta
	if t > 60.0:
		check(false, "ran out of time in phase %d" % phase)
		return _done()
	var grave := Iso.to_screen(Vector2(game.level["grave"][0] + 1.1, game.level["grave"][1] + 1.0))   # (the middle of the circle, the gunmen round it)
	match phase:
		0:
			if t < 1.0:
				return false
			step = "ring"
			guests = game.civilians.filter(func(c): return c.guest)
			check(guests.size() == 20, "twenty townsfolk at the grave: %d" % guests.size())
			var kinds := {}
			for c in guests:
				kinds[c.kind] = true
				at0[c] = c.global_position
				check(game.is_free(c.global_position), "%s stood on something solid at %s" % [c.kind, Iso.to_grid(c.global_position)])
			check(kinds.has("snowbound") and kinds.has("peon") and kinds.has("townswoman"), "not from all over: %s" % [kinds.keys()])
			var gunmen: Array = game.enemies.filter(func(e): return Iso.to_grid(e.global_position).distance_to(Iso.to_grid(grave)) < 4.5)
			var mid := Iso.to_grid(grave)
			var gun_far := 0.0
			for e in gunmen:
				gun_far = maxf(gun_far, Iso.to_grid(e.global_position).distance_to(mid))
			check(gunmen.size() >= 6, "the gunmen round the grave: %d" % gunmen.size())
			for c in guests:
				var d: float = Iso.to_grid(c.global_position).distance_to(mid)
				check(d > gun_far + 1.5, "%s at %s nearer the grave (%.1f tiles) than behind the gunmen (%.1f)" % [c.kind, Iso.to_grid(c.global_position), d, gun_far])
			phase = 1
			t0 = t
		1:   # a few seconds: they stand
			if t - t0 < 4.0:
				return false
			check(guests.all(func(c): return c.global_position.distance_to(at0[c]) < 6.0), "a townsman wandered off")
			step = "shot"
			game.make_noise(grave + Vector2(-40, 10), 900.0, "shot", game.player)   # (a shot by the grave)
			phase = 2
			t0 = t
		2:
			if t - t0 < 2.0:
				return false
			var off: Array = guests.filter(func(c): return c.alive and (c.st == Civilian.St.FLEE or c.st == Civilian.St.GONE))
			var living: Array = guests.filter(func(c): return c.alive)   # (the gang's fire can catch one as he runs: theirs, not the stranger's)
			check(game.stats.get("innocents", 0) == 0, "the stranger blamed for the gang's fire")
			check(off.size() == living.size(), "only %d of %d away after a shot" % [off.size(), living.size()])
			for c in guests:
				if not off.has(c):
					print("   stayed: ", c.kind, " st ", Civilian.St.keys()[c.st], " cower_t ", c.cower_t, " nerve ", c.nerve, " state ", game.state)
			var roads: Array = game.level["entries"].map(func(e): return Iso.to_screen(Vector2(e["x"], e["y"])))
			check(off.all(func(c): return roads.has(c.hid_at)), "a townsman running for somewhere other than a road out")
			phase = 3
			t0 = t
		3:   # one of them home: gone, and not coming back
			var gone: Array = guests.filter(func(c): return c.st == Civilian.St.GONE)
			if gone.is_empty() and t - t0 < 45.0:
				return false
			check(not gone.is_empty(), "nobody got away down a road")
			check(gone.all(func(c): return c.back_after == INF), "a townsman meaning to come back")
			step = "murder"
			var left: Array = guests.filter(func(c): return c.alive and c.st != Civilian.St.GONE)
			if not left.is_empty():
				var before: int = game.stats.get("innocents", 0)
				left[0].take_hit(10, Vector2.RIGHT, game.player)
				check(game.stats.get("innocents", 0) == before + 1, "shooting one of them no innocent")
			return _done()
	return false


func _done() -> bool:
	print("funeral guests test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
