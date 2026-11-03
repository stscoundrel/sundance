extends SceneTree
## Cover that wears. In order:
##   wear     - a crate takes Colt rounds: shot up past half, then a heap of boards
##              that no longer blocks the way or counts as cover.
##   pierce   - a Winchester round goes through a crate, not a barrel; a Sharps
##              through a barrel, not a trough; a Colt through nothing.
##   leak     - a holed trough leaks: the puddle spreads.
##   eyes     - crouched behind a crate, the stranger is hidden from a bandit far off
##              until he fires (and a moment after); one in a fight close by sees him
##              anyway; a calm guard close by doesn't.
##   breakers - hidden behind a crate, two bandits (never more) shoot it to pieces.
##   godot --headless --path . --fixed-fps 60 -s tests/test_cover.gd

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var step := ""
var crate: Dictionary
var trough: Dictionary
var gang: Array[Enemy] = []
var dir := Vector2.ZERO
var marks := 0
var most_breakers := 0
var fire_t := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	seed(3)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _props(kind: String) -> Array:
	return game.props.filter(func(p): return p["kind"] == kind)


## A crate out in the open with a long clear view on one side: (prop, direction).
func _open_crate(skip: Array) -> Array:
	for p in _props("crate"):
		if p in skip:
			continue
		var c: Vector2 = game.prop_centre(p)
		for i in 8:
			var d := Vector2.from_angle(i * TAU / 8.0)
			var far := c + d * 190.0
			if game.is_free(far) and game.is_free(c - d * 16.0) and game.line_of_sight(far, c, false) \
					and game.line_of_sight(c + d * 90.0, c, false):
				return [p, d]
	return []


func _bandit(at: Vector2, face: Vector2, fighting: bool) -> Enemy:
	for e in game.enemies:
		if e.alive and not e in gang and e.kind in ["cowboy", "pistolero", "rifleman", "bandido"]:
			gang.append(e)
			e.global_position = at
			e.facing = face
			e.desired = face
			e.hp = 1000
			if fighting:
				e.enter_combat(game.player.global_position, true, false)
			else:
				e.st = Enemy.St.GUARD
			return e
	return null


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 1000000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		_static_checks()
		step = "leak"
		trough = _props("trough")[0]
		marks = game.decals.splats.size()
		game.hit_prop(trough, game.PROP_HP["trough"] / 2, 0, game.prop_centre(trough))
	if frame <= 3:
		return false
	t += delta
	var p: Player = game.player
	p.weapon.update(delta)
	p.exposed_t = maxf(0.0, p.exposed_t - delta)   # (he's held still: run his clock by hand)
	match step:
		"leak":
			if t > 6.0:
				check(trough["state"] == 1, "the trough should look holed")
				check(game.decals.splats.size() >= marks + 3, "the trough should leak a spreading puddle")
				_start_eyes()
		"eyes":
			_eyes(delta)
		"breakers":
			_breakers(delta)
	return false


func _static_checks() -> void:
	step = "wear"
	var c: Dictionary = _props("crate")[0]
	var cells: Array = c["cells"].duplicate()
	var covers: Array = c["covers"].duplicate()
	var hits := 0
	while c["state"] == 0:
		game.hit_prop(c, 2, 0, game.prop_centre(c))
		hits += 1
	check(c["state"] == 1 and c["hp"] > 0, "a crate should look shot up before it breaks")
	while c["state"] < 2:
		game.hit_prop(c, 2, 0, game.prop_centre(c))
		hits += 1
	print("a crate takes %d Colt rounds" % hits)
	check(hits >= 3 and hits <= 6, "a crate should take a few Colt rounds (%d)" % hits)
	check(c["body"] == null, "a wrecked crate still stops bullets")
	check(cells.all(func(x): return not game.astar.is_point_solid(x) or game._solid.has(x)), "a wrecked crate still blocks the way")
	check(covers.all(func(x): return not x in game.cover_points), "a wrecked crate still counts as cover")
	step = "pierce"
	var cr: Dictionary = _props("crate")[1]
	var ba: Dictionary = _props("barrel")[0]
	var tr: Dictionary = _props("trough")[1]
	check(game.hit_prop(cr, 1, 1, Vector2.ZERO), "a Winchester round should go through a crate")
	check(not game.hit_prop(ba, 1, 1, Vector2.ZERO), "a Winchester round went through a barrel")
	check(game.hit_prop(ba, 1, 2, Vector2.ZERO), "a Sharps round should go through a barrel")
	check(not game.hit_prop(tr, 1, 2, Vector2.ZERO), "a Sharps round went through a trough")
	check(not game.hit_prop(_props("crate")[2], 1, 0, Vector2.ZERO), "a Colt round went through a crate")


