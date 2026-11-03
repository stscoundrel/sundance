extends SceneTree
## Dynamite. One scene at a time on open main street (everyone else held still,
## out of town):
##   carriers - the bandit types carry a stick; cowboys, gamblers, saloon girls,
##              El Jefe and the gunslinger don't. A drunk may fumble his.
##   rules    - no stick for a spot he's killed only one from, nor with a comrade
##              near it, nor too close, nor while one's lit or just after a blast.
##   throw    - he's killed two from here and keeps firing: a rifleman lights one and
##              it comes down by him, a ring round it; 4-5 s on, it blows and hurts him; then
##              nobody lights another for a good while.
##   blast    - right on top of it a bandit is flung dead; one further off is hurt;
##              one round a corner isn't; a crate near it is blown apart.
##   dropped  - a thrower shot dead winding up: it blows by his body, and the man
##              next to him gets clear and lives.
##   wounded  - a thrower winged winding up lets go of it and runs: he lives.
##   godot --headless --path . --fixed-fps 60 -s tests/test_dynamite.gd

const SPOT := Vector2(26.0, 31.4)   # open main street
const SCENES := ["carriers", "rules", "throw", "blast", "dropped", "wounded"]

var game: Node
var frame := 0
var failures := 0
var scene_i := -1
var t := 0.0
var used: Array[Enemy] = []
var a: Enemy
var b: Enemy
var hp0 := 0
var blasts0 := 0
var lit_t := -1.0
var land_d := -1.0
var land_t := -1.0
var ground_s := -1.0
var ringed := false
var cleared := false
var blew_at := Vector2.INF
var second := false


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	seed(6)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [SCENES[scene_i], msg])


func _take(kind: String) -> Enemy:
	for e in game.enemies:
		if e.alive and not e in used and e.kind == kind:
			used.append(e)
			return e
	return null


func _here(dx := 0.0) -> Vector2:
	return Iso.to_screen(SPOT + Vector2(scene_i * 7.0, 0)) + Vector2(dx, 0)


## A bandit on the street, in the fight, and live (or held still).
func _stand(e: Enemy, at: Vector2, live: bool, hp := 1000) -> void:
	e.global_position = at
	e.hp = hp
	e.max_hp = hp
	e.process_mode = Node.PROCESS_MODE_INHERIT if live else Node.PROCESS_MODE_DISABLED
	e.enter_combat(game.player.global_position, true, false)
	e.reaction = ""
	e.pending = ""


