extends SceneTree
## The barber-surgeon (the gang out of the way, the other townsfolk indoors):
##   far      - the stranger hurt but well away from the shop: he stays on his porch.
##   watched  - close by, but a bandit fighting him has him in sight: he stays put.
##   care     - close by and nobody at him: out he comes and binds him up where he
##              stands, faster than a bandage, back to whole, bandage still on him.
##   once     - hurt again: no second time this level.
##   far shot - gunfire across town: he minds his porch.
##   near shot- gunfire close by the shop: in he goes; and he's back out once it's
##              stopped there, though the town's nowhere near quiet.
##   downed   - a bandit down near the shop with none of his own about: the barber
##              kneels by him and gets him back on his feet.
##   godot --headless --path . --fixed-fps 60 -s tests/test_barber.gd

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var step := "far"
var b: Civilian
var p: Player
var watcher: Enemy
var downed: Enemy
var fire_every := 0.0
var fire_t := 0.0
var fire_at := Vector2.ZERO
var went_in := false
var bandages_before := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_reserve", true)
	Engine.set_meta("no_gasp", true)
	seed(3)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _next(s: String) -> void:
	print("%-9s done after %.1f s (%s)" % [step, t, Civilian.St.keys()[b.st]])
	step = s
	t = 0.0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		p = game.player
		p.process_mode = Node.PROCESS_MODE_DISABLED   # (he stands still)
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		for c in game.civilians:
			if c.barber:
				b = c
			else:
				c._go_inside(false)
				c.process_mode = Node.PROCESS_MODE_DISABLED
		check(b != null, "no barber in San Miguel")
		check(b.anim_gun == "barber" and b.has_anim("upper/barber/treat") and b.has_anim("upper/barber/tend"),
			"the barber has no poses for his work")
		p.hp = 2
		p.bleeding = true
		bandages_before = p.bandages
		p.global_position = b.home + Vector2(260, 80)
	if frame <= 3:
		return false
	t += delta
	fire_t -= delta
	if fire_every > 0.0 and fire_t <= 0.0:
		fire_t = fire_every
		game.make_noise(fire_at, 380.0, "enemy_shot", null)
	match step:
		"far":
			check(b.st in [Civilian.St.IDLE, Civilian.St.WALK], "he went out to a man %.0f px off (%s)" % [
				p.global_position.distance_to(b.home), Civilian.St.keys()[b.st]])
			if t > 4.0:
				p.global_position = _beside_door()
				watcher = game.enemies[0]
				watcher.global_position = p.global_position + Vector2(-150, 30)
				watcher.revealed = true
				watcher.st = Enemy.St.COMBAT
				check(game.line_of_sight(watcher.global_position, p.global_position, false), "(the bandit can't see him)")
				_next("watched")
		"watched":
			check(b.st in [Civilian.St.IDLE, Civilian.St.WALK], "he went out under a bandit's gun (%s)" % Civilian.St.keys()[b.st])
			if t > 4.0:
				watcher.global_position += Vector2(0, -4000)
				_next("care")
		"care":
			if p.hp == p.max_hp:
				check(not p.bleeding and p.limp_t <= 0.0, "still bleeding or limping")
				check(p.bandages == bandages_before, "his own bandage went")
				check(t >= Civilian.TREAT_T and t < Player.BANDAGE_T + 4.0, "patched up in %.1f s" % t)
				check(game.stats.get("patched up", 0) == 1, "not counted")
				p.hp = 3
				p.bleeding = true
				_next("once")
			elif t > 20.0:
				check(false, "he never patched him up (%s)" % Civilian.St.keys()[b.st])
				return _done()
		"once":
			check(b.st not in [Civilian.St.TO_PATIENT, Civilian.St.TREAT], "he came out a second time")
			if t > 8.0:
				check(p.hp == 3, "he was patched twice")
				p.global_position = Iso.to_screen(Vector2(-40, -40))
				fire_at = b.home + Vector2(700, 300)
				fire_every = 1.0
				_next("far shot")
		"far shot":
			check(b.st != Civilian.St.GONE and b.st != Civilian.St.FLEE, "he ran from shooting across town")
			if t > 5.0:
				fire_at = b.home + Vector2(120, 50)
				_next("near shot")
		"near shot":
			went_in = went_in or b.st == Civilian.St.GONE
			if went_in and t > 6.0 and fire_at.distance_to(b.home) < 200.0:
				fire_at = b.home + Vector2(700, 300)   # moved off: still going on, across town
				t = 0.0
			elif went_in and fire_at.distance_to(b.home) > 200.0 and b.st in [Civilian.St.IDLE, Civilian.St.WALK]:
				check(game.quiet_for() < 5.0, "(the town was quiet anyway)")
				check(t < Civilian.BACK_T + 6.0, "he took %.1f s to come back out" % t)
				fire_every = 0.0
				_next("downed")
				_down_a_bandit()
			elif t > 40.0:
				check(false, "went in: %s, now %s" % [went_in, Civilian.St.keys()[b.st]])
				return _done()
		"downed":
			if not downed.downed and downed.alive:
				check(game.stats.get("barber saves", 0) == 1, "not counted")
				check(downed.hp == 1, "he should be up with one HP")
				return _done()
			elif not downed.alive and not downed.downed:
				check(false, "the bandit bled out (%s)" % Civilian.St.keys()[b.st])
				return _done()
			elif t > 40.0:
				check(false, "he never saw to the downed man (%s)" % Civilian.St.keys()[b.st])
				return _done()
	return false


## Close by his door, in his sight.
func _beside_door() -> Vector2:
	for r in [40.0, 60.0, 80.0]:
		for k in 12:
			var q: Vector2 = b.home + Vector2.from_angle(k * TAU / 12.0) * r
			if game.is_free(q) and game.line_of_sight(b.home, q, false):
				return q
	return b.home


func _down_a_bandit() -> void:
	for e in game.enemies:
		if e != watcher and not e.tdata.get("concealed", false):
			downed = e
			break
	downed.global_position = _beside_door() + Vector2(30, 20)
	downed.process_mode = Node.PROCESS_MODE_INHERIT
	downed.go_down(Vector2.RIGHT, null)
	check(downed.downed, "the bandit should be down")


func _done() -> bool:
	print("stats: %s" % game.stats)
	print("barber test: " + ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
	return true
