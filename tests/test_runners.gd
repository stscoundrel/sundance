extends SceneTree
## Runners at the funeral (A Good Man Never Dies; see Director, the camps):
##   runner  - one of a faction shot: the faction's nearest man runs for its road;
##             within shouting distance of the map's edge he's heard, and a few
##             seconds on the faction's men ride in down that road, all at once,
##             armed with their long guns, quick to it and not struck dumb (they've
##             been told).
##   shot    - a faction whose runner's shot down on the way gets no help; one shot
##             at (a near miss, a graze) keeps running, and is only heard at his
##             road, never gone wherever the scare left him.
##   godot --headless --path . --fixed-fps 60 -s tests/test_runners.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var phase := 0
var t := 0.0
var t0 := 0.0
var runner: Enemy = null
var last_at := Vector2.ZERO   # where the runner was last seen (he's gone off the map once he's heard)
var old := {}                # everyone there before the bandidos' men came
var came_in := {}            # the new men, and where each was first seen


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


func _of(g: String) -> Array:
	return game.enemies.filter(func(e): return e.alive and e.gang == g)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game._to_loadout()
		game.player.hp = 1000000
		game.player.global_position = Iso.to_screen(Vector2(44.0, 84.0))   # (out of the way, down the south slope)
	if frame <= 3:
		return false
	t += delta
	if t > 110.0:   # (a test that loses its way ends, failing, rather than run on)
		check(false, "ran out of time in phase %d" % phase)
		return _done()
	var d: Director = game.director
	match phase:
		0:
			if t < 2.0:
				return false
			step = "runner"
			check(d != null and d.camps.size() == 4, "no roads home: %s" % [d.camps.keys() if d else "-"])
			for e in game.enemies:
				old[e] = true
			_of("bandidos")[0].take_hit(1000, Vector2.RIGHT, game.player)   # (one of the bandidos down)
			_of("federales")[0].take_hit(1000, Vector2.RIGHT, game.player)  # (and a federal)
			phase = 1
		1:   # each faction sends its man
			if d.camps["bandidos"]["state"] != "running" or d.camps["federales"]["state"] != "running":
				if t > 6.0:
					check(false, "no runners: %s %s" % [d.camps["bandidos"]["state"], d.camps["federales"]["state"]])
					return _done()
				return false
			runner = d.camps["bandidos"]["runner"]
			# shot at as he runs (a near miss, then a graze): he keeps running, and
			# doesn't vanish wherever the scare left him
			runner.near_miss(game.player.global_position)
			runner.take_hit(1, Vector2.RIGHT, game.player)
			step = "shot"
			d.camps["federales"]["runner"].take_hit(1000, Vector2.RIGHT, game.player)   # (the federal runner, cut down)
			t0 = t
			phase = 2
		2:   # the bandido gets in shouting distance, and his men come
			if is_instance_valid(runner) and runner.alive:
				last_at = runner.global_position
			if d.camps["bandidos"]["state"] in ["running", "fetching"] and t - t0 < 80.0:
				return false
			step = "runner"
			check(d.camps["bandidos"]["state"] == "sent", "the bandidos' men never came: %s" % d.camps["bandidos"]["state"])
			check(d.camps["federales"]["state"] == "lost", "the federales got help with their runner dead: %s" % d.camps["federales"]["state"])
			var g := Iso.to_grid(last_at)
			var camp := Iso.to_grid(d.camps["bandidos"]["at"])
			check(g.distance_to(camp) < float(game.level["shout"]) + 0.5, "heard a long way from the west road: %s, the road at %s" % [g, camp])
			check(minf(g.x, g.y) > 1.2 or game.size - maxf(g.x, g.y) > 1.2, "he went right to the edge, not just in shouting distance")
			phase = 3
		3:
			for e in game.enemies:
				if not old.has(e) and not came_in.has(e):
					came_in[e] = Iso.to_grid(e.global_position)
			if came_in.size() < 5 and t - t0 < 90.0:
				return false
			var new: Array = came_in.keys()
			check(new.size() == 5 and new.all(func(e): return e.gang == "bandidos"), "the bandidos' men: %s" % [new.map(func(e): return e.gang)])
			check(new.all(func(e): return not e.tdata.get("pistols_only", false) and e.reflex <= float(e.tdata["reflex"][1]) + 0.001), "they came as guests (pistols only, slow at it), not armed for a fight")
			check(new.all(func(e): return e.saw_him_risen and e.stowed == ""), "they came to stare, not fight")
			check(came_in.values().all(func(g): return g.x < 6.0), "not down the west road: %s" % [came_in.values()])
			return _done()
	return false


func _done() -> bool:
	print("runners test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
