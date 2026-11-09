extends SceneTree
## Silencio's townsfolk and the gangs' street war, slowed (Civilian "shy", Enemy.FEUD_*):
##   line    - the stranger's line at the start is no line at all: "...".
##   still   - a gang man standing his post by her door doesn't send her in.
##   shy     - one walking up to a townsman's door does: he's in, and stays in a
##             good while longer than San Miguel's folk would.
##   feud    - at the other gang's man a gang man shoots wide and slow: his spread
##             FEUD_SPREAD times what it is at the stranger.
##   godot --headless --path . --fixed-fps 60 -s tests/test_snowbound.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var waited := 0.0
var queue: Array = []
var man: Civilian
var woman: Civilian
var guard: Enemy
var walker: Enemy


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	Engine.set_meta("no_alarm", true)
	seed(17)
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
		_plan()
	if frame <= 3:
		return false
	t += delta
	waited += delta
	if queue.is_empty():
		print("snowbound test: ", "OK" if failures == 0 else "%d failures" % failures)
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


## The placed townsfolk nearest this tile.
func _folk_at(x: float, y: float) -> Civilian:
	var at := Iso.to_screen(Vector2(x, y))
	var best: Civilian = null
	for c in game.civilians:
		if best == null or c.global_position.distance_to(at) < best.global_position.distance_to(at):
			best = c
	return best


func _plan() -> void:
	queue = [
		[0.0, func():
			return game.state == "play" or waited > 15.0],   # (the level's opening first)
		[0.0, func():
			step = "line"
			if game.player.shout_t <= 0.0 and waited < 6.0:
				return false
			check(game.player.shout == "...", "his line should be '...', was '%s'" % game.player.shout)
			game.player.process_mode = Node.PROCESS_MODE_DISABLED   # (out of it from here)
			step = "still"
			check(game.civilians.size() == 7, "7 townsfolk, got %d" % game.civilians.size())
			woman = _folk_at(31.2, 16.2)
			check(woman.shy and woman.kind == "snowbound_woman", "the woman at the church door should be shy")
			var by := woman.global_position + woman.facing * 60.0
			guard = game._add_enemy("manhunter", by, PackedVector2Array(), 0.0, {"gang": "hunters"})
			return true],
		[3.0, func():
			check(woman.st in [Civilian.St.IDLE, Civilian.St.WALK], "a man standing still by her door shouldn't send her in (st %d)" % woman.st)
			guard.queue_free()
			game.enemies.erase(guard)
			step = "shy"
			man = _folk_at(33.6, 40.4)
			man.desired = Vector2.DOWN
			man.facing = Vector2.DOWN
			var from := man.global_position + Vector2(0, 150)
			walker = game._add_enemy("trapper", from, PackedVector2Array([from, man.global_position + Vector2(0, 20)]), 0.0, {"gang": "outlaws"})
			return true],
		[0.0, func():
			if man.st != Civilian.St.GONE and waited < 15.0:
				return false
			check(man.st == Civilian.St.GONE, "a trapper walking up to his door should have sent him in (st %d)" % man.st)
			check(man.back_after >= Civilian.SHY_BACK.x, "he should stay in a good while (%.1f s)" % man.back_after)
			check(game.stats.get("civilian shy", 0) >= 1, "counted as shy")
			step = "feud"
			var a: Enemy = game._add_enemy("trapper", Iso.to_screen(Vector2(30.0, 44.0)), PackedVector2Array(), 0.0, {"gang": "outlaws"})
			var b: Enemy = game._add_enemy("manhunter", Iso.to_screen(Vector2(34.0, 44.0)), PackedVector2Array(), 0.0, {"gang": "hunters"})
			var at_him := a.accuracy_mult()
			a.foe = b
			check(is_equal_approx(a.accuracy_mult(), at_him * Enemy.FEUD_SPREAD),
				"his spread at the other gang should be %.1fx (%.2f vs %.2f)" % [Enemy.FEUD_SPREAD, a.accuracy_mult(), at_him])
			return true],
	]