func _start_eyes() -> void:
	step = "eyes"
	t = 0.0
	var found := _open_crate([_props("crate")[0], _props("crate")[1], _props("crate")[2]])
	check(not found.is_empty(), "no crate out in the open")
	crate = found[0]
	dir = found[1]
	var c: Vector2 = game.prop_centre(crate)
	var p: Player = game.player
	p.global_position = c - dir * 16.0
	p.crouched = true
	p.facing = dir
	_bandit(c + dir * 190.0, -dir, true)            # far, in a fight
	_bandit(c + dir * 80.0, -dir, true)    # close, in a fight
	_bandit(c + dir * 100.0, -dir, false)  # close, calm
	for e in gang:
		e.process_mode = Node.PROCESS_MODE_DISABLED   # eyes only: we call perceive
		e.st = Enemy.St.COMBAT if e != gang[2] else Enemy.St.GUARD


func _vis(e: Enemy) -> bool:
	return e.visibility_of(game.player.global_position, game.player.low_profile()) > 0.0


func _eyes(_delta: float) -> void:
	var far: Enemy = gang[0]
	var near: Enemy = gang[1]
	var calm: Enemy = gang[2]
	var p: Player = game.player
	if t > 0.1 and t - _delta <= 0.1:
		check(not _vis(far), "a bandit far off sees him crouched behind the crate")
		check(_vis(near), "a bandit in a fight this close should see him over the crate")
		check(not _vis(calm), "a calm guard sees him crouched behind the crate")
		p.facing = Vector2.from_angle(dir.angle() + PI * 0.5)   # a shot off to the side
		p.weapon.trigger()
	if t > 0.3 and t - _delta <= 0.3:
		check(_vis(far), "firing from behind the crate should give him away")
	if t > 1.6 and t - _delta <= 1.6:
		check(not _vis(far), "a moment after firing he should be hidden again")
		_start_breakers()


func _start_breakers() -> void:
	step = "breakers"
	t = 0.0
	var c: Vector2 = game.prop_centre(crate)
	gang[1].global_position = c + dir * 170.0 + dir.orthogonal() * 30.0   # out of reach of the alert eyes
	gang[2].global_position = c + dir * 170.0 - dir.orthogonal() * 30.0
	for e in gang:
		e.process_mode = Node.PROCESS_MODE_INHERIT
		e.enter_combat(game.player.global_position, false, false)
		e.last_known = game.player.global_position
	game.report_sighting(game.player.global_position)


func _breakers(delta: float) -> void:
	var p: Player = game.player
	# he keeps his head down, but every few seconds a shot gives him away again
	fire_t -= delta
	if fire_t <= 0.0:
		fire_t = 3.0
		p.facing = Vector2.from_angle(dir.angle() + PI * 0.5)
		p.weapon.trigger()
		game.report_sighting(p.global_position)
	var n := 0   # the most on any one prop (there may be another crate beside his)
	for prop in game.props:
		n = maxi(n, gang.filter(func(e): return e.suppress_t > 0.0 and e.breaking == prop).size())
	most_breakers = maxi(most_breakers, n)
	if crate["state"] < 2 and t < 40.0:
		return
	print("crate %s after %.1f s; most breakers at once %d; %s" % [["whole", "shot up", "wrecked"][crate["state"]], t, most_breakers, game.stats])
	check(game.stats.get("shoots the cover", 0) > 0, "nobody shot at his cover")
	check(most_breakers <= 2, "too many shooting one prop (%d)" % most_breakers)
	check(crate["state"] == 2, "they never shot his crate to pieces")
	print("cover test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
