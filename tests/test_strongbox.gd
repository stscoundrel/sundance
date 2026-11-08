extends SceneTree
## Silencio's strongbox, the outlaws' gold (scripts/strongbox.gd):
##   map     - it sits in the hideout's doorway, the chief by it; the stranger's horse
##             is tied where he starts.
##   carry   - E by it: a second bent to it (not moving), then it's in his arms, no
##             gun in his hands; he goes slower than he walks, faster than he drags
##             a man, slower again crouched. E sets it down at his feet; reaching for
##             a gun drops it where he stands.
##   missed  - an outlaw looking at the empty doorway (the mountain man at the feed
##             barn faces it) misses it: their alarm up (the hunters' only uneasy),
##             men sent out to look.
##   fetch   - a trapper who sees it lying out takes it up and carries it home.
##   away    - to his horse with it in his arms: he's gone, and the level's won.
##   godot --headless --path . --fixed-fps 60 -s tests/test_strongbox.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var box: Strongbox
var p: Player
var mark := Vector2.ZERO
var trapper: Enemy
var waited := 0.0   # s a step's been waiting on something


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	seed(7)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _tap(action: String) -> void:
	Input.action_press(action)
	queue.push_front([0.05, func(): Input.action_release(action)])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		box = game.strongbox
		p = game.player
		game.level.erase("turf")   # (no street war over the missing gold here: test_war's)
		p.hp = 100000
		for e in game.enemies:   # (stood still where they are, till they're wanted)
			e.process_mode = Node.PROCESS_MODE_DISABLED
		_map()
		_plan()
	if frame <= 3:
		return false
	t += delta
	waited += delta
	if queue.is_empty():
		for a in ["move_right", "knife", "fire"]:
			Input.action_release(a)
		print("strongbox test: ", "OK" if failures == 0 else "%d failures" % failures)
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


func _map() -> void:
	step = "map"
	check(box != null and box.at_home() and not box.missed, "no strongbox at home")
	var door := Iso.to_screen(Vector2(17.5, 29.4))
	check(box.home.distance_to(door) < 20.0, "it's not in the hideout's doorway")
	var chief: Enemy = game.enemies.filter(func(e): return e.kind == "outlaw_chief")[0]
	check(chief.global_position.distance_to(box.home) < 40.0, "the chief's not by it")
	check(box.horse.distance_to(p.global_position) < 70.0, "his horse isn't where he starts")
	check(game.placed.any(func(r): return r["type"] == "horse"), "no horse on the map")


func _plan() -> void:
	queue = [
		[0.2, func():
			step = "carry"
			# away from the outlaws' eyes for now: the box brought to the horse's trail
			box.global_position = Iso.to_screen(Vector2(32.5, 58.0))
			p.global_position = box.global_position + Vector2(6, 2)
			p.process_mode = Node.PROCESS_MODE_INHERIT
			_tap("knife")],
		[0.4, func():
			check(p.lift_t > 0.0 and p.box == null and p.velocity == Vector2.ZERO, "not bent to it (lift %.2f)" % p.lift_t)],
		[0.8, func():
			check(p.box == box and box.holder == p and not box.sprite.visible, "it's not in his arms")
			check(p.anim_gun == "strongbox" and p.pose == "carry", "no carrying pose (%s, %s)" % [p.anim_gun, p.pose])
			mark = p.global_position
			Input.action_press("move_right")],
		[0.5, func():
			var v := p.velocity.length()
			check(v > Player.WALK * Player.DRAG_SPEED + 1.0 and v < Player.WALK - 1.0, "carrying it at %.1f px/s" % v)
			Input.action_release("move_right")
			_tap("crouch")],
		[0.1, func():
			Input.action_press("move_right")],
		[0.3, func():
			check(p.crouched and p.box == box and p.velocity.length() < Player.WALK * Player.BOX_SPEED - 3.0,
				"crouched with it at %.1f" % p.velocity.length())
			Input.action_release("move_right")
			_tap("crouch")],
		[0.2, func():
			_tap("knife")],
		[0.2, func():
			check(p.box == null and box.lying() and box.global_position.distance_to(p.global_position) < 20.0,
				"E didn't set it down at his feet")
			check(p.anim_gun == "" and p.pose == "", "still in the carrying pose")
			_tap("knife")],
		[1.3, func():
			check(p.box == box, "didn't take it up again")
			_tap("fire")],
		[0.2, func():
			check(p.box == null and box.lying(), "reached for his gun and kept hold of it")
			step = "missed"
			# (the mountain man at the feed barn faces the doorway: he's seen it go
			# already; start them all again from not knowing)
			box.missed = false
			game.stats.erase("gold missed")
			for g in game.gangs:
				game.gangs[g]["alarm"] = 0.0
			# an outlaw by the hideout, looking at the empty doorway
			var e: Enemy = game.enemies.filter(func(o): return o.kind == "mountainman")[0]
			e.process_mode = Node.PROCESS_MODE_INHERIT
			e.facing = (box.home - e.global_position).normalized()
			for o in game.enemies:
				o.process_mode = Node.PROCESS_MODE_INHERIT
			p.global_position = Iso.to_screen(Vector2(40.0, 62.0))   # (out of everyone's way)
			p.process_mode = Node.PROCESS_MODE_DISABLED],
		[1.0, func():
			check(box.missed and game.stats.get("gold missed", 0) == 1, "nobody missed it")
			check(game.gangs["outlaws"]["alarm"] >= game.SEND, "the outlaws' alarm only %.0f" % game.gangs["outlaws"]["alarm"])
			check(game.gangs["hunters"]["alarm"] <= game.OTHER_END, "the hunters' alarm %.0f" % game.gangs["hunters"]["alarm"])
			var out: Array = game.enemies.filter(func(o): return o.alarm_role == "scout" and o.gang == "outlaws")
			check(out.size() >= 3, "%d outlaws sent to look for it" % out.size())
			step = "fetch"
			trapper = game.enemies.filter(func(o): return o.kind == "trapper" and o.st != Enemy.St.COMBAT \
				and o.alarm_role != "scout")[0]
			box.put_down(trapper.global_position + Vector2(40, 10))],
		[0.5, func():
			check(box.fetcher != null, "nobody went for it lying in the snow")
			if box.fetcher:
				trapper = box.fetcher],
		[0.0, func():
			if box.holder != trapper and waited < 8.0:
				return false
			check(box.holder == trapper and trapper.anim_gun == "strongbox", "the trapper didn't take it up")],
		[0.0, func():
			if not box.at_home() and waited < 25.0:
				return false
			check(box.at_home(), "not carried home (%.0f px off; holder %s, he's %s/%s, %.0f px from home, fetcher %s)" % [
				box.global_position.distance_to(box.home), box.holder, trapper.reaction, trapper.fetch_phase,
				trapper.global_position.distance_to(box.home), box.fetcher])
			check(trapper.anim_gun == "" and trapper.reaction == "", "the trapper's still carrying")
			step = "away"
			for o in game.enemies:
				o.process_mode = Node.PROCESS_MODE_DISABLED
			box.global_position = Iso.to_screen(Vector2(32.0, 60.0))
			p.process_mode = Node.PROCESS_MODE_INHERIT
			p.global_position = box.global_position + Vector2(-4, 3)
			_tap("knife")],
		[1.3, func():
			check(p.box == box, "didn't take it up by the trail")
			p.global_position = box.horse + Vector2(0, 18)],
		[0.3, func():
			check(box.away and game.state == "won" and not p.visible, "not away with it (%s)" % game.state)
			check(box.line().contains("yours"), "the end card: %s" % box.line())],
	]
