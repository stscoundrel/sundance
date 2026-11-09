extends SceneTree
## The Henry 1860, the Winchester's forerunner (the test yard, its gang parked out of
## the way):
##   gun      - fifteen rounds (fourteen in the tube, one up) on the Winchester's
##              cartridges, 4 points against its 5; a slower lever.
##   loading  - filled at the muzzle: a round or two costs nearly as much as the lot,
##              and the whole tube takes longer than the Winchester's.
##   heat     - nothing to hold but the barrel: fired fast it throws wider, and
##              cools again; the Winchester doesn't.
##   carriers - about a third of the gang's Winchesters are Henrys (a type can say
##              otherwise); nobody without a Winchester has one.
##   stranger - it rides in his rifle slot off the Winchester rounds on his belt, and
##              swaps for a dead man's Winchester (F) on the same rounds.
##   godot --headless --path . --fixed-fps 60 -s tests/test_henry.gd

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


func _initialize() -> void:
	_gun()
	_loading()
	_heat()
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


## A gun of this kind in a mock man's hands, with this many fired off.
func _with(kind: String, fired: int) -> Array:
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g
	var w := Weapon.new(kind, a)
	w.reserve = 40
	for i in fired:
		w.trigger()
		_time(w, func(): return w.state == Weapon.S.READY)
	return [w, a, g]


## Seconds to load back what `fired` shots took out.
func _reload_time(kind: String, fired: int) -> float:
	var got := _with(kind, fired)
	var w: Weapon = got[0]
	w.start_reload()
	var took := _time(w, func(): return w.state == Weapon.S.READY)
	# (from empty, the lever takes one up out of the full tube)
	check(w.loaded() == w.cap() + (0 if fired > w.cap() else 1), "a %s loaded back to %d" % [kind, w.loaded()])
	got[1].free()
	got[2].free()
	return took


func _gun() -> void:
	step = "gun"
	var h: Dictionary = Weapon.DATA["henry"]
	var win: Dictionary = Weapon.DATA["rifle"]
	check(h["points"] == 4 and win["points"] == 5, "the Henry costs %d, the Winchester %d" % [h["points"], win["points"]])
	check(Player.SLOT["henry"] == "rifle" and "henry" in Player.choices("rifle"), "not on the rifle card")
	check(h["cycle"] > win["cycle"], "its lever's no slower than the Winchester's")
	check(h["damage"] == win["damage"] and h["range"] <= win["range"], "not the Winchester's round")
	var got := _with("henry", 0)
	var w: Weapon = got[0]
	check(w.ammo() == "rifle", "takes %s, not the Winchester's cartridges" % w.ammo())
	check(w.cap() == 14 and w.loaded() == 15, "holds %d in the tube, %d in all" % [w.cap(), w.loaded()])
	var n := 0
	while w.can_fire() and n < 30:
		w.trigger()
		_time(w, func(): return w.state == Weapon.S.READY)
		n += 1
	check(n == 15 and got[2].shots == 15, "fired %d (%d bullets) before it was empty" % [n, got[2].shots])
	got[1].free()
	got[2].free()


func _loading() -> void:
	step = "loading"
	var one_h := _reload_time("henry", 1)
	var one_w := _reload_time("rifle", 1)
	check(one_h > one_w * 2.0, "a round in: the Henry %.1f s, the Winchester %.1f s" % [one_h, one_w])
	var all_h := _reload_time("henry", 15)
	var all_w := _reload_time("rifle", 13)
	check(all_h > all_w, "all of it: the Henry %.1f s, the Winchester %.1f s" % [all_h, all_w])
	# per round in, topping up two hardly costs more than one: the sleeve's the price
	var two_h := _reload_time("henry", 2)
	check(two_h - one_h < one_h * 0.25, "a second round costs %.1f s over the first's %.1f" % [two_h - one_h, one_h])
	# stopped part way (a shot), the sleeve's closed again before it'll fire
	var got := _with("henry", 6)
	var w: Weapon = got[0]
	w.start_reload()
	_time(w, func(): return w.state == Weapon.S.INSERT)
	w.trigger()
	check(not w.can_fire(), "fires with the sleeve open")
	_time(w, func(): return w.state == Weapon.S.READY)
	check(w.loaded() < w.cap() + 1 and w.loaded() > 9, "stopped with %d in" % w.loaded())
	got[1].free()
	got[2].free()
	print("  a round in %.1f s (the Winchester %.1f), the lot %.1f s (%.1f)" % [one_h, one_w, all_h, all_w])


