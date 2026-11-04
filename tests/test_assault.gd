extends SceneTree
## The federal army's way of fighting at Paso Esperanza (enemy.gd, the assault):
##   bounds   - a soldado sent for the train goes in bounds, down a while between
##              them, and gets to his spot; on the way he isn't chasing the stranger.
##   push     - far out, rounds cracking past him all the while, he doesn't lie there
##              pinned: he keeps coming; close in, a round past him pins him.
##   cover    - the levas, green as they are, take cover on far fewer of their bounds
##              than the regulars.
##   volley   - a cabo with men about him who can see the stranger has them hold and
##              fire together.
##   desert   - a leva who's lost heart runs for the road and is gone (not dead).
##   smoke    - the army's guns carry less far and throw wider here; his don't.
##   fright   - the machine gun cuts a man down: the men by him the stranger can see
##              go to ground or give ground (not one far off down the line), and a
##              while after, it doesn't frighten them again.
##   hunt     - a man round among the carriers, the stranger far off, may turn on one
##              of them: he kills one, then he's done with them.
##   godot --headless --path . --fixed-fps 60 -s tests/test_assault.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var phase := "bounds"
var mark := 0.0
var walker: Enemy
var start_d := 0.0
var levas: Array = []
var soldados: Array = []
var cabo: Enemy
var leva: Enemy
var deserter_sent := false
var hunter: Enemy
var pusher: Enemy
var _logged := ""


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "train")
	Engine.set_meta("no_waves", true)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _spawn(k: String, g: Vector2, spot := Vector2.INF, over := {}) -> Enemy:
	var e: Enemy = game._add_enemy(k, Iso.to_screen(g), PackedVector2Array(), 160.0, over)
	if spot != Vector2.INF:
		e.assault_to(Iso.to_screen(spot))
		e.enter_combat(game.player.global_position, false, false)
	return e


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
		game.player.global_position = Iso.to_screen(Vector2(34.6, 35.6))
		game.cargo.goal = 1000   # (the carriers keep at it all test: there's one to hunt at the end)
		game.cargo.wagons[0]["cap"] = 1000
	if frame <= 3:
		return false
	t += delta
	if t < 6.0:
		return false   # (the opening)
	if t > 400.0:
		check(false, "stuck in %s" % phase)   # (a hard stop: never hang the suite)
		return _finish()
	if phase != _logged:
		_logged = phase
		print("  %.0fs: %s" % [t, phase])
	match phase:
		"bounds":
			step = "bounds"
			if walker == null:
				walker = _spawn("soldado", Vector2(56.0, 22.0), Vector2(32.0, 21.0))
				start_d = walker.global_position.distance_to(walker.objective)
				mark = t
				return false
			if walker.objective == Vector2.INF:
				check(walker.bounds.x >= 2, "got there in %d bounds" % walker.bounds.x)
				check(walker.global_position.distance_to(Iso.to_screen(Vector2(32.0, 21.0))) < 60.0, "not by the train")
				for e in game.enemies:
					e.die(Vector2.RIGHT, null)
				phase = "push"
				mark = t
			elif t - mark > 90.0:
				check(false, "never got to the train (%.0f px of %.0f to go)" % [walker.global_position.distance_to(walker.objective), start_d])
				phase = "cover"
				mark = t
		"push":
			step = "push"
			if pusher == null:
				pusher = _spawn("soldado", Vector2(56.0, 30.0), Vector2(40.2, 33.0))
				start_d = pusher.global_position.distance_to(pusher.objective)
				return false
			if t - mark < 8.0:
				pusher.near_miss(game.player.global_position)   # (the gun on him, every frame)
				check(pusher.pinned_t <= 0.0 or not pusher.pushing(), "pinned down, far out")
				return false
			var gone := start_d - pusher.global_position.distance_to(pusher.objective) if pusher.objective != Vector2.INF else start_d
			check(gone > 120.0, "under fire, he came only %.0f px of %.0f" % [gone, start_d])
			pusher.global_position = game.player.global_position + Vector2(60, 30)
			pusher.near_miss(game.player.global_position)
			check(not pusher.pushing() and pusher.pinned_t > 0.0, "close in, and not pinned")
			for e in game.enemies:
				e.die(Vector2.RIGHT, null)
			phase = "cover"
			mark = t
		"cover":
			step = "cover"
			if levas.is_empty():
				for i in 6:
					levas.append(_spawn("leva", Vector2(58.0, 30.0 + i * 1.6), Vector2(32.2, 12.4 + i * 2.0)))
					soldados.append(_spawn("soldado", Vector2(60.0, 31.0 + i * 1.6), Vector2(32.2, 12.4 + i * 2.0)))
				return false
			if t - mark > 50.0:
				var lv := Vector2i.ZERO
				var sv := Vector2i.ZERO
				for e in levas:
					lv += e.bounds
				for e in soldados:
					sv += e.bounds
				var lr := float(lv.y) / maxf(1.0, lv.x)
				var sr := float(sv.y) / maxf(1.0, sv.x)
				check(lv.x >= 6 and sv.x >= 6, "too few bounds to tell: %s, %s" % [lv, sv])
				check(lr < sr - 0.25, "levas to cover %.2f of the time, soldados %.2f" % [lr, sr])
				for e in game.enemies:
					e.die(Vector2.RIGHT, null)
				phase = "volley"
				mark = t
		"volley":
			step = "volley"
			if cabo == null:
				mark = float(game.stats.get("volleys", 0))   # (only a new one counts)
				game.player.global_position = Iso.to_screen(Vector2(46.0, 37.0))   # (out on the open road, in their sight)
				cabo = _spawn("cabo", Vector2(52.0, 37.0), Vector2(32.0, 21.0))
				for i in 4:
					_spawn("soldado", Vector2(52.5, 34.6 + i * 1.4), Vector2(32.0, 21.0))
				return false
			if game.stats.get("volleys", 0) > int(mark):
				phase = "desert"
				for e in game.enemies:
					e.die(Vector2.RIGHT, null)
				game.player.global_position = Iso.to_screen(Vector2(34.6, 35.6))
				mark = t
			elif cabo.t > 30.0:
				check(false, "no volley")
				phase = "desert"
				mark = t
		"desert":
			step = "desert"
			if not deserter_sent:
				deserter_sent = true
				leva = _spawn("leva", Vector2(50.0, 45.0), Vector2(29.6, 42.4))
				return false
			if t - mark < 3.0:
				return false
			if not is_instance_valid(leva) or not game.enemies.has(leva):   # (freed once he's off the map)
				check(game.stats.get("deserted", 0) >= 1, "gone, but not counted as a deserter")
				phase = "smoke"
				mark = t
			elif not leva.deserting:
				leva.lose_heart()
				check(leva.deserting, "lost heart and didn't run")
			elif t - mark > 60.0:
				check(false, "still running for the road (at %s)" % [Iso.to_grid(leva.global_position)])
				phase = "smoke"
				mark = t
		"smoke":
			step = "smoke"
			var s1 := _spawn("soldado", Vector2(50.0, 30.0))
			check(is_equal_approx(s1.reach(), s1.weapon.d["range"] * 0.7), "his reach %.0f of %.0f" % [s1.reach(), s1.weapon.d["range"]])
			var clear: float = s1.accuracy_mult() / game.haze.y
			check(is_equal_approx(s1.accuracy_mult(), clear * 1.4), "his aim not spoilt by the smoke")
			check(game.player.range_mult() == 1.0 and game.player.accuracy_mult() < s1.accuracy_mult(), "the smoke on him too")
			s1.die(Vector2.RIGHT, null)
			phase = "fright"
			mark = t
		"fright":
			step = "fright"
			var p: Player = game.player
			var g: MGun = game.mgun
			p.global_position = g.seat
			p.get_on(g)
			p.set_physics_process(false)
			var at := Iso.to_grid(g.seat) + Vector2(6.0, 2.0)
			var victim := _spawn("leva", at, Vector2(40.6, 37.8))
			var near1 := _spawn("soldado", at + Vector2(1.0, 0.6), Vector2(40.6, 37.8))
			var near2 := _spawn("leva", at + Vector2(-0.6, 1.2), Vector2(40.6, 37.8))
			var far1 := _spawn("soldado", at + Vector2(1.5, -22.0), Vector2(40.6, 37.8))   # (off down the line)
			victim.die(Vector2.RIGHT, p)
			for m in [near1, near2]:
				check(m.reaction in ["hide", "backoff", "flee"] and m.gun_nerve > game.clock, "%s by the man cut down, unmoved (%s)" % [m.kind, m.reaction])
			check(far1.reaction == "" and far1.gun_nerve < 0.0, "a man far off down the line frightened")
			var again := _spawn("leva", at + Vector2(0.4, 0.4), Vector2(40.6, 37.8))
			near1.reaction = ""
			again.die(Vector2.RIGHT, p)
			check(near1.reaction == "", "frightened again straight after")
			for e in game.enemies:
				e.die(Vector2.RIGHT, null)
			p.set_physics_process(true)
			p.get_off()
			phase = "hunt"
			mark = t
		"hunt":
			step = "hunt"
			if hunter == null:
				game.player.global_position = Iso.to_screen(Vector2(56.0, 56.0))   # (far off)
				var near: Civilian = null
				for c in game.cargo.carriers:
					if c.alive and c.visible and c.load_kind != "" and Iso.to_grid(c.global_position).x < 18.0:   # (laden, out west on the way to the wagons, well off the boxcar doors: one going in at a door is out of sight, and he gives that one up)
						near = c
						break
				if near == null:
					return false
				var g: Vector2 = Iso.to_grid(near.global_position)
				hunter = _spawn("rural", g + Vector2(-3.0, 2.0), Vector2.INF, {"hunt": 1.0})
				hunter.assault = true
				hunter.enter_combat(game.player.global_position, false, false)
				return false
			if t - mark > 40.0:
				var killed := 0
				for c in game.cargo.carriers:
					if not c.alive and c.killer == hunter:
						killed += 1
				check(killed == 1, "%d carriers killed by the one man" % killed)
				check(hunter.hunt_rolled and hunter.hunting == null, "still on the carriers")
				return _finish()
	return false


func _finish() -> bool:
	print("assault test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
