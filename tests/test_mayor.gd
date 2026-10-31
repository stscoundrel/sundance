extends SceneTree
## The mayor (the bandits out of town, the other townsfolk indoors):
##   speech  - gunfire on main street: he hurries out to the plaza and harangues them.
##   cower   - a round cracks past him: down he goes, and stays down while the
##             shooting goes on; once it's calmer he's back up and at it again.
##   hush    - quiet for a while: he steps down.
##   survey  - quieter still: he tours the damage (a shot-up crate, a wagon, a scorch
##             mark), tutting at each, then goes home.
##   godot --headless --path . --fixed-fps 60 -s tests/test_mayor.gd

const FIRE := Vector2(34.0, 31.0)   # main street, by the plaza

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var step := "speech"
var m: Civilian
var fire_every := 2.0
var fire_t := 0.0
var cowered_t := 0.0
var down_while_firing := true


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_reserve", true)
	seed(3)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _next(s: String) -> void:
	print("%-7s done after %.1f s (%s)" % [step, t, Civilian.St.keys()[m.st]])
	step = s
	t = 0.0


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
		for c in game.civilians:
			if c.mayor:
				m = c
			else:
				c._go_inside(false)
		check(m != null, "no mayor in town")
		check(m.anim_gun == "mayor" and m.has_anim("upper/mayor/orate") and m.has_anim("upper/mayor/survey"),
			"the mayor has no speech or survey poses")
	if frame <= 3:
		return false
	t += delta
	fire_t -= delta
	if fire_every > 0.0 and fire_t <= 0.0:
		fire_t = fire_every
		game.make_noise(Iso.to_screen(FIRE), 380.0, "shot", game.player)
	match step:
		"speech":
			if m.st == Civilian.St.ORATE and game.stats.get("mayor speeches", 0) > 0:
				check(m.global_position.distance_to(m.stump) < 30.0, "he speaks %.0f px from his spot" %
					m.global_position.distance_to(m.stump))
				m.near_miss(m.global_position + Vector2(40, 0))
				_next("cower")
			elif t > 25.0:
				check(false, "he never got up to speak (%s)" % Civilian.St.keys()[m.st])
				return _done()
		"cower":
			if t < 6.0:
				down_while_firing = down_while_firing and m.st == Civilian.St.COWER
			elif t < 6.0 + delta:
				check(down_while_firing, "he got up while the shooting went on")
				fire_every = 0.0   # a lull
			elif m.st == Civilian.St.ORATE:
				check(t - 6.0 < 8.0, "it took him %.1f s of calm to get back up" % (t - 6.0))
				_next("hush")
			elif t > 20.0:
				check(false, "he never got back up (%s)" % Civilian.St.keys()[m.st])
				return _done()
		"hush":
			if m.st != Civilian.St.ORATE:
				check(game.quiet_for() >= Civilian.HUSH, "he stepped down after %.1f s of quiet" % game.quiet_for())
				_wreck()
				_next("survey")
			elif t > 15.0:
				check(false, "he never stepped down")
				return _done()
		"survey":
			if t > 90.0:
				var n: int = game.stats.get("damage surveyed", 0)
				print("surveyed %d; %s" % [n, game.stats])
				check(n == 3, "he should have looked at all three wrecks (%d)" % n)
				check(m.st in [Civilian.St.IDLE, Civilian.St.WALK] and m.global_position.distance_to(m.home) < 40.0,
					"he should be home again (%s, %.0f px)" % [Civilian.St.keys()[m.st], m.global_position.distance_to(m.home)])
				return _done()
	return false


## Damage done without a sound (as if long ago in the fight): a shot-up crate, a
## holed wagon, and a scorch mark.
func _wreck() -> void:
	var got := {}
	for prop in game.props:
		if prop["kind"] in ["crate", "wagon"] and not got.has(prop["kind"]) \
				and game.prop_centre(prop).distance_to(m.stump) < 300.0:
			got[prop["kind"]] = true
			prop["hp"] = 1
			prop["state"] = 1
			game._prop_state(prop, 1)
	check(got.size() == 2, "no crate or wagon nearby")
	game._scar(Iso.to_screen(FIRE) + Vector2(10, 20), {})


func _done() -> bool:
	print("mayor test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
