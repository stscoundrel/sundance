extends SceneTree
## Out of the coffin (A Good Man Never Dies, phase 2):
##   inside  - he starts in his coffin by the grave: unseen (nobody spots him, however
##             long they look), and going nowhere; the mourners listening, eyes on
##             the grave, their cones put away till he's out.
##   blows   - two nails: the lid takes 2 x 2 blows, a nail giving every second;
##             some of the guests by the grave hear the knocking, each turning to
##             it once, puzzled, and nobody draws.
##   burst   - the last blow and the lid's off: he's lying in the box, sitting up,
##             and within a second up beside it, the open coffin and its lid lying
##             by; everyone by the grave struck dumb, each his own way (pointing,
##             cowering...), and nobody anywhere fights or fires for the first
##             second and a half; within a few more the mourners all have; and no
##             stand-off close-up, then or when they come to (the surprise is his).
##   first   - a guest who first lays eyes on him later stares before he fights.
##   wake    - a shot far off at the cantina only puzzles a guest there ("?", no
##             fight), and some seconds later he walks over to see.
##   godot --headless --path . --fixed-fps 60 -s tests/test_coffin.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var phase := 0
var t0 := 0.0
var at_start := Vector2.ZERO
var far: Enemy = null
var went := -1.0   # how long after the shot he set off to see


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "funeral")
	Engine.set_meta("nails", 2)
	Engine.set_meta("no_sermon", true)   # (the lid alone: see test_sermon for the burial)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _mourners() -> Array:
	return game.enemies.filter(func(e): return e.tdata.get("mourning", false))


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game._to_loadout()
		game.player.hp = 1000000   # (he stands there for the test: they get him otherwise)
		at_start = game.player.global_position
	if frame <= 3:
		return false
	t += delta
	var c: Coffin = game.coffin
	var p: Player = game.player
	match phase:
		0:   # a few seconds shut in, the guests all about him
			if t < 4.0:
				return false
			step = "inside"
			check(c.inside and p.in_coffin and not p.visible, "not in the coffin")
			check(p.global_position.distance_to(at_start) < 1.0, "he moved in the box")
			check(game.enemies.all(func(e): return not e.sees_player and e.st != Enemy.St.COMBAT), "seen in his coffin")
			check(_mourners().all(func(e): return e.listening() and not e.cone.visible), "a mourner looking about, not listening")
			check(_mourners().all(func(e): return e.anim_gun == "unarmed"), "a gun in hand at the graveside: %s" % [_mourners().map(func(e): return e.anim_gun)])
			step = "blows"
			check(c.blows_left() == 4 and c.nails_left() == 2, "two nails: %d blows, %d nails" % [c.blows_left(), c.nails_left()])
			for i in 2:
				c.blow()
			check(c.nails_left() == 1 and c.inside, "after two blows: %d nails, inside %s" % [c.nails_left(), c.inside])
			c.blow()
			check(c.nails_left() == 1 and c.blows_left() == 1 and c.inside, "the last nail, the lid still on: %d" % c.blows_left())
			var heard: int = game.stats.get("hears knocking", 0)
			var near: Array = _mourners().filter(func(e): return e.global_position.distance_to(c.global_position) < Coffin.KNOCK_EAR)
			check(heard >= 1 and heard < near.size(), "the knocking: heard by %d of the %d near enough" % [heard, near.size()])
			check(heard == near.filter(func(e): return e.heard_knock).size(), "a man reacted to the knocking more than once")
			check(_mourners().all(func(e): return e.st != Enemy.St.COMBAT and e.reaction == ""), "the knocking alarmed them")
			step = "burst"
			c.blow()
			check(not c.inside and not p.in_coffin and p.visible and p.rising_t >= 0.0 and p.propped, "not up out of the coffin: rising %.2f" % p.rising_t)
			check(c.lid != null and c.sprite.texture.resource_path.contains("his_coffin_open"), "the lid's still on the box")
			# the blow that broke the lid isn't a knife at whoever's by the box, and a man
			# struck dumb couldn't turn a gun on him if it were
			check(p.knife_cd >= Player.COFFIN_KNIFE - 0.01, "E out of the box is a lunge at once")
			check(_mourners().all(func(e): return not e.can_fire_at(p)), "a man struck dumb could fire point-blank")
			check(int(game.stats.get("struck dumb", 0)) >= 6, "struck dumb: %s" % game.stats.get("struck dumb", 0))
			check(_mourners().all(func(e): return e.reaction == "agape"), "a mourner who wasn't struck dumb")
			check(_mourners().all(func(e): return not e.listening()), "still listening with him out of the box")
			t0 = t
			phase = 1
		1:
			if t - t0 < 1.5:
				return false
			step = "risen"
			check(p.rising_t < 0.0 and not p.propped and p.global_position.distance_to(c.out_at) < 1.0, "still getting out of the box")
			var stares := {}
			for e in _mourners():
				stares[e.stare] = true
			check(stares.size() >= 3, "they all take it the same way: %s" % stares.keys())
			step = "struck dumb"
			check(_mourners().all(func(e): return e.reaction == "agape"), "a mourner came to too soon")
			check(_mourners().all(func(e): return e.cone.visible), "a mourner's cone never came back")
			check(game.enemies.all(func(e): return e.since_shot > 1.4), "somebody fired in the first second and a half")
			check(game.enemies.all(func(e): return e.st != Enemy.St.COMBAT or e.reaction == "agape"), "somebody's fighting already: %s" % [
				game.enemies.filter(func(e): return e.st == Enemy.St.COMBAT and e.reaction != "agape").map(func(e): return e.kind)])
			phase = 2
		2:
			if t - t0 < 4.0 + Coffin.STUN_T.y + 2.0 and not _mourners().all(func(e): return not e.alive or (e.reaction == "" and e.st == Enemy.St.COMBAT)):
				return false
			step = "fumbling"
			check(_mourners().all(func(e): return not e.alive or e.st == Enemy.St.COMBAT), "still standing there: %s" % [_mourners().map(func(e): return e.reaction)])
			check(game.stats.get("comes to", 0) >= 6, "came to: %s" % game.stats.get("comes to", 0))
			check(_mourners().all(func(e): return not e.alive or e.anim_gun == ""), "came to, and still no gun out")
			check(not game.hud.eyes_on and Engine.time_scale == 1.0, "the stand-off close-up took the player's seconds")
			step = "wake"
			for e in game.enemies:   # the cowboy on the cantina's porch, far from it all
				if e.kind == "cowboy":
					far = e
			check(far != null and far.st != Enemy.St.COMBAT, "the cowboy's in it already")
			if far:
				var shot_at: Vector2 = Iso.to_screen(Vector2(59.0, 48.0))   # (out in the street before the cantina)
				game.make_noise(shot_at, 600.0, "shot", game.player)
				check(far.puzzle_t != INF and far.marker == "?" and far.st != Enemy.St.COMBAT, "a shot sent him straight to the fight")
			t0 = t
			phase = 3
		3:
			if far and far.st == Enemy.St.INVESTIGATE and went < 0.0:
				went = t - t0
			if went < 0.0 and t - t0 < Enemy.PUZZLE_T.y + 1.0:
				return false
			check(went >= Enemy.PUZZLE_T.x - 0.1 and went <= Enemy.PUZZLE_T.y + 0.1, "he didn't wander over in time (%.1f s, %s)" % [went, Enemy.St.keys()[far.st] if far else "-"])
			step = "first sight"   # a guest who hasn't seen him yet lays eyes on him: he stares before he fights
			var fresh: Array = game.enemies.filter(func(e): return e.alive and not e.saw_him_risen and e.st != Enemy.St.COMBAT)
			check(not fresh.is_empty(), "everyone's seen him already")
			if not fresh.is_empty():
				var e: Enemy = fresh[0]
				e.enter_combat(game.player.global_position, true, true)
				check(e.reaction == "agape" and e.st != Enemy.St.COMBAT and e.saw_him_risen, "he went straight for his gun: %s %s" % [e.reaction, Enemy.St.keys()[e.st]])
			print("coffin test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
			quit(failures)
			return true
	return false