func _next() -> void:
	scene_i += 1
	t = 0.0
	b = null
	for e in used:
		if e.alive:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -3000)
	game.dyn_cd = 0.0
	game.fire_spots.clear()
	var p: Player = game.player
	p.global_position = _here()
	hp0 = p.hp
	blasts0 = game.stats.get("blasts", 0)
	match SCENES[scene_i]:
		"carriers":
			var want := {"pistolero": 1, "bandido": 1, "oldtimer": 1, "rifleman": 1, "redscarf": 1, "poacher": 1,
				"hillbilly": 1, "drunkard": 1, "cowboy": 0, "gambler": 0, "saloon_girl": 0, "jefe": 0, "gunslinger": 0}
			for e in game.enemies:
				check(e.sticks == want.get(e.kind, -1), "a %s carries %d sticks" % [e.kind, e.sticks])
			check(float(game.enemy_type("drunkard")["fumble"]) > 0.0, "a drunk never fumbles")
		"rules":
			a = _take("rifleman")
			_stand(a, _here(150.0), false)
			b = _take("pistolero")
			_stand(b, _here(-3000.0), false)
		"throw":
			a = _take("rifleman")
			_stand(a, _here(150.0), true)
			a.sticks = 3   # so there's one to spare for the cooldown
		"blast":
			pass
		"dropped", "wounded":
			a = _take("bandido")
			_stand(a, _here(150.0), true)
			if SCENES[scene_i] == "dropped":
				b = _take("bandido")
				_stand(b, _here(150.0) + Vector2(0, 30), true)
			a.throw_at = p.global_position
			a.sticks = 1
			a.start_reaction("throw")


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.alerted_once = true   # (no slow-motion stand-off)
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -3000)
		game.player.hp = 1000000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		_next()
	if frame <= 3:
		return false
	t += delta
	var done := true
	match SCENES[scene_i]:
		"rules":
			_rules()
		"throw":
			done = _throw(delta)
		"blast":
			_blast()
		"dropped", "wounded":
			done = _dropped(delta)
	if not done:
		return false
	if scene_i + 1 < SCENES.size():
		_next()
		return false
	print("stats: ", game.stats)
	print("dynamite test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true


func _spot(kills: int) -> void:
	var at: Vector2 = game.player.global_position
	game._note_fire(at)
	game.spot_at(at)["kills"] = kills
	game.report_sighting(at)


func _rules() -> void:
	var at: Vector2 = game.player.global_position
	_spot(1)
	check(game.dynamite_target(a) == Vector2.INF, "a stick for a spot with one kill")
	_spot(2)
	check(game.dynamite_target(a) == at, "no stick for a spot with two kills")
	b.global_position = at + Vector2(40, 0)
	check(game.dynamite_target(a) == Vector2.INF, "a stick at a spot with his comrade by it")
	b.global_position += Vector2(0, -3000)
	var far := a.global_position
	a.global_position = at + Vector2(60, 0)
	check(game.dynamite_target(a) == Vector2.INF, "a stick thrown from %.0f px" % 60.0)
	a.global_position = far
	game.dyn_cd = 5.0
	check(game.dynamite_target(a) == Vector2.INF, "a stick just after a blast")
	game.dyn_cd = 0.0
	game.clock += 30.0
	game.report_sighting(at)
	check(game.dynamite_target(a) == Vector2.INF, "a stick for a spot he's long stopped firing from")


func _throw(delta: float) -> bool:
	if int(t / 2.0) != int((t - delta) / 2.0) or t <= delta:
		_spot(2)   # he keeps shooting from here
	if lit_t < 0.0 and not game.lit.is_empty():
		lit_t = t
	for d in game.lit:
		if d.landed and land_d < 0.0:
			land_t = t
			land_d = d.global_position.distance_to(game.player.global_position)
		ringed = ringed or d.landed
	if game.stats.get("blasts", 0) > blasts0 and blew_at == Vector2.INF:
		blew_at = game.player.global_position
		ground_s = t - land_t
		t = 100.0   # (from now on: the cooldown)
	if t >= 100.0 and t < 115.0 and not game.lit.is_empty():
		second = true
	if t < 12.0 or (t >= 100.0 and t < 115.0):
		return false
	print("lit after %.1f s, came down %.0f px from him, blew %.1f s later; hp %d -> %d" % [lit_t, land_d, ground_s,
		hp0, game.player.hp])
	check(ground_s >= 4.0 and ground_s <= 5.2, "it lay fizzing %.1f s, not 4-5" % ground_s)
	check(lit_t >= 0.0, "he never lit one")
	check(land_d >= 0.0 and land_d < Dynamite.CORE + 20.0, "it came down %.0f px from him" % land_d)
	check(ringed, "no ring round it")
	check(blew_at != Vector2.INF, "it never went off")
	check(game.player.hp < hp0, "the blast didn't hurt him")
	check(not second, "another stick lit right after the blast")
	return true


## Somewhere a wall stands between two bits of open street 45 px apart.
func _round_corner() -> Array:
	for x in range(10, 60):
		for y in range(10, 60):
			var p := Iso.to_screen(Vector2(x, y))
			for i in 4:
				var q := p + Vector2.from_angle(i * TAU / 4.0) * 45.0
				if game.is_free(p) and game.is_free(q) and not game.line_of_sight(p, q, false):
					return [p, q]
	return []


func _blast() -> void:
	var crate: Dictionary = {}
	for prop in game.props:
		if prop["kind"] == "crate" and prop["state"] == 0:
			crate = prop
			break
	var at: Vector2 = game.prop_centre(crate) + Vector2(0, 30)
	game.player.global_position = at + Vector2(0, -3000)
	var near := _take("pistolero")
	_stand(near, at + Vector2(8, 4), false, 2)
	var off := _take("pistolero")
	_stand(off, at + Vector2(40, 0), false, 10)
	var by := _take("bandido")
	game.blast(at, by)
	check(not near.alive and near._death == "death_back", "the man on top of it should be flung dead (%s)" % near._death)
	check(off.alive and off.hp == 10 - 3, "the man %.0f px off should be hurt, not killed (hp %d)" % [40.0, off.hp])
	check(crate["state"] == 2, "the crate by it wasn't blown apart")
	var corner := _round_corner()
	check(not corner.is_empty(), "no corner to hide round")
	var safe := _take("rifleman")
	_stand(safe, corner[1], false, 2)
	game.blast(corner[0], by)
	check(safe.alive and safe.hp == 2, "the man round the corner was hurt")


func _dropped(delta: float) -> bool:
	var s: Dynamite = a.stick if a.stick else (game.lit[0] if not game.lit.is_empty() else null)
	if t > 0.2 and t - delta <= 0.2:
		check(a.stick != null, "no stick in his hand")
		if SCENES[scene_i] == "dropped":
			a.die(Vector2.RIGHT, game.player)
		else:
			a.take_hit(1, Vector2.RIGHT, game.player)
	if s and s.st != Dynamite.S.HELD:
		blew_at = s.global_position
	for e in [a, b]:
		if e and e.reaction == "clear":
			cleared = true
	if t < Dynamite.FUSE + 1.5:
		return false
	check(game.stats.get("blasts", 0) == blasts0 + 1, "it didn't go off")
	check(blew_at.distance_to(a.global_position) < 60.0 or SCENES[scene_i] == "wounded",
		"it went off %.0f px from where he fell" % blew_at.distance_to(a.global_position))
	check(cleared, "nobody ran from it")
	if SCENES[scene_i] == "dropped":
		check(b.alive, "the man next to him didn't get clear")
	else:
		check(a.alive, "the wounded thrower didn't get clear")
	print("%s: blew %.0f px from the thrower; hp of the one running %d" % [SCENES[scene_i],
		blew_at.distance_to(a.global_position), (b if b and SCENES[scene_i] == "dropped" else a).hp])
	cleared = false
	return true
