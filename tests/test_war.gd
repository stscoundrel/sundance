extends SceneTree
## Silencio's truce, and breaking it (game.weigh_death, game.start_war, Enemy._feuding):
##   truce   - while it holds, the hunter and the trapper face to face on the saloon's
##             porch leave each other be.
##   found   - a hunter finds a comrade knifed, nobody else in town that he knows of:
##             the hunters blame the outlaws, the truce is broken, a banner says so.
##   war     - the porch pair shoot each other; their rounds hurt the other gang now;
##             the gangs' kills aren't the stranger's, and a man who sees one of
##             his own shot down by them doesn't go looking for the stranger over it.
##   dig in  - a gang that's lost a third falls back to its holdout.
##   blame   - each reason on its own: where he lies (the other's ground), the gun
##             (theirs, and not one they've seen the stranger carry), nobody else in
##             town (they haven't seen him); seen, with nothing pointing elsewhere,
##             it's him they blame.
##   godot --headless --path . --fixed-fps 60 -s tests/test_war.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var waited := 0.0
var queue: Array = []
var pair: Array = []
var hp0 := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	Engine.set_meta("no_downed", true)
	seed(13)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED   # (at his horse, out of it)
		_plan()
	if frame <= 3:
		return false
	t += delta
	waited += delta
	if queue.is_empty():
		print("war test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
		else:
			waited = 0.0
	return false


## A man of this gang dead here, killed with this.
func _dead(kind: String, g: String, at: Vector2, with: String) -> Enemy:
	var e: Enemy = game._add_enemy(kind, game.free_point_near(at, 20.0), PackedVector2Array(), 0.0, {"gang": g})
	e.silent_death = with == "knife"   # (a knife in the dark makes no noise: see test_knife)
	e.die(Vector2.RIGHT, game.player)
	e.killed_with = with
	return e


func _plan() -> void:
	queue = [
		[0.0, func():
			return game.state == "play" or waited > 15.0],   # (the level's opening first)
		[0.1, func():
			step = "truce"
			for e in game.enemies:
				var x: float = Iso.to_grid(e.global_position).x
				if x > 24.0 and x < 31.0 and Iso.to_grid(e.global_position).y < 31.0:
					pair.append(e)
			check(pair.size() == 2 and pair[0].gang != pair[1].gang, "the porch pair: %s" % [pair.map(func(e): return e.kind)])
			hp0 = pair.map(func(e): return e.hp).reduce(func(a, b): return a + b, 0)],
		[3.0, func():
			check(not game.war and pair.all(func(e): return e.alive and e.foe == null), "they fell out with the truce on")
			step = "found"
			# a hunter knifed in front of one of his own, nobody else in town that they know of
			var guard: Enemy = game.enemies.filter(func(e): return e.gang == "hunters" and e.kind == "manhunter" \
				and e.st == Enemy.St.GUARD and Iso.to_grid(e.global_position).x > 40.0)[0]
			_dead("manhunter", "hunters", guard.global_position + guard.facing * 40.0, "knife")],
		[0.0, func():
			if not game.war and waited < 5.0:
				return false
			check(game.war, "nobody blamed anybody")
			check(String(game.stats.get("blamed", "")).contains("Nobody else"), "the reason: %s" % game.stats.get("blamed", ""))
			check(game.hud.banner_text.contains("blame the outlaws"), "the banner: %s" % game.hud.banner_text)
			step = "war"],
		[0.0, func():
			var now: int = pair.map(func(e): return e.hp if e.alive else 0).reduce(func(a, b): return a + b, 0)
			if now == hp0 and waited < 12.0:
				return false
			check(now < hp0, "the porch pair never hit each other")
			check(pair.any(func(e): return e.foe != null or not e.alive), "neither has the other as his man")
			check(game.stats.get("his kills", 0) == 1, "%d kills to his name (the knifed man's his)" % game.stats.get("his kills", 0))
			# (the stranger's out of it, at his horse: nobody's fighting him over their dead)
			var at_him: Array = game.enemies.filter(func(e): return e.alive and e.st == Enemy.St.COMBAT)
			check(at_him.is_empty(), "%d went for the stranger over the war's dead: %s" % [at_him.size(), at_him.map(func(e): return e.kind)])],
		[0.1, func():
			step = "dig in"
			game.gangs["outlaws"]["fallen"] += 10],
		[1.0, func():
			check(game.gangs["outlaws"]["dug_in"], "the outlaws didn't dig in")
			var back: Array = game.enemies.filter(func(e): return e.gang == "outlaws" and e.alarm_role == "fortified")
			check(back.size() >= 3, "%d outlaws fell back" % back.size())
			check(not game.gangs["hunters"]["dug_in"], "the hunters dug in too")],
		[0.1, func():
			step = "blame"
			var guard: Enemy = game.enemies.filter(func(e): return e.gang == "hunters" and e.alive)[0]
			var hs: Dictionary = game.gangs["hunters"]
			var cases := [
				# [where, killed with, seen him, his guns, war?, words]
				[Vector2(10, 33), "knife", true, {}, true, "outlaws' ground"],
				[Vector2(33, 33), "navy", true, {}, true, "an outlaw's gun"],
				[Vector2(33, 33), "navy", true, {"navy": true}, false, ""],
				[Vector2(33, 33), "knife", false, {}, true, "Nobody else"],
				[Vector2(33, 33), "knife", true, {}, false, ""],
			]
			for c in cases:
				game.war = false
				game.stats.erase("blamed")
				hs["seen"] = c[2]
				hs["his_guns"] = c[3]
				var d := _dead("manhunter", "hunters", Iso.to_screen(c[0]), c[1])
				game.weigh_death(guard, d)
				check(game.war == c[4], "%s, %s, seen %s: war %s" % [c[0], c[1], c[2], game.war])
				if c[4]:
					check(String(game.stats.get("blamed", "")).contains(c[5]), "the reason: %s" % game.stats.get("blamed", ""))],
	]
