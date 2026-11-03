extends SceneTree
## Bandages and blood (the bandits held still and out of town unless in a scene):
##   stranger - wounded, he leaves a trail of blood as he moves. Bandaging takes ten
##              seconds; a hit breaks it off (he keeps the bandage); done, it gives
##              two bars back, ends the limp and the bleeding, and uses it up. With
##              none left, he can't.
##   trail    - a guard comes across the stranger's fresh blood and follows it up
##              an alley to where he's crouched.
##   patch    - a wounded bandit breaks off into cover, bandages himself (one HP
##              back, no more bleeding) and bleeds on the way there.
##   abort    - one patching himself up gives it up when the stranger walks up on him.
##   weak     - bandidos and drunks have no bandages.
##   godot --headless --path . --fixed-fps 60 -s tests/test_bandage.gd

const HIDE := Vector2(35.5, 22.8)    # up the alley between the hotel and the bank
const MOUTH := Vector2(35.5, 28.9)
const GUARD := Vector2(35.5, 33.0)
const STREET := Vector2(26.0, 31.4)

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var used: Array[Enemy] = []
var route: Array[Vector2] = []
var walk_t := -1.0
var e: Enemy
var drops0 := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	seed(8)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _take(kind: String) -> Enemy:
	for x in game.enemies:
		if x.alive and not x in used and x.kind == kind:
			used.append(x)
			return x
	return null


func _away() -> void:
	for x in used:
		x.process_mode = Node.PROCESS_MODE_DISABLED
		x.global_position += Vector2(0, -4000)


func _drops(player: bool) -> int:
	return game.trails.filter(func(d): return d["player"] == player).size()


