extends SceneTree
## The stranger's pair of Colts (the test yard, its gang parked out of the way):
##   card    - the dearest gun on the loadout, 7 points, at the head of the sidearm
##             card, on the Colt's .45s.
##   fire    - right hand, left hand, in turn.
##   reload  - one gun at a time, the right first, the left put away meanwhile and then
##             drawn, and each round slower: well over twice a Colt's time.
##   swap    - given up for a dead man's Colt, it lies there as a pair, loaded as it
##             was, and comes back the same way; a dead gunslinger still leaves two
##             single Colts.
##   stand   - down in the dirt on one elbow, the right gun alone; up again, it's half
##             of the pair as he left it.
##   godot --headless --path . --fixed-fps 60 -s tests/test_pair.gd

class MockGame:
	extends Node
	func sfx(_n: String, _p = null, _v := 0.0, _pv := 0.0) -> void: pass
	func spawn_bullet(_o, _v, _r, _d, _s, _h, _p, _pi := 0) -> void: pass
	func muzzle_flash(_h, _d) -> void: pass
	func make_noise(_p, _r, _k, _s) -> void: pass

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var gun: Dictionary = {}


func _initialize() -> void:
	_card()
	_reload()
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	seed(11)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _time(w: Weapon, until: Callable, limit := 60.0) -> float:
	var s := 0.0
	while not until.call() and s < limit:
		w.update(0.02)
		s += 0.02
	return s


func _card() -> void:
	step = "card"
	check(Player.cost(["colts"]) == 7, "the pair costs %d" % Player.cost(["colts"]))
	for k in Weapon.DATA:
		if k != "colts" and Weapon.DATA[k].has("points"):
			check(Weapon.DATA[k]["points"] < 7, "the %s is as dear" % k)
	check(Player.choices("colt")[0] == "colts", "the pair doesn't head the sidearm card (%s)" % [Player.choices("colt")])
	check(Weapon.DATA["colts"]["ammo"] == "colt", "not on the Colt's rounds")
	check(Hud.BLURB.has("colts"), "no line for the card")


## Every chamber fired, then loaded from the belt: the seconds it takes.
func _reload_time(kind: String, fired: Array = []) -> float:
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g
	var w := Weapon.new(kind, a)
	w.reserve = 40
	for i in w.chambers.size():
		if fired.is_empty() or i in fired:
			w.chambers[i] = 2
	w.start_reload()
	var took := _time(w, func(): return w.state == Weapon.S.READY)
	check(not w.chambers.has(2) and not w.chambers.has(0), "the %s isn't full after its reload (%s)" % [kind, w.chambers])
	a.free()
	g.free()
	return took


