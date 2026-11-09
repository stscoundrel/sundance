extends SceneTree
## The stranger's two-shot sidearms on the loadout's sidearm card, the howdah for a
## point and the derringer free (the test yard, its gang parked out of the way):
##   card     - both on the sidearm card, after the Navy.
##   derringer- rides in his sidearm slot, its rounds on his belt; two shots, cocked
##              each time, then the barrels up and two more in off the belt.
##   howdah   - the right trigger lets both barrels go at once.
##   dead     - a dead gambler's derringer is his for an F, but there are no rounds
##              lying by it.
##   godot --headless --path . --fixed-fps 60 -s tests/test_sidearms.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var gun: Dictionary = {}


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	seed(7)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _time(w: Weapon, until: Callable, limit := 30.0) -> float:
	var s := 0.0
	while not until.call() and s < limit:
		w.update(0.02)
		s += 0.02
	return s


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		var p: Player = game.player
		p.hp = 100000
		p.process_mode = Node.PROCESS_MODE_DISABLED   # (stood where he's put)
		p.global_position = Iso.to_screen(Vector2(12, 12))
		for e in game.enemies:   # (out of the way, alive: or the yard's won)
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position = Iso.to_screen(Vector2(1.5, 22.5))
		_card()
		_plan()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("sidearms test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


func _card() -> void:
	step = "card"
	var side := Player.choices("colt")
	for k in ["derringer", "howdah"]:
		check(k in side and side.find(k) > side.find("navy"), "the %s isn't on the sidearm card after the Navy (%s)" % [k, side])
	check(Player.cost(["howdah"]) == 1 and Player.cost(["derringer"]) == 0,
		"the howdah costs %d, the derringer %d" % [Player.cost(["howdah"]), Player.cost(["derringer"])])


func _plan() -> void:
	var p: Player = game.player
	queue = [
		[0.2, func():
			step = "derringer"
			p.arm(["derringer"])
			var w: Weapon = p.weapons["colt"]
			check(w.kind == "derringer" and "colt" in p.owned, "no derringer in his sidearm slot")
			check(p.belt.get("derringer", 0) == Player.RESERVE["derringer"], "its rounds aren't on his belt (%s)" % p.belt)
			p.switch_to("colt")
			p.switch_t = 0.0
			var shots := 0
			for i in 3:
				_time(w, func(): return w.state == Weapon.S.READY)
				if w.can_fire():
					w.trigger()
					shots += 1
			check(shots == 2, "%d shots out of a derringer" % shots)
			_time(w, func(): return w.state == Weapon.S.READY)
			check(w.needs_reload(), "a fired-off derringer doesn't want loading")
			w.start_reload()
			var took := _time(w, func(): return w.state == Weapon.S.READY and w.loaded() == 2)
			check(w.loaded() == 2 and p.belt["derringer"] == Player.RESERVE["derringer"] - 2,
				"reloaded %d off the belt (%d left)" % [w.loaded(), p.belt["derringer"]])
			print("  two shots, and two more in in %.1f s" % took)],
		[0.1, func():
			step = "howdah"
			p.arm(["howdah"])
			var w: Weapon = p.weapons["colt"]
			p.switch_to("colt")
			p.switch_t = 0.0
			check(w.kind == "howdah" and w.loaded() == 2, "no loaded howdah in his hand")
			w.alt_trigger()
			check(w.loaded() == 0, "the right trigger left %d barrels loaded" % w.loaded())],
		[0.1, func():
			step = "dead"
			p.arm(["colt"])
			var at: Vector2 = p.global_position + Vector2(60, 20)
			if not game.is_free(at):
				at = game.free_point_near(at, 30.0)
			var e: Enemy = game._add_enemy("gambler", at, PackedVector2Array(), 0.0, {"concealed": false})
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.die(Vector2.RIGHT, p)
			for g in game.loose_guns:
				if g["under"] == e:
					gun = g
			check(not gun.is_empty() and gun["kind"] == "derringer", "the gambler left no derringer")
			check(gun["ammo"] == null, "rounds lying by a derringer")],
		[0.1, func():
			p.process_mode = Node.PROCESS_MODE_INHERIT
			p.global_position = gun["at"]],
		[0.3, func():
			check(p.weapons["colt"].kind == "colt", "walked over the derringer and it swapped without F")
			check(game.at_feet == gun, "the derringer at his feet isn't the one he'd take up")
			game.swap_gun()
			check(p.weapons["colt"].kind == "derringer", "the derringer's not in his sidearm slot")],
	]