func _heat() -> void:
	step = "heat"
	var got := _with("henry", 0)
	var w: Weapon = got[0]
	check(w.heat == 0.0, "hot before a shot")
	for i in 6:
		w.trigger()
		_time(w, func(): return w.state == Weapon.S.READY)
	check(w.heat >= 0.9, "six quick shots and it's %.2f hot" % w.heat)
	_time(w, func(): return false, 8.0)
	check(w.heat == 0.0, "not cool after a while (%.2f)" % w.heat)
	got[1].free()
	got[2].free()
	got = _with("rifle", 6)
	check(got[0].heat == 0.0, "the Winchester's fore-end gets hot (%.2f)" % got[0].heat)
	got[1].free()
	got[2].free()


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
		print("henry test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


## How many of `n` men of this kind come with a Henry.
func _count(kind: String, n: int, overrides := {}) -> int:
	var at := Iso.to_screen(Vector2(3.5, 20.5))
	var with := 0
	for i in n:
		var e: Enemy = game._add_enemy(kind, at, PackedVector2Array(), 0.0, overrides.duplicate(true))
		if "henry" in e.loadout:
			with += 1
			check(not "rifle" in e.loadout, "a %s with a Henry and a Winchester" % kind)
		game.enemies.erase(e)
		e.cone.free()
		e.free()
	return with


func _carriers() -> void:
	step = "carriers"
	var rif := _count("rifleman", 200)
	print("  rifleman: %d of 200 with a Henry" % rif)
	check(rif >= 40 and rif <= 85, "%d of 200 riflemen with a Henry" % rif)
	check(_count("rifleman", 40, {"henry": 0.0}) == 0, "a rifleman whose type says no with a Henry")
	var tir := _count("tirador", 200, {"loadouts": [{"guns": ["rifle", "navy"], "weight": 1}]})
	check(tir >= 40 and tir <= 85, "%d of 200 tiradores with a Winchester got a Henry" % tir)
	for kind in ["cowboy", "bandido", "pistolero", "revolucionario", "poacher", "gambler", "jefe"]:
		check(_count(kind, 40) == 0, "a %s with a Henry" % kind)


## A dead man of this kind with this gun, a little off from the stranger: and the
## gun he dropped.
func _dead_man(kind: String, guns: Array, off := Vector2(60, 20)) -> Dictionary:
	var p: Player = game.player
	var at: Vector2 = p.global_position + off
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	var e: Enemy = game._add_enemy(kind, at, PackedVector2Array(), 0.0,
		{"henry": 0.0, "loadouts": [{"guns": guns, "weight": 1}]})
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
			p.arm(["colt", "henry"])
			check(p.weapons["rifle"].kind == "henry" and "rifle" in p.owned, "no Henry in his rifle slot")
			check(p.weapons["rifle"].reserve == p.belt.get("rifle", -1) and p.belt["rifle"] == Player.RESERVE["henry"],
				"his Henry's rounds aren't Winchester rounds on his belt (%s)" % p.belt)
			gun = _dead_man("rifleman", ["rifle"])
			check(not gun.is_empty() and gun["kind"] == "rifle", "no Winchester lying there")],
		[0.3, func():
			p.global_position = gun["at"]],
		[0.3, func():
			check(p.weapons["rifle"].kind == "henry", "walked over the Winchester and it swapped without F")
			game.swap_gun()
			check(p.weapons["rifle"].kind == "rifle", "the Winchester's not in his rifle slot (%s)" % p.weapons["rifle"].kind)
			check(p.weapons["rifle"].reserve == p.belt.get("rifle", -1), "not off the same rounds")
			var left: Array = game.loose_guns.filter(func(g): return g.get("his", false))
			check(left.size() == 1 and left[0]["kind"] == "henry", "his Henry isn't lying there")],
	]
