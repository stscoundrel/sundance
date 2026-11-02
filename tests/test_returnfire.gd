extends SceneTree
## Fire with fire (San Miguel, the town quiet): the stranger shoots one of them from
## round a corner, where hardly any of the rest can see him.
##   answer   - within a couple of seconds several of them put rounds into the corner
##              he's behind (or his spot, if they can see it): somewhere they can see,
##              close by him. Not those watching a corner for him.
##   once     - a second shot a moment later doesn't set the same men off again.
##   stops    - with him quiet and out of sight, it's over in a few seconds: nobody
##              blazing away for long.
##   godot --headless --path . --fixed-fps 60 -s tests/test_returnfire.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var spot := Vector2.ZERO
var answered := {}       # who returned fire -> how many times
var corners := 0
var blind_rounds := 0
var seen := {}


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_reserve", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_downed", true)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _fire_at(victim: Enemy) -> void:
	var p: Player = game.player
	p.facing = (victim.global_position - p.global_position).normalized()
	p.weapon.state = Weapon.S.READY
	p.weapon.cocked = true
	p.weapon.trigger()


func _process(delta: float) -> bool:
	frame += 1
	var p: Player = game.player
	if frame == 3:
		game.begin()
		p.hp = 1000000
		p.process_mode = Node.PROCESS_MODE_DISABLED   # (stood still, round his corner)
	if frame == 120:
		step = "answer"
		var victim: Enemy = null
		var most := -1
		for e in game.enemies:
			var n: int = game.enemies.filter(func(o): return o != e and o.global_position.distance_to(e.global_position) < 250.0).size()
			if n > most:
				most = n
				victim = e
		var fewest := 999
		for r in [60.0, 75.0, 90.0]:
			for k in 24:
				var s: Vector2 = victim.global_position + Vector2.from_angle(k * TAU / 24.0) * r
				if not game.is_free(s) or not game.line_of_sight(s, victim.global_position, false):
					continue
				var n := 0
				for o in game.enemies:
					if o != victim and game.line_of_sight(o.global_position, s, false):
						n += 1
				if n < fewest:
					fewest = n
					spot = s
		p.global_position = spot
		print("  shoots a %s, %d of the gang within 250 px, %d of whom can see where he is" % [victim.kind, most, fewest])
		_fire_at(victim)
	if frame <= 120:
		return false
	t += delta
	for e in game.enemies:
		if not e.alive:
			continue
		if e.suppress_t > 0.0 and not e.single_shot and e.watch_at != Vector2.INF:
			check(false, "a %s watching a corner is blazing away too" % e.kind)
		if e.suppress_t > 0.0 and not e.single_shot and e.return_ok_at > 0.0 and not answered.has(e):
			answered[e] = e.return_ok_at
			check(e.suppress_at.distance_to(spot) < game.CORNER_NEAR + 12.0, "a %s fires %.0f px off his spot" % [
				e.kind, e.suppress_at.distance_to(spot)])
			check(game.line_of_sight(e.global_position, e.suppress_at, false), "a %s fires at a wall" % e.kind)
			if not game.line_of_sight(e.global_position, spot, false):
				corners += 1
	for n in game.world.get_children():
		if n is Bullet and n.shooter is Enemy and not seen.has(n.get_instance_id()):
			seen[n.get_instance_id()] = true
			if not n.shooter.sees_player:
				blind_rounds += 1
	if step == "answer" and t >= 2.0:
		print("  in 2 s: %d returned fire (%d of them at a corner, not his spot)" % [answered.size(), corners])
		check(answered.size() >= 3, "only %d answered his shot" % answered.size())
		check(corners >= 1, "nobody fired at the corner he's behind")
		step = "once"
		var again: Enemy = null
		for e in game.enemies:
			if e.alive and game.line_of_sight(spot, e.global_position, false):
				again = e
				break
		var before: int = game.stats.get("return fire", 0)
		var keen: Array = answered.keys().filter(func(e): return e.alive)
		if again:
			_fire_at(again)
		p.global_position = Iso.to_screen(Vector2(-30, -30))   # (and gone: nobody sees him after it)
		check(keen.all(func(e): return e.suppress_t <= 0.0 or answered[e] == e.return_ok_at),
			"the same men set off again by a second shot")
		print("  a second shot: %d more answer it" % (game.stats.get("return fire", 0) - before))
	if step == "once" and t >= 9.0:
		step = "stops"
		var still: Array = game.enemies.filter(func(e): return e.alive and e.suppress_t > 0.0 and not e.single_shot and not e.sees_player)
		check(still.is_empty(), "%d still blazing away 7 s after his last shot" % still.size())
		print("  %d rounds fired blind in 9 s; stats %s" % [blind_rounds, game.stats])
		print("return fire test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	return false
