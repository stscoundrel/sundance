extends SceneTree
## Reinforcements from the saloon, in three scenes:
##   quiet  - all 25 die without a sound: the town is won and nobody comes out.
##   noise  - shooting at the far end of town doesn't stir the saloon; shooting near
##            it does: five come out of its door, its shutters slam, and the town
##            isn't won until they're dead too.
##   runner - a fight across town: a weak bandit runs for help. Shot on the way,
##            nobody comes; the next one gets through and brings them out.
##   godot --headless --path . --fixed-fps 60 -s tests/test_reinforcements.gd

const SCENES := ["quiet", "noise", "runner"]

var game: Node
var scene_i := -1
var frame := 0
var clock := 0.0
var failures := 0
var step := 0
var step_t := 0.0
var first_runner: Enemy


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_civilians", true)
	_next_scene()


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [SCENES[scene_i], msg])


func _next_scene() -> void:
	if game:
		root.remove_child(game)
		game.free()
	scene_i += 1
	frame = 0
	clock = 0.0
	step = 0
	step_t = 0.0
	seed(4 + scene_i)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _street(x: float) -> Vector2:
	return Iso.to_screen(Vector2(x, 31.4))


func _shoot_at(pos: Vector2, n: int) -> void:
	for i in n:
		game.make_noise(pos, 380.0, "shot", game.player)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 1000000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		check(game.den.has("door"), "no den in town")
		check(game.enemies.size() == 25, "25 bandits on the street (%d)" % game.enemies.size())
	if frame <= 3:
		return false
	clock += delta
	step_t += delta
	var done := false
	match SCENES[scene_i]:
		"quiet":
			done = _quiet()
		"noise":
			done = _noise(delta)
		"runner":
			done = _runner()
	if not done:
		return false
	if scene_i + 1 < SCENES.size():
		_next_scene()
		return false
	print("reinforcements test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true


func _quiet() -> bool:
	for e in game.enemies:
		if e.alive:
			e.die(Vector2.RIGHT)
	if step_t < 5.0:
		return false
	check(game.state == "won", "silencing the 25 should win (%s)" % game.state)
	check(not game.den["rallied"] and game.enemies.size() == 25, "nobody should have come out of a quiet saloon")
	return true


func _noise(delta: float) -> bool:
	var door: Vector2 = game.den["door"]
	for e in game.enemies:
		if e.process_mode != Node.PROCESS_MODE_DISABLED and not e in game.enemies.slice(25):
			e.process_mode = Node.PROCESS_MODE_DISABLED   # the street holds still; we do the shooting
	match step:
		0:   # a running fight at the far end of town: the saloon doesn't hear it
			if int(step_t * 2.0) != int((step_t - delta) * 2.0):
				_shoot_at(_street(56.0), 1)
			if step_t > 12.0:
				check(not game.den["rallied"], "gunfire across town brought the saloon out")
				step = 1
				step_t = 0.0
		1:   # now right outside
			if int(step_t * 2.0) != int((step_t - delta) * 2.0):
				_shoot_at(door + Vector2(60, 30), 1)
			if game.den["rallied"]:
				print("the saloon empties after %.1f s of shooting outside it" % step_t)
				check(game.den["cause"] == "gunfire", "rallied by %s" % game.den["cause"])
				check(step_t < 8.0, "it took %.1f s of shooting outside the door" % step_t)
				step = 2
				step_t = 0.0
			elif step_t > 20.0:
				check(false, "shooting outside the saloon never brought them out")
				return true
		2:
			if step_t > 8.0:
				var out: Array = game.enemies.slice(25)
				check(out.size() == 5, "five should come out (%d)" % out.size())
				for e in out:
					check(e.global_position.distance_to(door) < 160.0, "%s came out far from the door" % e.kind)
					check(e.st == Enemy.St.COMBAT, "%s came out without a fight in him" % e.kind)
				var shut := 0
				var all := 0
				for sh in game.shutters:
					if sh.get_parent() == game.den["sprite"]:
						all += 1
						shut += 1 if sh.shut else 0
				check(all > 0 and shut == all, "the saloon's shutters should slam (%d of %d)" % [shut, all])
				for e in game.enemies.slice(0, 25):
					e.die(Vector2.RIGHT)
				step = 3
				step_t = 0.0
		3:
			if step_t > 2.0 and step < 4:
				check(game.state == "play", "the town was won with the reserve still standing")
				for e in game.enemies:
					if e.alive:
						e.die(Vector2.RIGHT)
				step = 4
				step_t = 0.0
		4:
			if step_t > 2.0:
				check(game.state == "won", "the town should be won once the reserve is dead too (%s)" % game.state)
				return true
	return false


func _runner() -> bool:
	match step:
		0:   # the stranger shows himself at the east end; the fight starts there
			game.player.global_position = _street(58.0)
			for e in game.enemies:
				if e.global_position.distance_to(game.player.global_position) < 300.0:
					e.enter_combat(game.player.global_position, true, false)
			step = 1
			step_t = 0.0
		1:
			var r = game.den["runner"]
			if r != null:
				first_runner = r
				print("first runner: %s, %.0f px from the door" % [r.kind, r.global_position.distance_to(game.den["door"])])
				check(r.kind in ["bandido", "pistolero", "drunkard"], "the runner should be one of the weak (%s)" % r.kind)
				step = 2
				step_t = 0.0
			elif step_t > 20.0:
				check(false, "nobody ran for help")
				return true
		2:   # he's shot down on the way
			if step_t > 1.0:
				first_runner.die(Vector2.RIGHT)
				step = 3
				step_t = 0.0
		3:
			check(not game.den["rallied"], "the saloon came out with its runner dead (%s)" % game.den["cause"])
			if game.den["runner"] != null and game.den["runner"] != first_runner:
				check(step_t > game.RUNNER_CD * 0.8, "the next runner went too soon (%.1f s)" % step_t)
				print("second runner: %s after %.1f s" % [game.den["runner"].kind, step_t])
				step = 4
				step_t = 0.0
			elif step_t > 40.0:
				check(false, "no second runner")
				return true
		4:
			if game.den["rallied"]:
				print("the second runner got through in %.1f s; rallied by %s" % [step_t, game.den["cause"]])
				check(game.den["cause"] == "runner", "rallied by %s, not the runner" % game.den["cause"])
				return true
			if step_t > 90.0:
				check(false, "the second runner never reached the saloon")
				return true
	return false
