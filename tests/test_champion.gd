extends SceneTree
## The Champion, a single-barrel break-open shotgun (the test yard, its gang parked
## out of the way):
##   gun      - one barrel on the coach gun's shells: further and tighter than the
##              coach gun, a shell in quick, the hammer back after it; nothing like the
##              escopeta's age with the ramrod.
##   carriers - the low end of the gang now and then has one slung beside his
##              sidearm (cowboys, bandidos, drunkards, revolucionarios): never a man
##              out of a door, nor one in the coach gun's class; the rabble's rarer.
##   stranger - it rides in his shotgun slot, off the coach gun's shells on his belt,
##              and swaps for his coach gun off a dead man (F). Broken open, it
##              throws out one shell, the coach gun two.
##   ditch    - fired off, he more often than not throws it down for his revolver.
##   godot --headless --path . --fixed-fps 60 -s tests/test_champion.gd

class MockGame:
	extends Node
	var shots := 0
	func sfx(_n: String, _p = null, _v := 0.0, _pv := 0.0) -> void: pass
	func spawn_bullet(_o, _v, _r, _d, _s, _h, _p, _pi := 0) -> void: shots += 1
	func muzzle_flash(_h, _d) -> void: pass
	func make_noise(_p, _r, _k, _s) -> void: pass

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var gun: Dictionary = {}
var ditcher: Enemy
var ditch_from := 0.0


func _initialize() -> void:
	_gun()
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	seed(41)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _time(w: Weapon, until: Callable, limit := 30.0) -> float:
	var s := 0.0
	while not until.call() and s < limit:
		w.update(0.02)
		s += 0.02
	return s


func _gun() -> void:
	step = "gun"
	var champ: Dictionary = Weapon.DATA["champion"]
	var coach: Dictionary = Weapon.DATA["coach"]
	check(champ["range"] > coach["range"] and champ["spread"] < coach["spread"], "no further or tighter than the coach gun")
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g
	var w := Weapon.new("champion", a)
	check(w.ammo() == "coach", "takes %s, not the coach gun's shells" % w.ammo())
	check(w.is_shotgun() and w.barrels.size() == 1, "not a one-barrel shotgun")
	w.reserve = 5
	w.trigger()
	_time(w, func(): return w.state == Weapon.S.READY)
	check(not w.can_fire() and w.needs_reload(), "fires more than once")
	check(w.start_reload(), "won't load")
	var took := _time(w, func(): return w.state == Weapon.S.READY)
	check(w.can_fire() and took < 2.0, "a shell in took %.1f s" % took)
	check(w.reserve == 4, "%d shells left of 5" % w.reserve)
	print("  a shell in and snapped shut in %.1f s" % took)
	check(g.shots == 9, "%d pellets" % g.shots)
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
		_carriers()
		_plan()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("champion test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


## How many of `n` men of this kind come with a Champion.
func _count(kind: String, n: int, overrides := {}) -> int:
	var at := Iso.to_screen(Vector2(3.5, 20.5))
	var with := 0
	for i in n:
		var e: Enemy = game._add_enemy(kind, at, PackedVector2Array(), 0.0, overrides.duplicate(true))
		if e.loadout[0] == "champion":
			with += 1
			check(e.loadout.size() == 2 and e.loadout[1] in Enemy.PISTOLS, "a %s's Champion with %s" % [kind, e.loadout])
			check(e.tdata["draw_sidearm"] >= 0.5, "a %s won't throw his Champion down" % kind)
		game.enemies.erase(e)
		e.cone.free()
		e.free()
	return with


func _carriers() -> void:
	step = "carriers"
	for kind in ["cowboy", "bandido", "drunkard", "revolucionario", "soldadera"]:
		var with := _count(kind, 100)
		print("  %s: %d of 100 with a Champion" % [kind, with])
		check(with >= 8 and with <= 45, "%d of 100 %ss with a Champion" % [with, kind])
	for kind in ["pistolero", "redscarf", "sargento", "tirador", "gambler", "jefe"]:
		check(_count(kind, 30) == 0, "a %s with a Champion" % kind)
	check(_count("bandido", 40, {"pistols_only": true}) == 0, "a bandido out of his door with a Champion")
	var rabble: Array = game.director.arms_sets["rabble"] if game.director else []
	if rabble.is_empty():
		rabble = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))["arms"]["rabble"]
	var with := _count("revolucionario", 200, {"loadouts": rabble})
	print("  the rabble: %d of 200 with a Champion" % with)
	check(with > 0 and with < 40, "%d of 200 of the rabble with a Champion" % with)


