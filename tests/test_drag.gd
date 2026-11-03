extends SceneTree
## Dragging the dead (the bandits held still and out of town unless in a scene):
##   grab    - a tap of E by a body does nothing to it; holding E takes hold. Only
##             the dead: not a downed man.
##   drag    - walking with E held hauls him along behind, slowly, leaving a smear
##             the bandits can read as the stranger's trail; his pool stays put.
##   drop    - letting go of E drops him; so does going for a gun (and no shot goes
##             off); the undertaker won't claim a body the stranger has hold of.
##   pool    - a guard who sees the pool with nobody in it goes to look.
##   scream  - townsfolk who see him at it mostly cry murder, the rest slip away
##             (and once one cries out, the others run); a bandit in earshot of the
##             cry goes to see.
##   godot --headless --path . --fixed-fps 60 -s tests/test_drag.gd

const SPOT := Vector2(26.0, 31.4)   # open main street

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var used: Array[Enemy] = []
var body: Enemy
var fell_at := Vector2.ZERO
var trails0 := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_reserve", true)
	Engine.set_meta("no_downed", true)
	seed(15)
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


func _here(d := Vector2.ZERO) -> Vector2:
	return Iso.to_screen(SPOT + d)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.alerted_once = true
		game.player.hp = 100000
		for x in game.enemies:
			x.process_mode = Node.PROCESS_MODE_DISABLED
			x.global_position += Vector2(0, -4000)
		for c in game.civilians:
			c.process_mode = Node.PROCESS_MODE_DISABLED
			c.global_position += Vector2(0, -4000)
		_grab()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		for a in ["knife", "move_left", "fire"]:
			Input.action_release(a)
		print("stats: ", game.stats)
		print("drag test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _grab() -> void:
	step = "grab"
	var p: Player = game.player
	body = _take("bandido")
	body.global_position = _here()
	body.process_mode = Node.PROCESS_MODE_INHERIT
	body.die(Vector2.RIGHT)
	fell_at = body.global_position
	p.global_position = body.global_position + Vector2(-12, 0)
	queue = [
		[2.0, func(): Input.action_press("knife")],   # (once he's fallen) a tap
		[0.1, func():
			Input.action_release("knife")],
		[0.3, func():
			check(p.dragging == null, "a tap of E took hold of him")
			Input.action_press("knife")],
		[0.6, func():
			check(p.dragging == body and body.has_meta("dragged"), "holding E didn't take hold")
			check(p.pose == "haul", "not hauling (%s)" % p.pose)
			_drag()],
	]


func _drag() -> void:
	step = "drag"
	var p: Player = game.player
	var from := p.global_position
	trails0 = game.trails.filter(func(d): return d["player"]).size()
	Input.action_press("move_left")
	queue.append([3.0, func():
		Input.action_release("move_left")
		var went := p.global_position.distance_to(from)
		print("dragged %.0f px in 3 s; body %.0f px behind him, %.0f px from where he fell" % [went,
			body.global_position.distance_to(p.global_position), body.global_position.distance_to(fell_at)])
		check(went > p.WALK * p.DRAG_SPEED * 2.0 and went < p.WALK * p.DRAG_SPEED * 3.5, "not at a drag's pace (%.0f px)" % went)
		check(body.global_position.distance_to(p.global_position) < 22.0, "the body didn't come along")
		check(body.global_position.distance_to(fell_at) > 40.0, "the body barely moved")
		check(game.trails.filter(func(d): return d["player"]).size() >= trails0 + 4, "no smear behind him")
		check(game.blood_pools.any(func(pl): return pl["body"] == body and pl["at"] == fell_at), "his pool went with him")
		_drop()])


func _drop() -> void:
	step = "drop"
	var p: Player = game.player
	var undertaker: Civilian = null
	for c in game.civilians:
		if c.undertaker:
			undertaker = c
	check(undertaker == null or game.claim_body(undertaker) != body, "the undertaker claimed the body in the stranger's hands")
	Input.action_release("knife")
	queue.append([0.2, func():
		check(p.dragging == null and not body.has_meta("dragged") and p.pose == "", "letting go of E didn't drop him")
		Input.action_press("knife")])
	queue.append([0.6, func():
		check(p.dragging == body, "couldn't take hold again")
		Input.action_press("fire")
		queue.push_front([0.2, func():
			Input.action_release("fire")
			check(p.dragging == null, "going for a gun didn't drop him")
			check(not game.world.get_children().any(func(n): return n is Bullet), "a shot went off with his hands full")
			Input.action_release("knife")
			_downed_not()])])


func _downed_not() -> void:
	var p: Player = game.player
	var e := _take("cowboy")
	e.global_position = _here(Vector2(4, 0))
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.go_down(Vector2.RIGHT, p)
	check(game.body_to_drag(e.global_position, 20.0) == null, "a downed man can be dragged")
	e.finish(null)
	e.global_position += Vector2(0, -4000)
	_pool()


func _pool() -> void:
	step = "pool"
	var p: Player = game.player
	p.global_position = Iso.to_screen(Vector2(-40, -40))
	body.global_position = Iso.to_screen(Vector2(-30, -30))   # (round a corner, out of anyone's sight)
	var g := _take("cowboy")
	g.global_position = fell_at + Iso.to_screen(Vector2(3.5, 0)) - Iso.to_screen(Vector2.ZERO)
	g.home = g.global_position
	g.facing = (fell_at - g.global_position).normalized()
	g.home_facing = g.facing
	g.desired = g.facing
	g.patrol = PackedVector2Array()
	g.st = Enemy.St.GUARD
	g.process_mode = Node.PROCESS_MODE_INHERIT
	queue.append([1.5, func():
		check(game.stats.get("finds a pool", 0) == 1, "the guard never noticed the empty pool")
		check(g.st in [Enemy.St.INVESTIGATE, Enemy.St.SEARCH], "he didn't go to look (%s)" % Enemy.St.keys()[g.st])
		g.process_mode = Node.PROCESS_MODE_DISABLED
		g.global_position += Vector2(0, -4000)
		_scream()])


func _scream() -> void:
	step = "scream"
	var p: Player = game.player
	p.global_position = _here(Vector2(0, 0))
	var b := _take("pistolero")
	b.global_position = _here(Vector2(10, 0))   # out of sight, in earshot
	b.home = b.global_position
	b.st = Enemy.St.GUARD
	b.facing = Vector2.RIGHT
	b.home_facing = Vector2.RIGHT
	b.desired = Vector2.RIGHT
	b.patrol = PackedVector2Array()
	b.process_mode = Node.PROCESS_MODE_INHERIT
	var dead := _take("bandido")
	dead.global_position = p.global_position + Vector2(-12, 0)
	dead.process_mode = Node.PROCESS_MODE_INHERIT
	dead.die(Vector2.RIGHT)
	var folk: Array = game.civilians.filter(func(c): return not (c.undertaker or c.priest or c.mayor or c.carpenter \
		or c.keeper or c.sweeper or c.henwife or c.gunsmith or c.mourner)).slice(0, 8)
	var i := 0
	for c in folk:
		var at := p.global_position + Vector2.from_angle(i * TAU / folk.size()) * 90.0
		c.global_position = at if game.is_free(at) else game.free_point_near(at, 20.0)
		c.facing = (p.global_position - c.global_position).normalized()
		c.desired = c.facing
		c.process_mode = Node.PROCESS_MODE_INHERIT
		i += 1
	queue.append([2.0, func(): Input.action_press("knife")])
	queue.append([0.6, func():
		check(p.dragging == dead, "couldn't take hold")
		Input.action_press("move_left")])
	queue.append([2.0, func():
		Input.action_release("move_left")
		Input.action_release("knife")
		var calm: Array = folk.filter(func(c): return not c.st in [Civilian.St.FLEE, Civilian.St.COWER, Civilian.St.GONE])
		print("of %d townsfolk round him: %d cried murder, %d slipped away, %d calm" % [folk.size(),
			game.stats.get("screams", 0), game.stats.get("looks away", 0), calm.size()])
		check(game.stats.get("screams", 0) + game.stats.get("looks away", 0) >= 1, "nobody saw him at it")
		check(calm.is_empty(), "%d took no notice" % calm.size())
		check(b.st == Enemy.St.INVESTIGATE or b.st == Enemy.St.COMBAT or b.st == Enemy.St.SEARCH,
			"the bandit in earshot didn't come (%s)" % Enemy.St.keys()[b.st])
		# and the odds, one witness at a time
		var c: Civilian = folk[0]
		var s0: int = game.stats.get("screams", 0)
		var q0: int = game.stats.get("looks away", 0)
		for k in 60:
			c.remove_meta("saw_drag")
			c.st = Civilian.St.IDLE
			c._saw_drag(p)
		var s: int = game.stats.get("screams", 0) - s0
		var q: int = game.stats.get("looks away", 0) - q0
		print("60 witnesses: %d cried murder, %d slipped away" % [s, q])
		check(s + q == 60 and s > 30 and q > 6, "the odds are off")])
