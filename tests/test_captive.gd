extends SceneTree
## Cruz Verde's prisoner at the pole by the well (the rest of the garrison out of
## the fort; no townsfolk but him):
##   setup    - the pole by the well, the man tied to it, the guard (one of the five,
##              off his rounds) standing over him.
##   quiet    - no shot, no countdown: the man's left be. A moment in, the stranger
##              says the level's line ("Vamos a matar, compañeros").
##   executed - the first shot (anyone's), and the guard puts his gun to the man's
##              head and counts; he doesn't stir from the pole, and at ten he shoots
##              him. With the count nearly out the man starts his last words ("Hay
##              que ganar muriendo, pistoleros"), and the shot cuts them off, the
##              broken line left over him a moment. The stranger's told to make the
##              fort pay; the end card says he failed him. The guard stays by the pole.
##   general  - the guard shot dead mid-count, the man halfway into his last words:
##              no execution, and he gets to the end of them. El General comes out and
##              goes straight to the pole, and counts it out himself.
##   cut      - El General counting, the stranger at the pole holds E: the man's
##              loose and runs for the chapel. The end card: saved.
##   rounds   - the stranger's round through the man goes past him; a bandit's
##              doesn't.
##   blast    - dynamite going off close by (well inside a blast's killing core)
##              leaves him standing; one right on him doesn't.
##   godot --headless --path . --fixed-fps 60 -s tests/test_captive.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var queue := ["setup", "quiet", "executed", "general", "cut", "rounds", "blast"]
var t := 0.0
var phase := 0
var mark := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "cruz_verde")
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_alarm", true)
	_fresh()


func _fresh() -> void:
	if game:
		game.queue_free()
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	frame = 0
	t = 0.0
	phase = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func c() -> Captive:
	return game.captive


## A shot somewhere far off: the first of the day.
func _first_shot() -> void:
	game.make_noise(Iso.to_screen(Vector2(-30, -30)), 400.0, "shot", game.player)


