extends SceneTree
## Silencio's snow at work (scripts/footprints.gd, scripts/snowfall.gd):
##   prints  - the stranger leaves boot prints walking the snow, and they go on his
##             trail; none on a trodden street. The gangs leave them too, only to look at.
##   fill    - they fill in: about a minute in the steady snow.
##   tracks  - a guard who sees his fresh prints follows them ("Tracks..."); prints
##             the snow's half filled are no lead.
##   squall  - one comes down: everyone sees about half as far, the white closes in,
##             the prints fill three times as fast.
##   godot --headless --path . --fixed-fps 60 -s tests/test_snow.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var waited := 0.0
var queue: Array = []
var fp: Footprints
var p: Player
var mark: Dictionary = {}
var guard: Enemy
var calm_view := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	seed(11)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		fp = game.footprints
		p = game.player
		p.hp = 100000
		for e in game.enemies:   # (stood still where they are, till they're wanted)
			e.process_mode = Node.PROCESS_MODE_DISABLED
		_plan()
	if frame <= 3:
		return false
	t += delta
	waited += delta
	if queue.is_empty():
		for a in ["move_left", "move_up"]:
			Input.action_release(a)
		print("snow test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
		else:
			waited = 0.0
	return false


## A guard of this kind with open ground in front of him (where prints laid would
## be in plain sight), or null.
func _guard_with_a_view(kinds: Array) -> Enemy:
	for e in game.enemies:
		if not e.kind in kinds or e.st != Enemy.St.GUARD or e.patrol.size() > 1:
			continue
		var ok := true
		for i in 6:
			var at: Vector2 = e.global_position + e.facing * (50.0 + i * 12.0)
			ok = ok and game.is_free(at) and game.line_of_sight(e.global_position, at, true)
		if ok:
			return e
	return null


func _his() -> Array:
	return fp.prints.filter(func(q): return q["player"])


func _plan() -> void:
	queue = [
		[0.0, func():
			return game.state == "play" or waited > 15.0],   # (the level's opening first)
		[0.1, func():
			step = "prints"
			check(game.snowfall.storm == 0.0 and absf(game.sight - Snowfall.SIGHT.x) < 0.01, "not the steady snow at the start")
			check(not fp.takes_print(Iso.to_screen(Vector2(32.0, 31.5))), "a print on main street")
			check(not fp.takes_print(Iso.to_screen(Vector2(10.0, 8.6))), "a print on the ice")
			check(fp.takes_print(Iso.to_screen(Vector2(27.0, 57.0))), "no print in the snow by the trail")
			p.global_position = Iso.to_screen(Vector2(29.5, 56.0))
			Input.action_press("move_left")],
		[1.5, func():
			Input.action_release("move_left")
			var his := _his()
			check(his.size() >= 5, "%d prints walking the snow" % his.size())
			check(his.all(func(q): return q in game.trails), "his prints aren't on his trail")
			if not his.is_empty():
				mark = his[0]
			# along main street: no more of them
			var before := his.size()
			p.global_position = Iso.to_screen(Vector2(36.0, 31.5))
			Input.action_press("move_left")
			queue.push_front([1.0, func():
				Input.action_release("move_left")
				check(_his().size() == before, "%d prints on main street" % (_his().size() - before))])],
		[0.1, func():
			step = "gangs"
			# a man of theirs a few strides across open snow
			var walker: Enemy = game.enemies[0]
			var from := Iso.to_screen(Vector2(27.0, 57.0))
			for i in 4:
				walker.global_position = from + Vector2(-10.0 * i, 0)
				fp._step(walker)
			var theirs := fp.prints.filter(func(q): return not q["player"])
			check(theirs.size() >= 3, "%d prints from three strides of his" % theirs.size())
			check(not theirs.any(func(q): return q in game.trails), "their prints are on the stranger's trail")],
		[0.1, func():
			step = "fill"
			var d: float = mark.get("depth", 1.0)
			var age: float = game.clock - mark.get("t", game.clock)
			check(absf((1.0 - d) - age / Footprints.FILL_T) < 0.03, "%.2f filled after %.1f s" % [1.0 - d, age])
			step = "tracks"
			guard = _guard_with_a_view(["trapper", "trappeur", "manhunter", "woodsman"])
			check(guard != null, "no guard with open snow in front of him")
			p.global_position = Iso.to_screen(Vector2(40.0, 62.0))   # (well out of it)
			p.process_mode = Node.PROCESS_MODE_DISABLED
			for i in 6:
				fp.add_print(guard.global_position + guard.facing * (50.0 + i * 12.0), guard.facing, 1.0 if i % 2 else -1.0, true)
			guard.process_mode = Node.PROCESS_MODE_INHERIT],
		[0.0, func():
			if guard.st != Enemy.St.SEARCH and waited < 6.0:
				return false
			check(guard.st == Enemy.St.SEARCH, "the guard didn't follow the tracks (%s)" % Enemy.St.keys()[guard.st])
			check(guard.shout in Enemy.TRACK_LINES or guard.shout_t <= 0.0, "he said '%s'" % guard.shout)
			guard.process_mode = Node.PROCESS_MODE_DISABLED
			step = "filled"
			var other: Enemy = _guard_with_a_view(["sharpshooter", "manhunter", "trapper", "trappeur", "woodsman"].filter(func(k): return k != guard.kind))
			for i in 6:
				var q := fp.add_print(other.global_position + other.facing * (50.0 + i * 12.0), other.facing, 1.0, true)
				q["depth"] = Footprints.LEAD - 0.1
			other.process_mode = Node.PROCESS_MODE_INHERIT
			queue.push_front([3.0, func():
				check(other.st == Enemy.St.GUARD, "followed prints the snow had filled (%s)" % Enemy.St.keys()[other.st])
				other.process_mode = Node.PROCESS_MODE_DISABLED])],
		[0.1, func():
			step = "squall"
			calm_view = guard.view_range()
			game.snowfall.squalls.assign([Vector2(game.clock, game.clock + 30.0)])
			mark = fp.add_print(Iso.to_screen(Vector2(27.0, 57.0)), Vector2.RIGHT, 1.0, false)],
		[Snowfall.RISE + 0.5, func():
			check(game.snowfall.storm == 1.0, "the squall's at %.2f" % game.snowfall.storm)
			check(absf(game.sight - Snowfall.SIGHT.y) < 0.01, "sight at %.2f in the squall" % game.sight)
			check(guard.view_range() < calm_view * 0.7, "he sees %.0f px, %.0f before" % [guard.view_range(), calm_view])
			var fog: float = (game.post.material as ShaderMaterial).get_shader_parameter("fog")
			check(fog > 0.9, "no white-out (%.2f)" % fog)
			mark["depth"] = 1.0
			mark["t"] = game.clock],
		[2.0, func():
			var filled: float = 1.0 - mark["depth"]
			var calm := 2.0 / Footprints.FILL_T
			check(filled > calm * 2.5, "%.3f filled in 2 s of squall (%.3f in the steady snow)" % [filled, calm])],
	]
