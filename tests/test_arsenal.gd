extends SceneTree
## The revolution's guns:
##   guns     - the Spencer holds seven and wants lever and hammer between shots; the
##              Springfield and the escopeta take one charge and an age to load
##              (pour, ram, cap).
##   mix      - most revolutionaries carry revolvers; the long guns are there, fewer.
##   indoors  - those who dash out of the buildings come with their pistols (El
##              General excepted: his gun goes where he goes).
##   ditch    - an escopeta fired off, he throws it down and draws his revolver.
##   godot --headless --path . --fixed-fps 60 -s tests/test_arsenal.gd

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
var ditcher: Enemy
var ditched_at := -1.0
var out_checked := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _initialize() -> void:
	_guns()
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "cruz_verde")
	seed(23)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _time(w: Weapon, until: Callable, limit := 30.0) -> float:
	var s := 0.0
	while not until.call() and s < limit:
		w.update(0.02)
		s += 0.02
	return s


func _guns() -> void:
	step = "guns"
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g
	var sp := Weapon.new("spencer", a)
	sp.reserve = 20
	check(sp.loaded() == 8, "Spencer holds %d (7 in the tube, 1 up)" % sp.loaded())
	var fired := 0
	var s := 0.0
	while sp.loaded() > 0 and s < 30.0:
		if sp.can_fire():
			sp.trigger()
			fired += 1
		sp.update(0.02)
		s += 0.02
	check(fired == 8 and s > 7 * 0.8, "Spencer: %d shots in %.1f s" % [fired, s])
	for k in ["springfield", "escopeta"]:
		var w := Weapon.new(k, a)
		w.reserve = 5
		check(w.can_fire(), "%s not loaded" % k)
		w.trigger()
		_time(w, func(): return w.state == Weapon.S.READY)
		check(not w.can_fire() and w.needs_reload(), "%s fires more than once" % k)
		check(w.start_reload(), "%s won't load" % k)
		var took := _time(w, func(): return w.state == Weapon.S.READY)
		check(w.can_fire() and took > 6.0 and took < 9.0, "%s loaded in %.1f s" % [k, took])
		print("  %s: a charge rammed home in %.1f s" % [k, took])
	check(g.shots == 8 + 1 + 8, "%d shots, pellets and all" % g.shots)
	a.free()
	g.free()


func _mix() -> void:
	step = "mix"
	var e := Enemy.new()
	for kind in ["revolucionario", "soldadera", "tirador", "sargento"]:
		var n := {}
		var short := 0
		for i in 400:
			e.tdata = game.enemy_type(kind)
			var guns: Array = e._pick_loadout()
			n[guns[0]] = n.get(guns[0], 0) + 1
			short += 1 if guns[0] in Enemy.PISTOLS else 0
		print("  %s: %s" % [kind, n])
		if kind == "revolucionario":
			check(short > 260, "only %d of 400 with a revolver" % short)
			for k in ["spencer", "springfield", "escopeta"]:
				check(n.get(k, 0) > 10, "hardly a %s among them" % k)
		if kind == "soldadera":
			check(short >= 200, "only %d of 400 soldaderas with a revolver" % short)
		for i in 50:
			e.tdata = game.enemy_type(kind, {"pistols_only": true})
			var guns: Array = e._pick_loadout()
			check(guns.all(func(g): return g in Enemy.PISTOLS), "a %s out of doors with %s" % [kind, guns])
	e.free()


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		_mix()
		step = "indoors"
		game.begin()
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.make_noise(game.player.global_position, 380.0, "shot", game.player)
		game.last_gunfire = game.clock
		game.last_gunfire_at = game.player.global_position
	if frame <= 3:
		return false
	t += delta
	for e in game.enemies.slice(5 + out_checked) if ditcher == null else []:   # each as he comes out of his door
		out_checked += 1
		var gun: String = e.weapon.kind
		if e.kind == "general":
			check(gun == "coach", "El General came out with his %s" % gun)
		else:
			check(gun in Enemy.PISTOLS, "a %s came out with a %s" % [e.kind, gun])
	if t < 34.0:
		return false
	if ditcher == null:
		check(out_checked == 10, "%d came out" % out_checked)
		step = "ditch"
		for e in game.enemies:
			e.die(Vector2.RIGHT)
		var at: Vector2 = game.player.global_position + Vector2(90, 0)
		if not game.is_free(at):
			at = game.free_point_near(at, 40.0)
		ditcher = game._add_enemy("revolucionario", at, PackedVector2Array(), 180.0, {"loadouts": [
			{"guns": ["escopeta", "navy"], "weight": 1, "range": [30, 100], "draw_sidearm": 1.0}]})
		ditcher.hp = 1000
		game.player.process_mode = Node.PROCESS_MODE_INHERIT
		game.player.hp = 100000
		ditcher.enter_combat(game.player.global_position, false, false)
		t = 34.0
		return false
	if ditched_at < 0.0 and ditcher.weapon.kind == "navy":
		ditched_at = t - 34.0
		check(game.loose_guns.any(func(g): return g["kind"] == "escopeta"), "no escopeta lying in the dirt")
	if ditched_at < 0.0 and t < 60.0:
		return false
	check(ditched_at >= 0.0, "he kept his escopeta (%s)" % ditcher.weapon.kind)
	print("  fired the escopeta and drew his Navy %.1f s in" % ditched_at)
	print("arsenal test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
