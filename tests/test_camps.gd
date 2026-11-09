extends SceneTree
## Silencio's camps and the street war's flanks (Director: camps; game.war_line):
##   runner  - the hunters down to their last three: the one nearest their camp
##             runs for it, a banner says so, and he goes off the map there.
##   camp    - their five come back in by the same way, new blood: the gang's no
##             longer dug in, and the level isn't over while they're coming.
##   stopped - the outlaws down to three: their runner shot on the way, and no
##             help comes.
##   flanks  - each gang's pushes go by turns up main street, the north street and
##             the south street.
##   godot --headless --path . --fixed-fps 60 -s tests/test_camps.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var waited := 0.0
var queue: Array = []
var runner: Enemy


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	Engine.set_meta("no_alarm", true)
	Engine.set_meta("no_downed", true)
	seed(19)
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
		print("camps test: ", "OK" if failures == 0 else "%d failures" % failures)
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


## All of this gang dead but the `keep` nearest this spot.
func _thin(g: String, keep: int, near: Vector2) -> void:
	var men: Array = game.enemies.filter(func(e): return e.alive and e.gang == g)
	men.sort_custom(func(a, b): return a.global_position.distance_to(near) < b.global_position.distance_to(near))
	for e in men.slice(keep):
		e.die(Vector2.RIGHT, game.player)


func _plan() -> void:
	var d: Director = game.director
	queue = [
		[0.0, func():
			return game.state == "play" or waited > 15.0],   # (the level's opening first)
		[0.0, func():
			step = "flanks"
			check(d != null and d.camps.size() == 2, "a director with two camps")
			for g in ["hunters", "outlaws"]:
				var seen := {}
				for i in 3:
					seen[Iso.to_grid(game.war_line(g)).y] = true
				check(seen.size() == 3, "%s should push by turns to three lines (%s)" % [g, seen.keys()])
			step = "runner"
			_thin("hunters", 3, d.camps["hunters"]["at"])
			return true],
		[0.0, func():
			if d.camps["hunters"]["state"] == "" and waited < 3.0:
				return false
			check(d.camps["hunters"]["state"] == "running", "a hunter should be running for the camp")
			runner = d.camps["hunters"]["runner"]
			check(runner != null and runner.camp_to != Vector2.INF, "the runner has his camp")
			check(not d.done(), "not over while he's running")
			return true],
		[0.0, func():
			if d.camps["hunters"]["state"] == "running" and waited < 40.0:
				return false
			check(d.camps["hunters"]["state"] == "fetching", "he should have got there (%s)" % d.camps["hunters"]["state"])
			check(not is_instance_valid(runner) or not runner in game.enemies, "off the map")
			check(game.alive_in("hunters") == 2, "two left in town, got %d" % game.alive_in("hunters"))
			step = "camp"
			game.gangs["hunters"]["dug_in"] = true
			d.camps["hunters"]["due"] = d.clock + 0.5   # (no need to sit out the whole wait)
			return true],
		[0.0, func():
			if game.alive_in("hunters") < 7 and waited < 15.0:
				return false
			check(game.alive_in("hunters") == 7, "five more hunters in from the camp, got %d" % game.alive_in("hunters"))
			check(not game.gangs["hunters"]["dug_in"], "new blood: no longer dug in")
			check(d.camps["hunters"]["state"] == "sent", "sent")
			step = "stopped"
			_thin("outlaws", 3, d.camps["outlaws"]["at"])
			return true],
		[0.0, func():
			if d.camps["outlaws"]["state"] != "running" and waited < 3.0:
				return false
			check(d.camps["outlaws"]["state"] == "running", "an outlaw should be running for the camp")
			var r: Enemy = d.camps["outlaws"]["runner"]
			r.die(Vector2.RIGHT, game.player)
			return true],
		[1.0, func():
			check(d.camps["outlaws"]["state"] == "lost", "the runner shot: no help (%s)" % d.camps["outlaws"]["state"])
			check(game.alive_in("outlaws") == 2, "two outlaws left, got %d" % game.alive_in("outlaws"))
			check(d.done(), "nothing more coming")
			return true],
	]