func _general() -> Enemy:
	return game._add_enemy("general", Iso.to_screen(Vector2(38.0, 27.0)), PackedVector2Array(), 90.0)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			if e != c().guard:
				e.process_mode = Node.PROCESS_MODE_DISABLED
				e.global_position += Vector2(0, -4000)
		if game.director:
			game.director.process_mode = Node.PROCESS_MODE_DISABLED   # (no sleepers, no waves: we bring the general)
		step = queue[0]
		return false
	if frame < 3:
		return false
	t += delta
	match step:
		"setup":
			check(c() != null, "no prisoner in Cruz Verde")
			check(c().man.bound and c().man.alive and c().man.global_position.distance_to(c().pole) < 20.0,
				"the man isn't tied at the pole")
			check(c().pole.distance_to(Iso.to_screen(Vector2(32.0, 30.0))) < 40.0, "the pole isn't by the well")
			check(c().guard.captor and c().guard.kind == "revolucionario" and c().guard.patrol.is_empty(),
				"no guard taken off his rounds for it")
			check(c().guard.global_position.distance_to(c().man.global_position) < 40.0, "the guard isn't over him")
			check(game.enemies.size() == 5, "the garrison outside should still be five: %d" % game.enemies.size())
			_next()
		"quiet":
			check(c().state == "tied" and c().man.alive, "something happened with nobody firing: %s" % c().state)
			if t > 5.0:
				check(game.said_line and game.player.shout == "Vamos a matar, compañeros", "no opening line: \"%s\"" % game.player.shout)
				_next()
		"executed":
			var g: Enemy = c().guard
			if phase == 0:
				_first_shot()
				phase = 1
				mark = t
			elif phase == 1:
				if t - mark < 0.3:
					return false
				if c().state == "guard":
					check(g.global_position.distance_to(c().spots[0]) < 10.0, "the guard left the man")
					if c().count_t > Captive.LAST_FROM + 0.1:
						check(c().man.shout_t <= 0.0, "his last words already, %.1f s left" % c().count_t)
					elif c().count_t < Captive.LAST_FROM - 0.2:
						check(c().man.shout != "" and Captive.LAST_WORDS.begins_with(c().man.shout), "not saying his last words: \"%s\"" % c().man.shout)
				if not c().man.alive:
					check(c().man.shout == "Hay que ganar murien—" and c().man.last_words and c().man.shout_t > 0.0,
						"his last words not cut off: \"%s\"" % c().man.shout)
					check(absf(t - mark - Captive.COUNT) < 0.5, "shot at %.1f s, not at ten" % (t - mark))
					check("pay" in game.hud.banner_text, "no word to make them pay: %s" % game.hud.banner_text)
					check("shot dead, you failed him" in game._tally(), "the end card: %s" % game._tally())
					phase = 2
					mark = t
				elif t - mark > Captive.COUNT + 2.0:
					check(false, "he was never shot: %s" % c().state)
					_next()
			elif phase == 2:
				g.enter_combat(Iso.to_screen(Vector2(20, 40)), false, false)   # (somewhere off he's no business going)
				phase = 3
			elif phase == 3:
				check(g.global_position.distance_to(g.home) < Enemy.LEASH + 15.0, "the guard wandered off the pole")
				if t - mark > 12.0:
					check(g.global_position.distance_to(g.home) < 10.0, "the guard didn't go back to the pole")
					_next()
		"general":
			if phase == 0:
				_first_shot()
				phase = 1
				mark = t
			elif phase == 1 and t - mark > Captive.COUNT - 1.0:
				check(c().state == "guard", "the guard isn't counting: %s" % c().state)
				check(c().man.shout != "" and c().man.shout != Captive.LAST_WORDS, "not halfway into his last words: \"%s\"" % c().man.shout)
				c().guard.die(Vector2.RIGHT, game.player)
				phase = 2
				mark = t
			elif phase == 2 and t - mark > 1.0:
				check(c().state == "tied" and c().man.alive, "the count went on without him: %s" % c().state)
				check("guard's down" in game.hud.banner_text, "no word the guard's down")
				check(c().man.shout == Captive.LAST_WORDS and c().man.shout_t > 0.0, "didn't get to finish: \"%s\"" % c().man.shout)
				_general()
				phase = 3
				mark = t
			elif phase == 3 and c().state == "general":
				check(c().general.global_position.distance_to(c().spots[1]) < 12.0, "El General isn't at the pole")
				phase = 4
				mark = t
			elif phase == 4 and not c().man.alive:
				check(absf(t - mark - Captive.COUNT) < 0.5, "El General shot him at %.1f s" % (t - mark))
				check(game.stats.get("captive executed by", "") == "general", "not El General's doing")
				_next()
			elif t > 40.0:
				check(false, "stuck at phase %d (%s)" % [phase, c().state])
				_next()
		"cut":
			if phase == 0:
				_first_shot()
				c().guard.die(Vector2.RIGHT, game.player)
				_general()
				phase = 1
			elif phase == 1 and c().state == "general":
				game.player.process_mode = Node.PROCESS_MODE_INHERIT
				game.player.global_position = c().man.global_position + Vector2(-14, 6)
				check(c().can_cut(game.player.global_position), "the pole isn't in reach")
				Input.action_press("knife")
				phase = 2
				mark = t
			elif phase == 2 and c().state == "freed":
				Input.action_release("knife")
				check(t - mark > Captive.CUT_T - 0.1, "cut loose too quickly")
				check(c().man.hid_at == c().chapel, "he isn't making for the chapel")
				check("prisoner: saved" in game._tally(), "the end card: %s" % game._tally())
				game.player.global_position = Iso.to_screen(Vector2(-40, -40))   # (out of El General's way)
				phase = 3
				mark = t
			elif phase == 3 and c().man.gone():
				check(c().man.global_position.distance_to(c().chapel) < 30.0, "he hid somewhere other than the chapel")
				_next()
			elif phase == 3 and not c().man.alive:
				check(false, "he was shot running for it")
				_next()
			elif t > 40.0:
				Input.action_release("knife")
				check(false, "stuck at phase %d (%s)" % [phase, c().state])
				_next()
		"rounds":
			var m: Civilian = c().man
			var from := m.global_position + Vector2(-80, 30)
			if phase == 0:
				game.spawn_bullet(from, (m.global_position - from).normalized() * 900.0, 200.0, 2, game.player,
					Iso.GUN_H, false)
				phase = 1
				mark = t
			elif phase == 1 and t - mark > 0.5:
				check(m.alive, "the stranger's round killed him")
				var bandit: Enemy = game.enemies.filter(func(e): return e != c().guard)[0]
				game.spawn_bullet(from, (m.global_position - from).normalized() * 900.0, 200.0, 2, bandit,
					Iso.GUN_H, false)
				phase = 2
				mark = t
			elif phase == 2 and t - mark > 0.5:
				check(not m.alive, "a bandit's round went past him")
				_next()
		"blast":
			var m: Civilian = c().man
			var bandit: Enemy = game.enemies.filter(func(e): return e != c().guard)[0]
			if phase == 0:
				game.blast(m.global_position + Vector2(24, 8), bandit)
				phase = 1
				mark = t
			elif phase == 1 and t - mark > 0.5:
				check(m.alive and m.bound, "a blast 25 px off killed him")
				game.blast(m.global_position + Vector2(4, 2), bandit)
				phase = 2
				mark = t
			elif phase == 2 and t - mark > 0.5:
				check(not m.alive, "a stick right on him didn't")
				_next()
	return false


func _next() -> void:
	queue.pop_front()
	if queue.is_empty():
		print("captive test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures > 0 else 0)
		return
	_fresh()