func _process(delta: float) -> bool:
	frame += 1
	var p: Player = game.player
	if frame == 3:
		game.begin()
		game.alerted_once = true
		for x in game.enemies:
			x.process_mode = Node.PROCESS_MODE_DISABLED
			x.global_position += Vector2(0, -4000)
		_stranger()
	if frame <= 3:
		return false
	t += delta
	if walk_t >= 0.0:   # walking him along a route, by hand, 40 px/s
		walk_t += delta
		var d := walk_t * 40.0
		var i := 0
		while i < route.size() - 1 and d > route[i].distance_to(route[i + 1]):
			d -= route[i].distance_to(route[i + 1])
			i += 1
		if i >= route.size() - 1:
			p.global_position = route[-1]
			walk_t = -1.0
		else:
			p.global_position = route[i].move_toward(route[i + 1], d)
	if queue.is_empty():
		print("stats: ", game.stats)
		print("bandage test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _stranger() -> void:
	step = "stranger"
	var p: Player = game.player
	p.global_position = Iso.to_screen(STREET)
	p.hp = 4
	var shooter := _take("cowboy")
	check(not p.bleeding, "bleeding before he's hurt")
	p.take_hit(1, Vector2.RIGHT, shooter)
	check(p.bleeding and p.hp == 3, "a hit should leave him bleeding")
	route = [p.global_position, p.global_position + Vector2(80, 0)]
	walk_t = 0.0
	queue = [
		[2.5, func():
			check(_drops(true) >= 4, "too little blood behind him (%d drops)" % _drops(true))
			check(p.start_bandage(), "he couldn't start bandaging")],
		[3.0, func():
			check(p.bandage_t > 2.5, "not bandaging (%.1f)" % p.bandage_t)
			p.take_hit(1, Vector2.RIGHT, shooter)
			check(p.bandage_t < 0.0 and p.bandages == 1 and p.hp == 2, "a hit should break it off and leave him the bandage")
			check(p.start_bandage(), "he couldn't start again")],
		[6.0, func():
			check(p.hp == 2 and p.bandage_t > 0.0, "done too soon")],
		[4.3, func():
			check(p.hp == 4 and not p.bleeding and p.limp_t <= 0.0 and p.bandages == 0,
				"after ten seconds: hp %d, bleeding %s, bandages %d" % [p.hp, p.bleeding, p.bandages])
			check(p.bandage_t < 0.0 and p.pose == "", "still at it")
			check(not p.start_bandage(), "bandaging with none left")
			p.crouched = false
			drops0 = _drops(true)
			route = [p.global_position, p.global_position + Vector2(-80, 0)]
			walk_t = 0.0],
		[2.5, func():
			check(_drops(true) == drops0, "still bleeding after the bandage")
			_trail()],
	]


func _trail() -> void:
	step = "trail"
	var p: Player = game.player
	p.hp = 100000   # (the guard will find him, and shoot)
	p.bleeding = true
	p.bandages = 1
	game.trails.clear()
	game.clock += 100.0   # (the old drops are long cold)
	e = _take("rifleman")
	e.global_position = Iso.to_screen(GUARD)
	e.home = e.global_position
	e.home_facing = (Iso.to_screen(MOUTH) - e.global_position).normalized()
	e.facing = e.home_facing
	e.desired = e.facing
	e.st = Enemy.St.GUARD
	e.patrol = PackedVector2Array()
	p.global_position = Iso.to_screen(Vector2(29.0, 30.0))
	route = [p.global_position, Iso.to_screen(MOUTH), Iso.to_screen(HIDE)]
	walk_t = 0.0
	p.crouched = true
	queue.append([7.0, func():
		check(walk_t < 0.0, "still walking")
		e.process_mode = Node.PROCESS_MODE_INHERIT])   # he looks up: blood in the street
	queue.append([25.0, func():
		print("trail: %s; %.0f px from him; %s" % [Enemy.St.keys()[e.st], e.global_position.distance_to(p.global_position),
			game.stats.get("follows the blood", 0)])
		check(game.stats.get("follows the blood", 0) > 0, "the guard never followed the blood")
		check(e.st == Enemy.St.COMBAT or e.global_position.distance_to(p.global_position) < 70.0,
			"the trail didn't lead him to the stranger")
		_patch()])


func _patch() -> void:
	step = "patch"
	_away()
	var p: Player = game.player
	p.bleeding = false
	p.crouched = false
	p.global_position = Iso.to_screen(STREET)
	e = _take("cowboy")
	e.global_position = Iso.to_screen(STREET + Vector2(9.0, 0))
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.hp = 2
	e.max_hp = 2
	e.tdata["patch"] = 100.0   # (he will)
	e.enter_combat(p.global_position, true, false)
	p.global_position = Iso.to_screen(Vector2(-40, -40))   # gone again
	e.take_hit(1, Vector2.LEFT, p)
	drops0 = _drops(false)
	queue.append([1.0, func():
		check(e.reaction == "patch", "he didn't break off to patch up (%s)" % e.reaction)])
	queue.append([16.0, func():
		check(e.hp == 2 and e.bandages == 0 and not e.bleeding, "patched: hp %d, bandages %d, bleeding %s" %
			[e.hp, e.bandages, e.bleeding])
		check(game.stats.get("patches up", 0) == 1, "no patching counted")
		check(_drops(false) > drops0, "he left no blood on the way")
		_abort()])


func _abort() -> void:
	step = "abort"
	_away()
	var p: Player = game.player
	e = _take("cowboy")
	e.global_position = Iso.to_screen(STREET + Vector2(9.0, 0))
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.hp = 2
	e.max_hp = 2
	e.tdata["patch"] = 100.0
	e.enter_combat(p.global_position, false, false)
	e.take_hit(1, Vector2.LEFT, p)
	queue.append([0.1, func(): _wait_patching(0.0)])


func _wait_patching(waited: float) -> void:
	if not e.patching and waited < 10.0:
		queue.push_front([0.2, func(): _wait_patching(waited + 0.2)])
		return
	check(e.patching, "he never got down to patching")
	var p: Player = game.player
	p.crouched = false
	for a in [0.0, 0.3, -0.3, 0.6, -0.6]:   # right in front of him, in plain view
		var at: Vector2 = e.global_position + e.facing.rotated(a) * 60.0
		if game.is_free(at) and game.line_of_sight(e.global_position, at, false):
			p.global_position = at
			break
	queue.push_front([1.0, func():
		check(not e.patching and e.hp == 1, "he went on patching with the stranger on him")
		check(game.stats.get("gives up patching", 0) == 1, "no giving up counted")
		_weak()])


func _weak() -> void:
	step = "weak"
	for k in ["bandido", "drunkard"]:
		check(int(game.enemy_type(k)["bandages"]) == 0, "a %s carries bandages" % k)
	check(int(game.enemy_type("cowboy")["bandages"]) == 1, "a cowboy has none")