## A dead man with this gun, a little off from the stranger: and the gun he dropped.
func _dead_man(kind: String) -> Dictionary:
	var p: Player = game.player
	var at: Vector2 = p.global_position + Vector2(60, 20)
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	var e: Enemy = game._add_enemy("revolucionario", at, PackedVector2Array(), 0.0, {"loadouts": [{"guns": [kind], "weight": 1}]})
	e.process_mode = Node.PROCESS_MODE_DISABLED
	e.die(Vector2.RIGHT, p)
	for g in game.loose_guns:
		if g["under"] == e:
			return g
	return {}


func _plan() -> void:
	var p: Player = game.player
	queue = [
		[0.2, func():
			step = "stranger"
			check("champion" in Player.choices("coach"), "not on the loadout's shotgun card")
			p.arm(["colt", "champion"])
			check(p.weapons["coach"].kind == "champion" and "coach" in p.owned, "no Champion in his shotgun slot")
			check(p.weapons["coach"].reserve == p.belt.get("coach", -1) and p.belt["coach"] == Player.RESERVE["champion"],
				"his Champion's shells aren't the coach gun's on his belt (%s)" % p.belt)
			for k in ["champion", "coach"]:   # a shell out of each barrel
				p.arm(["colt", k])
				p.switch_to("coach")
				var before: int = game.world.get_child_count()
				game.anim_event(p, "shells")
				var puff: Puff = game.world.get_child(game.world.get_child_count() - 1)
				check(game.world.get_child_count() == before + 1 and puff.parts.size() == Weapon.DATA[k]["barrels"],
					"the %s threw out %d shells" % [k, puff.parts.size()])
			p.arm(["colt", "coach"])
			gun = _dead_man("champion")
			check(not gun.is_empty(), "no Champion lying there")],
		[0.3, func():
			p.global_position = gun["at"]],
		[0.3, func():
			check(p.weapons["coach"].kind == "coach", "walked over the Champion and it swapped without F")
			check(game.at_feet == gun, "the Champion at his feet isn't the one he'd take up")
			game.swap_gun()
			check(p.weapons["coach"].kind == "champion", "the Champion's not in his shotgun slot (%s)" % p.weapons["coach"].kind)
			check(p.weapons["coach"].reserve == p.belt["coach"], "not off the coach gun's shells")
			var left: Array = game.loose_guns.filter(func(g): return g.get("his", false))
			check(left.size() == 1 and left[0]["kind"] == "coach", "his coach gun isn't lying there")],
		[0.1, func():
			step = "ditch"
			p.process_mode = Node.PROCESS_MODE_INHERIT
			p.global_position = Iso.to_screen(Vector2(12, 12))
			var at: Vector2 = p.global_position + Vector2(110, 0)
			if not game.is_free(at):
				at = game.free_point_near(at, 40.0)
			ditcher = game._add_enemy("cowboy", at, PackedVector2Array(), 180.0, {"champion": 1.0})
			check(ditcher.weapon.kind == "champion", "the cowboy came without his Champion")
			ditcher.hp = 1000
			ditcher.tdata["draw_sidearm"] = 1.0   # (he does, more often than not: this one always)
			ditcher.enter_combat(p.global_position, false, false)
			ditch_from = game.clock],
		[0.0, func():
			if ditcher.weapon.kind == "champion" and game.clock - ditch_from < 25.0:
				return false
			check(ditcher.weapon.kind in Enemy.PISTOLS, "he kept his Champion (%s)" % ditcher.weapon.kind)
			check(game.loose_guns.any(func(g): return g["kind"] == "champion"), "no Champion lying in the dirt")
			print("  fired the Champion and drew his %s %.1f s in" % [ditcher.weapon.kind, game.clock - ditch_from])],
	]
