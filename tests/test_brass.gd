extends SceneTree
## Spent cases on the ground (scripts/brass.gd), the test yard:
##   reload   - the stranger fires his Colt dry and reloads: the empties he knocks out
##              come down by his boots and stay there.
##   events   - brass flicked out, a Schofield's whole cylinder dumped, a shotgun's
##              shells: each lands near the man and is still there long after (brass
##              yellow, shells red).
##   cap      - past two thousand the oldest go, the newest stay, and every square of
##              ground draws only its own.
##   godot --headless --path . --fixed-fps 60 -s tests/test_brass.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var phase := "reload"
var mark := 0.0
var fired := 0
var before := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	seed(7)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _all() -> Array:
	var out: Array = []
	for cell in game.brass.cells.values():
		out.append_array(cell.cases)
	return out


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
		for e in game.enemies:   # (the yard's to him alone: theirs would land too)
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
	if frame <= 3:
		return false
	t += delta
	if t < 5.0:
		return false   # (the opening)
	if t > 120.0:
		check(false, "stuck in %s" % phase)
		return _finish()
	var p: Player = game.player
	match phase:
		"reload":
			step = "reload"
			if mark == 0.0:
				check(p.weapon.action == "revolver", "not on his Colt: %s" % p.current)
				check(game.brass.count == 0, "brass before a shot: %d" % game.brass.count)
				mark = t
			if p.weapon.can_fire() and fired < 6:
				p.weapon.trigger()
				fired += 1
			elif fired >= 6 and not p.weapon.is_reloading() and p.weapon.needs_reload():
				p.weapon.start_reload()
			if t - mark > 14.0:
				check(game.brass.count >= 6, "%d cases from six fired and a reload" % game.brass.count)
				for c in _all():
					check(c[0].distance_to(p.global_position) < 40.0, "a case %.0f px off" % c[0].distance_to(p.global_position))
				before = game.brass.count
				phase = "events"
				mark = t
		"events":
			step = "events"
			if t - mark < 0.1:
				game.anim_event(p, "brass")
				game.anim_event(p, "dump", 6)
				game.anim_event(p, "shells")
				mark = t - 0.1
				return false
			if t - mark > 4.0 and t - mark < 4.0 + delta * 1.5:
				check(game.brass.count == before + 1 + 6 + 2, "%d cases, wanted %d" % [game.brass.count, before + 9])
				var red := 0
				for c in _all():
					if c[1].r > 0.6 and c[1].g < 0.3:
						red += 1
				check(red == 2, "%d shells on the ground, wanted 2" % red)
			if t - mark > 20.0:
				check(game.brass.count == before + 9, "cases gone in twenty seconds: %d" % game.brass.count)
				phase = "cap"
		"cap":
			step = "cap"
			var first: Array = _all()[0]
			for i in Brass.CAP + 100:
				game.brass.add(Vector2(i % 900, i / 900 * 7.0), Color(0.9, 0.72, 0.3))
			check(game.brass.count == Brass.CAP, "%d past the cap" % game.brass.count)
			check(_all().size() == Brass.CAP, "%d drawn, %d counted" % [_all().size(), game.brass.count])
			check(not game.brass.order.any(func(o): return o[1] == first and o[1][0] == first[0]), "the oldest case is still there")
			check(game.brass.cells.size() > 4, "all in one square of ground: %d" % game.brass.cells.size())
			for cell in game.brass.cells.values():
				for c in cell.cases:
					var k := Vector2i(floori(c[0].x / Brass.CELL), floori(c[0].y / Brass.CELL))
					if game.brass.cells[k] != cell:
						check(false, "a case drawn in the wrong square")
						break
			return _finish()
	return false


func _finish() -> bool:
	print("brass test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
