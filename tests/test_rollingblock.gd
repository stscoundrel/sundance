extends SceneTree
## The cut-down Rolling Block, the rifle slot's junk gun (the test yard, its gang
## parked out of the way):
##   gun      - free on the loadout screen, on the Sharps' cartridges: a rifle's hit,
##              but short and wild, and the quickest single-shot to load.
##   carriers - now and then a pistolero has one under his poncho, more rarely a
##              revolucionario: never a man out of a door, nor one passing as
##              townsfolk; nobody else.
##   stranger - it rides in his rifle slot off the Sharps rounds on his belt, swaps for
##              his Winchester off a dead man (F), and a dead poacher's cartridges
##              are his to pick up for it.
##   ditch    - fired off, he likely throws it down for his revolver.
##   godot --headless --path . --fixed-fps 60 -s tests/test_rollingblock.gd

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
var rounds_before := 0


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


func _reload_time(kind: String) -> float:
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g
	var w := Weapon.new(kind, a)
	w.reserve = 5
	w.trigger()
	_time(w, func(): return w.state == Weapon.S.READY)
	w.start_reload()
	var took := _time(w, func(): return w.state == Weapon.S.READY)
	a.free()
	g.free()
	return took


func _gun() -> void:
	step = "gun"
	var cut: Dictionary = Weapon.DATA["rollingblock"]
	check(cut["points"] == 0, "it costs %d points" % cut["points"])
	check(Player.cost(["pistola", "escopeta", "rollingblock"]) == 0, "a junk loadout isn't free")
	for k in ["rifle", "spencer", "springfield"]:
		check(cut["range"] < Weapon.DATA[k]["range"] * 0.65, "reaches as far as the %s" % k)
		check(cut["spread"] > Weapon.DATA[k]["spread"] * 2.0, "as true as the %s" % k)
	check(cut["damage"] == 2 and not cut.has("pierce"), "not a rifle's hit, or it goes through")
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g
	var w := Weapon.new("rollingblock", a)
	check(w.ammo() == "sharps", "takes %s, not the Sharps' cartridges" % w.ammo())
	check(w.barrels.size() == 1 and not w.is_shotgun(), "not a single-shot rifle")
	w.reserve = 5
	w.trigger()
	_time(w, func(): return w.state == Weapon.S.READY)
	check(not w.can_fire() and w.needs_reload(), "fires more than once")
	a.free()
	g.free()
	var took := _reload_time("rollingblock")
	check(took < 1.5, "a round in took %.1f s" % took)
	for k in ["sharps", "springfield"]:
		check(took < _reload_time(k), "slower to load than the %s" % k)
	print("  the block rolled back, a round in and closed in %.1f s" % took)


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
		print("rollingblock test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


## How many of `n` men of this kind come with a Rolling Block.
func _count(kind: String, n: int, overrides := {}) -> int:
	var at := Iso.to_screen(Vector2(3.5, 20.5))
	var with := 0
	for i in n:
		var e: Enemy = game._add_enemy(kind, at, PackedVector2Array(), 0.0, overrides.duplicate(true))
		if e.loadout[0] == "rollingblock":
			with += 1
			check(e.loadout.size() == 2 and e.loadout[1] in Enemy.PISTOLS, "a %s's Rolling Block with %s" % [kind, e.loadout])
			check(e.tdata["draw_sidearm"] >= 0.5, "a %s won't throw his Rolling Block down" % kind)
		game.enemies.erase(e)
		e.cone.free()
		e.free()
	return with


func _carriers() -> void:
	step = "carriers"
	var pist := _count("pistolero", 200)
	print("  pistolero: %d of 200 with a Rolling Block" % pist)
	check(pist >= 8 and pist <= 45, "%d of 200 pistoleros with a Rolling Block" % pist)
	var rev := _count("revolucionario", 300)
	print("  revolucionario: %d of 300 with a Rolling Block" % rev)
	check(rev >= 3 and rev < pist * 1.5, "%d of 300 revolucionarios with a Rolling Block" % rev)
	for kind in ["cowboy", "bandido", "drunkard", "redscarf", "rifleman", "gambler", "saloon_girl", "jefe"]:
		check(_count(kind, 40) == 0, "a %s with a Rolling Block" % kind)
	check(_count("pistolero", 60, {"pistols_only": true}) == 0, "a pistolero out of his door with a Rolling Block")
	check(_count("pistolero", 60, {"concealed": true}) == 0, "a man passing as townsfolk with a Rolling Block")


## A dead man of this kind with this gun, a little off from the stranger: and the
## gun he dropped.
func _dead_man(kind: String, guns: Array, off := Vector2(60, 20)) -> Dictionary:
	var p: Player = game.player
	var at: Vector2 = p.global_position + off
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	var e: Enemy = game._add_enemy(kind, at, PackedVector2Array(), 0.0, {"loadouts": [{"guns": guns, "weight": 1}]})
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
			var rifles := Player.choices("rifle")
			check("rollingblock" in rifles, "not on the loadout's rifle card")
			p.arm(["colt", "rollingblock"])
			check(p.weapons["rifle"].kind == "rollingblock" and "rifle" in p.owned, "no Rolling Block in his rifle slot")
			check(p.weapons["rifle"].reserve == p.belt.get("sharps", -1) and p.belt["sharps"] == Player.RESERVE["rollingblock"],
				"his Rolling Block's rounds aren't Sharps rounds on his belt (%s)" % p.belt)
			rounds_before = p.belt["sharps"]
			gun = _dead_man("poacher", ["sharps"], Vector2(-60, 20))
			check(not gun.is_empty() and gun["ammo_kind"] == "sharps", "the poacher left no Sharps rounds by his rifle")],
		[0.3, func():
			p.process_mode = Node.PROCESS_MODE_INHERIT   # (a body in the world again, to walk over them)
			p.global_position = gun["ammo"].global_position],
		[0.3, func():
			check(p.belt["sharps"] == rounds_before + Pickup.AMOUNT["sharps"],
				"the poacher's rounds aren't on his belt (%d, was %d)" % [p.belt["sharps"], rounds_before])
			check(p.weapons["rifle"].kind == "rollingblock", "he took up the Sharps")
			p.process_mode = Node.PROCESS_MODE_DISABLED
			p.global_position = Iso.to_screen(Vector2(12, 12))
			p.arm(["colt", "rifle"])
			gun = _dead_man("revolucionario", ["rollingblock"])
			check(not gun.is_empty(), "no Rolling Block lying there")],
		[0.3, func():
			p.global_position = gun["at"]],
		[0.3, func():
			check(p.weapons["rifle"].kind == "rifle", "walked over the Rolling Block and it swapped without F")
			check(game.at_feet == gun, "the Rolling Block at his feet isn't the one he'd take up")
			game.swap_gun()
			check(p.weapons["rifle"].kind == "rollingblock", "the Rolling Block's not in his rifle slot (%s)" % p.weapons["rifle"].kind)
			check(p.weapons["rifle"].reserve == p.belt.get("sharps", -1), "not off the Sharps rounds")
			var left: Array = game.loose_guns.filter(func(g): return g.get("his", false))
			check(left.size() == 1 and left[0]["kind"] == "rifle", "his Winchester isn't lying there")],
		[0.1, func():
			step = "ditch"
			p.process_mode = Node.PROCESS_MODE_INHERIT
			p.global_position = Iso.to_screen(Vector2(12, 12))
			var at: Vector2 = p.global_position + Vector2(140, 0)
			if not game.is_free(at):
				at = game.free_point_near(at, 40.0)
			ditcher = game._add_enemy("pistolero", at, PackedVector2Array(), 180.0,
				{"rollingblock": 1.0, "loadouts": [{"guns": ["colt"], "weight": 1}]})
			check(ditcher.weapon.kind == "rollingblock", "the pistolero came without his Rolling Block")
			ditcher.hp = 1000
			ditcher.tdata["draw_sidearm"] = 1.0   # (he likely does: this one always)
			ditcher.enter_combat(p.global_position, false, false)
			ditch_from = game.clock],
		[0.0, func():
			if ditcher.weapon.kind == "rollingblock" and game.clock - ditch_from < 25.0:
				return false
			check(ditcher.weapon.kind in Enemy.PISTOLS, "he kept his Rolling Block (%s)" % ditcher.weapon.kind)
			check(game.loose_guns.any(func(g): return g["kind"] == "rollingblock"), "no Rolling Block lying in the dirt")
			print("  fired the Rolling Block and drew his %s %.1f s in" % [ditcher.weapon.kind, game.clock - ditch_from])],
	]
