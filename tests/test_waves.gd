extends SceneTree
## Waves (the test yard: four in it, three more by the west track at 20 s, then two
## by the west track and two named men by the north track at 40 s):
##   wait     - with the yard cleared before any wave, it isn't won: more are coming;
##              the countdown runs down to them.
##   word     - 15 s before a wave, word of which road they're coming by.
##   quiet    - with nothing going on, the arrivals walk in to the middle of town
##              and spread out there (looking into the bodies they find on the way).
##   fight    - with shooting going on, the next lot go straight to it.
##   won      - once the last wave's in and down, the yard is won.
##   godot --headless --path . --fixed-fps 60 -s tests/test_waves.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var d: Director


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_downed", true)
	Engine.set_meta("level", "test_yard_waves")
	seed(18)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _kill_all() -> void:
	for e in game.enemies:
		if e.alive:
			e.die(Vector2.RIGHT)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		d = game.director
		check(d != null and is_equal_approx(d.next_in(), 20.0), "no waves, or not due at 20 s")
		_wait()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("stats: ", game.stats)
		print("waves test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _wait() -> void:
	step = "wait"
	queue = [
		[1.0, func():
			_kill_all()],
		[1.0, func():
			check(game.state == "play", "won with a wave still to come (%s)" % game.state)
			check(d.next_in() > 17.0 and d.next_in() < 18.5, "the countdown says %.1f" % d.next_in())
			check(d.warned_from().is_empty(), "word came too early")
			step = "word"],
		[3.5, func():
			check(not d.warned_from().is_empty() and d.warned_from()[0]["name"] == "west track",
				"no word of them 15 s out (%.1f s to go)" % d.next_in())
			check(game.hud.banner_text.contains("west track"), "the banner says: %s" % game.hud.banner_text)
			step = "quiet"],
		[17.0, func():
			check(game.stats.get("arrivals", 0) == 3, "%d walked in" % game.stats.get("arrivals", 0))
			check(d.warned_from().is_empty() and d.arriving_from().is_empty(), "still word of the wave that's in")],
		[10.5, func():
			var new: Array = game.enemies.slice(4)
			var mid := Iso.to_screen(Vector2(12.0, 10.5))
			for e in new:
				print("  arrived %s: %s, %.0f px from the middle" % [e.kind, Enemy.St.keys()[e.st], e.global_position.distance_to(mid)])
				check(e.home.distance_to(mid) < 170.0, "his post isn't about the middle of town")
				check(e.global_position.distance_to(mid) < 200.0, "a %s isn't in the middle of town yet" % e.kind)
			check(new.all(func(a): return a.home != new[0].home or a == new[0]), "two given the same spot")
			check(game.stats.get("arrive to a fight", 0) == 0, "they went to a fight that wasn't on")
			step = "fight"
			# shooting before the next lot get here
			_kill_all()
			game.make_noise(Iso.to_screen(Vector2(6, 12)), 380.0, "shot", game.player)],
		[3.0, func():
			game.make_noise(Iso.to_screen(Vector2(6, 12)), 380.0, "shot", game.player)],
		[3.0, func():
			game.make_noise(Iso.to_screen(Vector2(6, 12)), 380.0, "shot", game.player)],
		[4.0, func():
			var new: Array = game.enemies.slice(7)
			check(new.size() == 4, "%d in the second wave" % new.size())
			check(new.map(func(e): return e.kind).has("pistolero") and new.map(func(e): return e.kind).has("bandido"),
				"the named men didn't come")
			check(game.stats.get("arrive to a fight", 0) == 4, "%d went to the fight" % game.stats.get("arrive to a fight", 0))
			check(new.all(func(e): return e.st == Enemy.St.COMBAT), "they didn't go to the shooting")
			check(d.done() and d.next_in() < 0.0, "more still to come")
			check(game.state == "play", "won with them alive")
			step = "won"
			_kill_all()],
		[1.0, func():
			check(game.state == "won", "not won with all in and down (%s)" % game.state)],
	]
