extends SceneTree
## The peso. Two of the gang at a post in the bare yard, the stranger well off:
##   lure    - a peso clinks down behind them: the nearer goes for it alone (the other
##             turning to watch him), stoops with his eyes on the dirt, pockets it and
##             walks back to his post. He's unaware all the while: a knife's chance.
##   again   - a second by the same spot: he goes, but has a look round after, wary.
##   trick   - a third: nobody stoops for it; the pair go to see who's throwing money.
##   nobody  - one out of everyone's earshot lies there, and the stranger takes it back.
##   toss    - Q: the stranger's purse goes down by one and a peso lands, no further
##             off than he can flick it.
##   loot    - a dead man's pockets give one up about a time in four.
##   godot --headless --path . --fixed-fps 60 -s tests/test_peso.gd

const POST := Vector2(8.0, 14.0)
const SCENES := ["lure", "again", "trick", "nobody", "toss", "loot"]

var game: Node
var frame := 0
var failures := 0
var scene_i := -1
var t := 0.0
var a: Enemy    # the nearer of the pair: the one who goes
var b: Enemy
var coin_at := Vector2.ZERO
var went := false
var stooped_eyes := 1.0
var watched := false
var unaware_out := true
var back := false
var looked := false
var pesos0 := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [SCENES[scene_i], msg])


func _post(e: Enemy, at: Vector2) -> void:
	e.global_position = at
	e.home = at
	e.patrol = PackedVector2Array()
	e.home_facing = Vector2.UP
	e.facing = Vector2.UP
	e.desired = Vector2.UP
	e.st = Enemy.St.GUARD
	e.wary = false
	e.suspicion = 0.0
	e.path = PackedVector2Array()
	e.process_mode = Node.PROCESS_MODE_INHERIT


func _next() -> void:
	scene_i += 1
	t = 0.0
	went = false
	stooped_eyes = 1.0
	watched = false
	unaware_out = true
	back = false
	looked = false
	if scene_i >= SCENES.size():
		print("pesos: %s" % {"tossed": game.stats.get("pesos tossed", 0), "taken": game.stats.get("pesos taken", 0)})
		print("peso test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return
	var p: Player = game.player
	pesos0 = p.pesos
	match SCENES[scene_i]:
		"lure", "again", "trick":
			if SCENES[scene_i] == "lure":
				_post(a, Iso.to_screen(POST))
				_post(b, Iso.to_screen(POST) + Vector2(24, 0))
			coin_at = Iso.to_screen(POST) + Vector2(-10, 60)   # behind them, nearer him
			game.peso_landed(coin_at)
		"nobody":
			a.process_mode = Node.PROCESS_MODE_DISABLED
			b.process_mode = Node.PROCESS_MODE_DISABLED
			a.global_position += Vector2(0, -3000)
			b.global_position += Vector2(0, -3000)
			coin_at = p.global_position + Vector2(40, 0)
			game.peso_landed(coin_at)
		"toss":
			game._args["toss-at"] = "%f,%f" % [Iso.to_grid(p.global_position + Vector2(400, 0)).x, Iso.to_grid(p.global_position + Vector2(400, 0)).y]
			check(p.toss_peso(), "the peso didn't go")
			check(p.pesos == pesos0 - 1, "his purse is %d after a toss from %d" % [p.pesos, pesos0])
		"loot":
			var dead: Enemy = game.enemies[0]
			for i in 200:
				game._drop_kit(dead)


func _pesos_lying() -> Array:
	var out := []
	for n in game.world.get_children():
		if n is Pickup and n.kind == "peso" and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 1000
		game.player.global_position = Iso.to_screen(Vector2(21.0, 2.5))   # well out of their sight
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -2000)
		for e in game.enemies:
			if e.kind == "bandido":
				a = e
			elif e.kind == "rifleman":
				b = e
		check(game.player.pesos == game.PESO_START, "he rides in with %d pesos" % game.player.pesos)
		_next()
	if frame <= 3 or scene_i >= SCENES.size():
		return false
	t += delta
	var p: Player = game.player
	match SCENES[scene_i]:
		"lure", "again":
			if a.st == Enemy.St.ERRAND:
				went = true
				unaware_out = unaware_out and a.unaware()
				if a.errand_t > 0.0:
					stooped_eyes = minf(stooped_eyes, a.view_range() / Enemy.VIEW)
				if b.facing.dot((a.global_position - b.global_position).normalized()) > 0.9:
					watched = true
			if SCENES[scene_i] == "again" and a.st == Enemy.St.INVESTIGATE and went:
				looked = true
			check(b.st == Enemy.St.GUARD, "the other one left his post too")
			if went and a.st == Enemy.St.GUARD and a.global_position.distance_to(a.home) < 8.0:
				check(_pesos_lying().is_empty(), "the peso's still lying there")
				check(stooped_eyes < 0.6, "his eyes weren't on the dirt (%.2f of his sight)" % stooped_eyes)
				check(watched, "his mate never watched him go")
				check(unaware_out, "he wasn't unaware on his errand")
				if SCENES[scene_i] == "again":
					check(looked, "the second peso didn't have him looking round")
					check(a.wary, "not wary after the second")
				_next()
			elif t > 30.0:
				check(false, "no peso taken and back (went %s, state %d)" % [went, a.st])
				_next()
		"trick":
			check(a.st != Enemy.St.ERRAND and b.st != Enemy.St.ERRAND, "a man stooped for the third peso")
			if t > 0.5:
				check(a.st == Enemy.St.INVESTIGATE and b.st == Enemy.St.INVESTIGATE, "the pair aren't going to see (%d, %d)" % [a.st, b.st])
				check(a.suspicion >= 0.5 and a.wary, "not suspicious of money from the sky")
				check(_pesos_lying().size() == 1, "the third peso isn't lying there")
				for c in _pesos_lying():
					c.queue_free()
				_next()
		"nobody":
			if t > 1.0 and t - delta <= 1.0:
				check(_pesos_lying().size() == 1, "the peso isn't lying there")
				p.global_position = coin_at + Vector2(-20, 0)
				p.velocity = Vector2.ZERO
			if t > 1.0:
				p.global_position = p.global_position.move_toward(coin_at, 60.0 * delta)
			if p.pesos == pesos0 + 1:
				check(_pesos_lying().is_empty(), "taken back and still lying there")
				_next()
			elif t > 4.0:
				check(false, "he couldn't take his peso back (%d)" % p.pesos)
				_next()
		"toss":
			var lying := _pesos_lying()
			if lying.size() == 1:
				var d: float = lying[0].global_position.distance_to(p.global_position)
				check(d <= Player.PESO_MAX + 6.0 and d >= Player.PESO_MIN - 6.0, "landed %.0f px off" % d)
				lying[0].queue_free()
				_next()
			elif t > 2.0:
				check(false, "the peso never landed")
				_next()
		"loot":
			if t > 0.1:
				var n := _pesos_lying().size()
				check(n > 30 and n < 75, "%d pesos from 200 dead men's pockets" % n)
				for c in _pesos_lying():
					c.queue_free()
				_next()
	return false
