extends SceneTree
## Shutters. The bandits are held still; the hero is moved by hand.
##   1. He creeps crouched down the middle of main street: hardly a shutter moves.
##   2. He walks it upright: the ones he passes slam, ahead of him, the far end of
##      town stays open.
##   3. A shot on the south side slams the shutters within earshot of it.
##   4. He leaves town and it goes quiet: the shutters creak open again.
##   godot --headless --path . --fixed-fps 60 -s tests/test_shutters.gd

const QUIET := 6.0

var game: Node
var frame := 0
var failures := 0
var clock := 0.0
var phase := 0
var phase_t := 0.0
var open_at_start: Array[Shutter] = []
var counts := {}


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_civilians", true)
	seed(2)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _shut(near: Vector2, within: float) -> Array:
	var n := 0
	var of := 0
	for s in open_at_start:
		if s.at.distance_to(near) < within:
			of += 1
			n += 1 if s.shut else 0
	return [n, of]


func _street(x: float) -> Vector2:
	return Iso.to_screen(Vector2(x, 31.4))


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.quiet_after = QUIET
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.hp = 1000000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		for s in game.shutters:
			if not s.shut:
				open_at_start.append(s)
		print("%d shutters, %d open" % [game.shutters.size(), open_at_start.size()])
		check(open_at_start.size() > game.shutters.size() / 2, "most shutters should start open")
	if frame <= 3:
		return false
	clock += delta
	phase_t += delta
	var p: Player = game.player
	match phase:
		0:   # creeping, crouched, along the middle of main street
			p.crouched = true
			p.global_position = _street(4.0 + phase_t * 2.0)
			if phase_t > 14.0:
				counts["crept"] = _shut(_street(18), 2000.0)[0]
				print("crept down main street: %d shut" % counts["crept"])
				_next()
		1:   # walking it, west half only
			p.crouched = false
			p.global_position = _street(4.0 + phase_t * 2.0)
			if phase_t > 10.0:
				var west := _shut(_street(14), 180.0)
				var east := _shut(_street(56), 140.0)
				print("walked to x=24: west end %d of %d shut, east end %d of %d" % [west[0], west[1], east[0], east[1]])
				check(west[0] >= west[1] / 2, "the shutters he walked past should mostly slam")
				check(east[0] == 0, "the far end of town shouldn't hear him walking")
				check(counts["crept"] < west[0], "creeping should be noticed far less than walking")
				_next()
		2:   # a shot on the south side
			if phase_t < delta * 1.5:
				var at := Iso.to_screen(Vector2(40.0, 44.0))
				game.make_noise(at, 380.0, "shot", p)
				counts["shot_at"] = at
			if phase_t > 3.0:
				var near := _shut(counts["shot_at"], 200.0)
				print("after the shot: %d of %d shut nearby" % [near[0], near[1]])
				check(near[1] > 0 and near[0] == near[1], "every shutter near the shot should slam")
				p.global_position = Iso.to_screen(Vector2(-30, -30))   # he rides out
				_next()
		3:   # quiet: they open again
			if phase_t > QUIET + 60.0:
				var still := 0
				for s in game.shutters:
					still += 1 if s.shut else 0
				print("a minute after the quiet: %d of %d still shut" % [still, game.shutters.size()])
				check(still < game.shutters.size() / 2, "shutters should open again once it's quiet")
				print("shutters test: ", "OK" if failures == 0 else "%d failures" % failures)
				quit(1 if failures else 0)
				return true
	return false


func _next() -> void:
	phase += 1
	phase_t = 0.0
