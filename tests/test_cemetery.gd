extends SceneTree
## Cruz Verde's cemetery (the garrison out of the way, the stranger off the map):
##   visiting  - the families go from grave to grave round the stone circle.
##   far shot  - shooting over in the fort: they carry on.
##   gate shot - shooting at the west gate: they scatter off the edge of the map.
##   return    - it stops at the gate (though not in the fort): they're back soon.
##   digging   - the grave digger digs out each open grave, lets the coffin down and
##               fills it in: a fresh grave (one of the three; one is enough to see
##               it), and the families come to it.
##   godot --headless --path . --fixed-fps 60 -s tests/test_cemetery.gd

const FORT := Vector2(32.0, 30.0)   # the plaza, inside the walls
const GATE := Vector2(17.5, 30.5)   # just inside the west gate

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var step := "visiting"
var digger: Civilian
var folk: Array[Civilian] = []
var fire_every := 0.0
var fire_t := 0.0
var fire_at := Vector2.ZERO
var fled := false


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
		print("FAIL: [%s] %s" % [step, msg])


func _next(s: String) -> void:
	print("%-9s done after %.1f s" % [step, t])
	step = s
	t = 0.0


func _states() -> Array:
	return folk.map(func(c): return Civilian.St.keys()[c.st])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(40, 60))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		for c in game.civilians:
			if c.digger:
				digger = c
				folk.append(c)
			elif c.visitor:
				folk.append(c)
			else:
				c.process_mode = Node.PROCESS_MODE_DISABLED
		check(digger != null and folk.size() >= 4, "no grave digger, or too few families (%d)" % folk.size())
		check(digger.has_anim("upper/spade/dig"), "the digger has no digging")
		check(folk.all(func(c): return c.digger or c.has_anim("upper/grief/mourn")), "a mourner has no grieving poses")
		check(game.open_graves.size() == 3, "%d open graves" % game.open_graves.size())
		# one is as good as three for the digging, and each is a minute of it: the
		# nearest the digger is his job, the other two are left as they lie
		game.open_graves.sort_custom(func(a, b): return a["at"].distance_to(digger.global_position) < b["at"].distance_to(digger.global_position))
		game.open_graves.resize(1)
		check(game.old_graves.size() > 40, "only %d old graves" % game.old_graves.size())
	if frame <= 3:
		return false
	t += delta
	fire_t -= delta
	if fire_every > 0.0 and fire_t <= 0.0:
		fire_t = fire_every
		game.make_noise(Iso.to_screen(fire_at), 380.0, "enemy_shot", null)
	match step:
		"visiting":
			var all_there := folk.all(func(c): return game._on_boot_hill(Iso.to_grid(c.global_position)))
			if (game.stats.get("mournings", 0) >= 4 and all_there) or t > 45.0:
				check(game.stats.get("mournings", 0) >= 4, "only %d graves visited" % game.stats.get("mournings", 0))
				for c in folk:
					check(game._on_boot_hill(Iso.to_grid(c.global_position)), "%s wandered off to %s" % [c.kind,
						Iso.to_grid(c.global_position)])
				fire_at = FORT
				fire_every = 1.0
				_next("far shot")
		"far shot":
			check(not folk.any(func(c): return c.st in [Civilian.St.FLEE, Civilian.St.GONE, Civilian.St.COWER]),
				"they ran from shooting in the fort: %s" % [_states()])
			if t > 6.0:
				fire_at = GATE
				_next("gate shot")
		"gate shot":
			if folk.all(func(c): return c.st == Civilian.St.GONE):
				fire_at = FORT   # it moves off into the fort
				_next("return")
			elif t > 15.0:
				check(false, "they didn't all get away: %s" % [_states()])
				return _done()
		"return":
			if folk.all(func(c): return c.st != Civilian.St.GONE and c.st != Civilian.St.FLEE):
				check(game.quiet_for() < 3.0, "(the fort went quiet)")
				check(t < Civilian.RETURN_T + 10.0, "they took %.1f s to come back" % t)
				fire_every = 0.0
				_next("digging")
			elif t > 40.0:
				check(false, "they never came back: %s" % [_states()])
				return _done()
		"digging":
			if game.open_graves.all(func(g): return g["done"]):
				check(game.stats.get("graves dug", 0) == 1, "%d graves counted" % game.stats.get("graves dug", 0))
				check(game.to_mourn.size() == 1, "%d fresh graves to mourn" % game.to_mourn.size())
				check(not game.open_graves.any(func(g): return g["sprite"].visible), "an open grave's still showing")
				_next("mourned")
			elif t > 200.0:
				check(false, "the digger didn't finish: %s" % [game.open_graves.map(func(g): return [g["dug"], g["filled"]])])
				return _done()
		"mourned":
			if game.to_mourn.all(func(g): return g["done"]):
				return _done()
			elif t > 90.0:
				check(false, "the fresh graves went unmourned: %s" % [game.to_mourn])
				return _done()
	return false


func _done() -> bool:
	print("stats: %s" % game.stats)
	print("cemetery test: " + ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
	return true
