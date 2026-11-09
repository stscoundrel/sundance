extends SceneTree
## The Spencer 1882 pump gun (the test yard, its gang parked out of the way):
##   gun      - six shells (five in the tube, one up) of the coach gun's, 5 points,
##              the dearest gun with the Winchester; a 12 bore a little tighter and further than the
##              coach gun, no volley; the slide slower than any lever.
##   dry      - fired empty and loaded again, it takes two strokes (one long cycle)
##              before it'll fire; loaded with one still up, one stroke as ever.
##   loading  - a shell at a time through the port, and it can be stopped partway.
##   carriers - one El Jefe in three has it for his coach gun; nobody else.
##   stranger - it rides in his shotgun slot off the coach shells on his belt.
##   godot --headless --path . --fixed-fps 60 -s tests/test_pump.gd

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


func _initialize() -> void:
	_gun()
	_dry()
	_loading()
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


## A pump gun in a mock man's hands, with this many fired off.
func _with(fired: int) -> Array:
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g
	var w := Weapon.new("spencer82", a)
	w.reserve = 40
	for i in fired:
		w.trigger()
		_time(w, func(): return w.state == Weapon.S.READY)
	return [w, a, g]


func _free(got: Array) -> void:
	got[1].free()
	got[2].free()


func _gun() -> void:
	step = "gun"
	var sp: Dictionary = Weapon.DATA["spencer82"]
	var coach: Dictionary = Weapon.DATA["coach"]
	for k in Weapon.DATA:
		if k != "spencer82" and Weapon.DATA[k].has("points"):
			check(sp["points"] >= Weapon.DATA[k]["points"], "cheaper than the %s" % k)
	check(sp["points"] == 5, "costs %d" % sp["points"])
	check(Player.SLOT["spencer82"] == "coach" and "spencer82" in Player.choices("coach"), "not on the shotgun card")
	check(sp["spread"] < coach["spread"] and sp["range"] > coach["range"] and sp["pellets"] < coach["pellets"],
		"not a 12 bore a little tighter than the coach gun")
	check(not sp.get("volley", false), "it has barrels to loose together")
	for k in ["rifle", "henry", "spencer"]:
		check(sp["cycle"] >= Weapon.DATA[k]["cycle"], "the slide's quicker than the %s's lever" % k)
	var got := _with(0)
	var w: Weapon = got[0]
	check(w.ammo() == "coach" and w.is_shotgun(), "not a shotgun on the coach gun's shells")
	check(w.cap() == 5 and w.loaded() == 6, "holds %d in the tube, %d in all" % [w.cap(), w.loaded()])
	var n := 0
	while w.can_fire() and n < 20:
		w.trigger()
		_time(w, func(): return w.state == Weapon.S.READY)
		n += 1
	check(n == 6 and got[2].shots == 6 * int(sp["pellets"]), "fired %d (%d pellets) before it was empty" % [n, got[2].shots])
	check(w.dry, "fired empty and the carrier's not down")
	_free(got)


## Seconds from a reload's start to ready to fire, and whether it was a double stroke.
func _back_up(w: Weapon) -> Array:
	w.start_reload()
	_time(w, func(): return w.state == Weapon.S.CLOSE)
	_time(w, func(): return w.state != Weapon.S.CLOSE)
	var raced := w.racking
	var took := _time(w, func(): return w.state == Weapon.S.READY)
	return [took, raced]


func _dry() -> void:
	step = "dry"
	var cyc: float = Weapon.DATA["spencer82"]["cycle"]
	var got := _with(6)
	var w: Weapon = got[0]
	var r := _back_up(w)
	check(r[1] and r[0] > cyc * 1.8, "run dry, loaded and one stroke brought it up (%.2f s)" % r[0])
	check(w.can_fire() and not w.dry and w.chambered, "after two strokes it won't fire")
	check(w.loaded() == 5, "%d in it after loading five" % w.loaded())
	_free(got)
	# one still up: loading the tube is no reason to pump at all, let alone twice
	got = _with(5)
	w = got[0]
	check(w.chambered and not w.dry and w.tube == 0, "fired five and the sixth not up")
	r = _back_up(w)
	check(not r[1], "racked twice with a shell still up")
	check(w.loaded() == 6, "%d in it" % w.loaded())
	_free(got)
	# run dry and pumped by hand: the same two strokes from the trigger
	got = _with(6)
	w = got[0]
	w.reserve = 1
	w.start_reload()
	_time(w, func(): return w.state == Weapon.S.READY and not w.racking and w.chambered, 5.0)
	check(w.can_fire(), "one shell in, run dry, and it never came up")
	_free(got)
	print("  run dry, two strokes to bring one up (%.2f s each)" % cyc)


func _loading() -> void:
	step = "loading"
	var got := _with(3)
	var w: Weapon = got[0]
	w.start_reload()
	_time(w, func(): return w.state == Weapon.S.INSERT)
	w.trigger()   # stop after this one
	_time(w, func(): return w.state == Weapon.S.READY)
	check(w.loaded() == 4 and w.can_fire(), "stopped part way with %d in" % w.loaded())
	_free(got)


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
		print("pump test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


## How many of `n` men of this kind come with the pump gun.
func _count(kind: String, n: int, overrides := {}) -> int:
	var at := Iso.to_screen(Vector2(3.5, 20.5))
	var with := 0
	for i in n:
		var e: Enemy = game._add_enemy(kind, at, PackedVector2Array(), 0.0, overrides.duplicate(true))
		if "spencer82" in e.loadout:
			with += 1
			check(not "coach" in e.loadout, "a %s with a pump gun and a coach gun" % kind)
		game.enemies.erase(e)
		e.cone.free()
		e.free()
	return with


func _carriers() -> void:
	step = "carriers"
	var jefe := _count("jefe", 150)
	print("  jefe: %d of 150 with the pump gun" % jefe)
	check(jefe >= 30 and jefe <= 70, "%d of 150 Jefes with the pump gun" % jefe)
	for kind in ["redscarf", "sargento", "cowboy", "rifleman", "pistolero", "revolucionario"]:
		check(_count(kind, 40) == 0, "a %s with the pump gun" % kind)


func _plan() -> void:
	var p: Player = game.player
	queue = [
		[0.2, func():
			step = "stranger"
			p.arm(["colt", "spencer82"])
			check(p.weapons["coach"].kind == "spencer82" and "coach" in p.owned, "no pump gun in his shotgun slot")
			check(p.weapons["coach"].reserve == p.belt.get("coach", -1) and p.belt["coach"] == Player.RESERVE["spencer82"],
				"its shells aren't coach shells on his belt (%s)" % p.belt)],
	]
