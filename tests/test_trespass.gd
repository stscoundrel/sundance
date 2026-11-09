extends SceneTree
## Silencio's misunderstanding (game._trespass_tick): the other gang's men on a gang's
## ground with their guns out, and the gang hasn't seen the stranger they're after.
##   idle     - a hunter just standing on the outlaws' ground, in the chief's sight:
##              no war (the truce lets a man stand where he likes).
##   seen     - the outlaws have seen the stranger: a hunter going to look on their
##              ground is after him, and they know it. No war.
##   attack   - they haven't: the same hunter, the same look, and it's war, the
##              outlaws' man on him, a banner saying why.
##   godot --headless --path . --fixed-fps 60 -s tests/test_trespass.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var waited := 0.0
var queue: Array = []
var hunter: Enemy
var chief: Enemy


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	Engine.set_meta("no_alarm", true)
	seed(23)
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
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED   # (at his horse, out of it)
		_plan()
	if frame <= 3:
		return false
	t += delta
	waited += delta
	if queue.is_empty():
		print("trespass test: ", "OK" if failures == 0 else "%d failures" % failures)
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


func _plan() -> void:
	queue = [
		[0.0, func():
			return game.state == "play" or waited > 15.0],   # (the level's opening first)
		[0.0, func():
			step = "idle"
			for e in game.enemies:
				if e.kind == "outlaw_chief":
					chief = e
			var at := Iso.to_screen(Vector2(20.8, 30.4))
			check(game.on_turf(at, "outlaws"), "the spot before the chief is the outlaws' ground")
			hunter = game._add_enemy("manhunter", at, PackedVector2Array(), 0.0, {"gang": "hunters"})
			return true],
		[1.5, func():
			check(chief.visibility_of(hunter.global_position, false) > 0.0, "the chief sees him")
			check(not game.war, "a hunter standing about is no attack")
			step = "seen"
			game.gangs["outlaws"]["seen"] = true
			hunter.start_investigate(Iso.to_screen(Vector2(20.4, 31.0)), true)
			return true],
		[1.5, func():
			check(hunter.st in [Enemy.St.INVESTIGATE, Enemy.St.SEARCH, Enemy.St.RETURN, Enemy.St.GUARD], "he went to look (st %d)" % hunter.st)
			check(not game.war, "they've seen the stranger: they know who he's after")
			step = "attack"
			game.gangs["outlaws"]["seen"] = false
			hunter.start_investigate(Iso.to_screen(Vector2(21.0, 30.0)), true)
			return true],
		[0.0, func():
			if not game.war and waited < 3.0:
				return false
			check(game.war, "hunters hunting on their ground, and nobody else in town: war")
			check(game.stats.get("blamed", "") == "trespass", "blamed on the trespass (%s)" % game.stats.get("blamed", ""))
			check(game.enemies.any(func(e): return e.gang == "outlaws" and e.foe == hunter), "an outlaw has him for his foe")
			return true],
	]