func _reload() -> void:
	step = "reload"
	var one := _reload_time("colt")
	var pair := _reload_time("colts")
	print("  a Colt loads in %.1f s, the pair in %.1f s" % [one, pair])
	check(pair > one * 2.25, "the pair (%.1f s) loads under 2.25 times as long as a Colt (%.1f s)" % [pair, one])
	# the left gun alone fired: no putting the right away to get at it
	var left := _reload_time("colts", [1, 3])
	var right := _reload_time("colts", [0, 2])
	check(absf(left - right) < 0.05, "the left gun alone takes %.1f s, the right alone %.1f s" % [left, right])
	# the right gun's chambers go first
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g
	var w := Weapon.new("colts", a)
	w.reserve = 40
	w.chambers.fill(2)
	w.start_reload()
	_time(w, func(): return w.chambers.count(1) == 6)
	check(w.chambers == [1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2] or w.chambers == [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0],
		"the right gun wasn't loaded first (%s)" % [w.chambers])
	a.free()
	g.free()


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		var p: Player = game.player
		p.hp = 100000
		p.process_mode = Node.PROCESS_MODE_DISABLED   # (stood where he's put)
		p.global_position = Iso.to_screen(Vector2(12, 12))
		for e in game.enemies:   # (out of the way, alive: or the yard's won)
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position = Iso.to_screen(Vector2(1.5, 22.5))
		_plan()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("pair test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


## A dead man of this kind with this gun, a little off from the stranger: and the
## guns he dropped.
func _dead_man(kind: String, guns: Array, more := {}) -> Array:
	var p: Player = game.player
	var at: Vector2 = p.global_position + Vector2(60, 20)
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	var over := {"loadouts": [{"guns": guns, "weight": 1}]}
	over.merge(more)
	var e: Enemy = game._add_enemy(kind, at, PackedVector2Array(), 0.0, over)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	e.die(Vector2.RIGHT, p)
	return game.loose_guns.filter(func(g): return g["under"] == e)


func _plan() -> void:
	var p: Player = game.player
	queue = [
		[0.2, func():
			step = "fire"
			p.arm(["colts"])
			check(p.weapons["colt"].kind == "colts" and p.belt.get("colt", 0) == Player.RESERVE["colts"],
				"no pair in his sidearm slot, or its rounds (%s)" % p.belt)
			p.switch_to("colt")
			p.switch_t = 0.0
			var w: Weapon = p.weapon
			var hands := []
			for i in 4:
				_time(w, func(): return w.state == Weapon.S.READY)
				w.trigger()
				hands.append(w.hand)
			check(hands == [0, 1, 0, 1], "fired from hands %s" % [hands])
			_time(w, func(): return w.state == Weapon.S.READY)
			check(w.loaded() == 8, "%d left of twelve" % w.loaded())],
		[0.1, func():
			step = "swap"
			var left := _dead_man("cowboy", ["colt"], {"schofield": 0.0})
			check(left.size() == 1 and left[0]["kind"] == "colt", "the cowboy left %s" % [left.map(func(g): return g["kind"])])
			gun = left[0]
			p.process_mode = Node.PROCESS_MODE_INHERIT
			p.global_position = gun["at"]],
		[0.3, func():
			check(game.at_feet == gun, "the Colt at his feet isn't the one he'd take up")
			game.swap_gun()
			check(p.weapons["colt"].kind == "colt", "the Colt's not in his hand (%s)" % p.weapons["colt"].kind)
			var his: Array = game.loose_guns.filter(func(g): return g.get("his", false))
			check(his.size() == 1 and his[0]["kind"] == "colts", "his pair isn't lying there as one (%s)" % [his.map(func(g): return g["kind"])])
			if his.size() == 1:
				gun = his[0]
				check(gun["weapon"].loaded() == 8, "the pair lying there has %d in it" % gun["weapon"].loaded())
				game.at_feet = gun
				game.swap_gun()
			check(p.weapons["colt"].kind == "colts" and p.weapons["colt"].loaded() == 8, "the pair didn't come back as he left it")
			p.process_mode = Node.PROCESS_MODE_DISABLED
			p.global_position = Iso.to_screen(Vector2(12, 12))
			var two := _dead_man("gunslinger", ["colts"])
			check(two.size() == 2 and two.all(func(g): return g["kind"] == "colt"), "a dead gunslinger left %s" % [
				two.map(func(g): return g["kind"])])],
		[0.1, func():
			step = "stand"
			p.hp = 1
			var pair: Weapon = p.weapons["colt"]
			pair.chambers = [2, 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1] as Array[int]   # the right gun's first fired
			p.take_hit(2, Vector2.UP, game.enemies[0])
			check(p.down and p.boot != null and p.weapon == p.boot and p.weapon.kind == "colt",
				"not down with one Colt in his hand (%s)" % p.weapon.kind)
			check(p.weapon.chambers == ([2, 1, 1, 1, 1, 1] as Array[int]), "the right gun's chambers aren't his (%s)" % [p.weapon.chambers])
			p.weapon.chambers[1] = 2   # (a shot from the dirt)
			p._get_up(false)
			check(not p.down and p.weapon == p.weapons["colt"] and p.weapon.kind == "colts", "not back on his feet with the pair")
			check(pair.chambers == ([2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1] as Array[int]),
				"the pair isn't as he left it, lying there (%s)" % [pair.chambers])],
	]
