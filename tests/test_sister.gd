extends SceneTree
## The sister (the bandits out of the way, the stranger off the map):
##   inside   - she starts indoors in the church, and Cruz Verde has one in its chapel.
##   shelter  - gunfire near the church: out she comes to the door and calls folk in;
##              a townsman running from shooting nearby makes for her door.
##   back in  - quiet near the church a while: she's back inside.
##   rescue   - the padre shot down, the shooting still going: she runs out, drags
##              him in by the shoulders, and he's gone from the town for good.
##   blessing - once it's quiet, with him gone, she blesses the dead in his place;
##              the end card says only that the padre is in God's hands.
##   godot --headless --path . --fixed-fps 60 -s tests/test_sister.gd

const QUIET := 8.0

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var step := "inside"
var sis: Civilian
var padre: Civilian
var runner: Civilian
var dead: Enemy
var fire_every := 0.0
var fire_t := 0.0
var fire_at := Vector2.ZERO
var saw_drag := false


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
	print("%-8s done after %.1f s (%s)" % [step, t, Civilian.St.keys()[sis.st]])
	step = s
	t = 0.0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.quiet_after = QUIET
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		for c in game.civilians:
			if c.sister:
				sis = c
			elif c.priest:
				padre = c
			elif runner == null and c.kind == "townsman":
				runner = c
			else:
				c._go_inside(false)
				c.process_mode = Node.PROCESS_MODE_DISABLED   # (no undertaker to take the dead first)
		check(sis != null and padre != null and runner != null, "no sister, padre or townsman in town")
		check(sis.anim_gun == "nun" and sis.has_anim("upper/nun/beckon") and sis.has_anim("upper/nun/drag")
			and sis.has_anim("upper/nun/bless"), "the sister has no beckoning, hauling or blessing poses")
		var cv: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cruz_verde.json"))
		check(cv["civilians"].any(func(c): return c["kind"] == "sister"), "no sister in Cruz Verde's chapel")
		fire_at = sis.home + Vector2(-150, 60)
	if frame <= 3:
		return false
	t += delta
	fire_t -= delta
	if fire_every > 0.0 and fire_t <= 0.0:
		fire_t = fire_every
		game.make_noise(fire_at, 380.0, "enemy_shot", null)
	match step:
		"inside":
			check(sis.st == Civilian.St.GONE and not sis.visible, "she should start indoors (%s)" % Civilian.St.keys()[sis.st])
			if t > 1.0:
				fire_every = 1.5
				_next("shelter")
		"shelter":
			if sis.st == Civilian.St.SHELTER and sis.global_position.distance_to(sis.home) < 8.0:
				check(sis.visible, "she's at the door but can't be seen")
				# a townsman between the shooting and the church runs for it
				runner.global_position = sis.home + Vector2(-110, 40)
				runner.st = Civilian.St.IDLE
				runner.alarm(fire_at, false)
				check(runner.st != Civilian.St.FLEE or runner.hid_at.distance_to(sis.home) < 30.0,
					"he ran for a door %.0f px from hers" % runner.hid_at.distance_to(sis.home))
				_next("back in")
				fire_every = 0.0
			elif t > 8.0:
				check(false, "she never came to the door (%s)" % Civilian.St.keys()[sis.st])
				return _done()
		"back in":
			if sis.st == Civilian.St.GONE:
				check(t > Civilian.SHELTER_FOR - 2.0, "she went in after only %.1f s" % t)
				_kill_padre()
				fire_every = 1.2   # and it's still going on
				_next("rescue")
			elif t > Civilian.SHELTER_FOR + 8.0:
				check(false, "she never went back in (%s)" % Civilian.St.keys()[sis.st])
				return _done()
		"rescue":
			saw_drag = saw_drag or sis.st == Civilian.St.CARRY_IN
			if padre.has_meta("taken_in"):
				check(saw_drag, "she never dragged him")
				check(sis.st == Civilian.St.GONE, "she should be inside with him (%s)" % Civilian.St.keys()[sis.st])
				fire_every = 0.0
				_lay_out_a_bandit()
				_next("blessing")
			elif t > 30.0:
				check(false, "she never got the padre in (%s)" % Civilian.St.keys()[sis.st])
				return _done()
		"blessing":
			if t > 1.0 and t - delta <= 1.0:
				check(not padre.visible, "the padre's still lying there")
				check(padre.has_meta("buried"), "the padre should be out of the story")
			if dead.has_meta("blessed"):
				check(game.stats.get("blessings", 0) >= 1, "no blessing counted")
				var card: String = game._tally()
				check("in God's hands" in card, "the end card doesn't mention the padre: " + card)
				check(not "dead" in card and not "killed" in card, "the end card gives his fate away: " + card)
				print("card: " + card)
				return _done()
			elif t > 60.0:
				check(false, "she never blessed the dead bandit (%s)" % Civilian.St.keys()[sis.st])
				return _done()
	return false


## The padre a few steps up the alley from his church door, and a round from the stranger's direction.
func _kill_padre() -> void:
	padre.global_position = Iso.to_screen(Vector2(30.6, 6.6))   # up the alley from the church door
	padre.take_hit(5, Vector2.RIGHT, game.player)
	check(not padre.alive, "the padre should be dead")


## A dead bandit by the church, where she'll find him.
func _lay_out_a_bandit() -> void:
	for e in game.enemies:
		if e.alive and not e.tdata.get("concealed", false):
			dead = e
			break
	dead.global_position = game.free_point_near(sis.home + Vector2(-60, 70), 20.0)
	dead.process_mode = Node.PROCESS_MODE_INHERIT
	Engine.set_meta("no_downed", true)
	dead.take_hit(10, Vector2.RIGHT, null)
	Engine.remove_meta("no_downed")
	check(not dead.alive, "the bandit should be dead")


func _done() -> bool:
	print("stats: %s" % game.stats)
	print("sister test: " + ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(failures)
	return true
