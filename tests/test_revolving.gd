extends SceneTree
## The Colt revolving shotgun (the test yard, its gang parked out of the way):
##   gun       - five chambers of shot on the Navy's powder, fired about as quick as
##               the Navy; then an age to load, each chamber charged and rammed.
##   chainfire - now and then (one shot in forty, near enough) every loaded chamber
##               goes off at once, wide, and the hand in front of the cylinder is burnt.
##   carriers  - some revolucionarios have one slung beside the sidearm, and some
##               sargentos have one for the coach gun; nobody else, and never a man
##               out of a door.
##   stranger  - it rides in his shotgun slot at 5 points, off the powder on his belt,
##               and has its poses baked. Burnt, he's a point down, nobody's to blame;
##               on his last bar it puts him in the last stand; a burn that kills him
##               says so on the end screen.
##   bandit    - burnt, he's a point down and doesn't turn on himself; burnt again, dead.
##   godot --headless --path . --fixed-fps 60 -s tests/test_revolving.gd

class MockGame:
	extends Node
	var shots := 0
	func sfx(_n: String, _p = null, _v := 0.0, _pv := 0.0) -> void: pass
	func spawn_bullet(_o, _v, _r, _d, _s, _h, _p, _pi := 0) -> void: shots += 1
	func muzzle_flash(_h, _d) -> void: pass
	func make_noise(_p, _r, _k, _s) -> void: pass
	func add_shake(_s) -> void: pass

class Hand:
	extends Actor
	var burns := 0
	func chain_burn() -> void: burns += 1

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	Engine.set_meta("no_last_stand", true)
	seed(41)
	_gun()
	_chainfire()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _time(w: Weapon, until: Callable, limit := 40.0) -> float:
	var s := 0.0
	while not until.call() and s < limit:
		w.update(0.02)
		s += 0.02
	return s


func _gun() -> void:
	step = "gun"
	var d: Dictionary = Weapon.DATA["colt55"]
	check(d["points"] == 5, "costs %d" % d["points"])
	check(d["cycle"] <= Weapon.DATA["navy"]["cycle"] * 1.2, "fires slower than the Navy is cocked")
	var g := MockGame.new()
	var a := Hand.new()
	a.game = g
	Weapon.chain_rng.seed = 5   # (no chainfire in these five: see _chainfire for that)
	var w := Weapon.new("colt55", a)
	check(w.ammo() == "powder" and w.is_shotgun() and w.action == "revolver", "not a revolving shotgun on powder")
	check(w.chambers.size() == 5 and w.loaded() == 5, "%d chambers, %d loaded" % [w.chambers.size(), w.loaded()])
	w.reserve = 20
	var n := 0
	var took := 0.0
	while w.can_fire() and n < 10:
		w.trigger()
		took += _time(w, func(): return w.state == Weapon.S.READY)
		n += 1
	check(n == 5 or a.burns > 0, "fired %d before it was empty" % n)
	check(took < 3.0, "five shots took %.1f s" % took)
	check(w.needs_reload(), "still loaded after five")
	check(w.start_reload(), "won't load")
	var filled := _time(w, func(): return w.state == Weapon.S.READY)
	check(filled > 8.0 and filled < 16.0, "empty to full in %.1f s" % filled)
	check(w.loaded() == 5 and w.reserve == 15, "%d loaded, %d left of 20" % [w.loaded(), w.reserve])
	print("  five shots in %.1f s, five loaded in %.1f s" % [took, filled])
	a.free()
	g.free()


## Fired a long while: how often they all go off, and what that does.
func _chainfire() -> void:
	step = "chainfire"
	var g := MockGame.new()
	var a := Hand.new()
	a.game = g
	var w := Weapon.new("colt55", a)
	w.reserve = 100000
	Weapon.chain_rng.seed = 173
	var pellets := int(Weapon.DATA["colt55"]["pellets"])
	var shots := 0
	var chains := 0
	while shots < 1200:
		if w.needs_reload():
			w.chambers.fill(1)   # (loaded at once: the reload's tested above)
		var live := w.loaded()
		var before: int = g.shots
		w.trigger()
		_time(w, func(): return w.state == Weapon.S.READY)
		shots += 1
		if g.shots - before > pellets:
			chains += 1
			check(g.shots - before == pellets * live, "%d chambers loaded and %d pellets went" % [live, g.shots - before])
			check(w.loaded() == 0, "chain-fired with %d left loaded" % w.loaded())
	print("  %d chainfires in %d shots" % [chains, shots])
	check(chains >= 12 and chains <= 60, "%d chainfires in %d shots (about one in forty)" % [chains, shots])
	check(a.burns == chains, "%d burns for %d chainfires" % [a.burns, chains])
	# no other revolver ever does it
	var colt := Weapon.new("colt", a)
	colt.reserve = 100000
	var n0 := a.burns
	for i in 300:
		if colt.needs_reload():
			colt.chambers.fill(1)
		colt.trigger()
		_time(colt, func(): return colt.state == Weapon.S.READY)
	check(a.burns == n0, "a Colt chain-fired")
	a.free()
	g.free()


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		var p: Player = game.player
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
		print("revolving test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


func _add(kind: String, overrides := {}) -> Enemy:
	var at := Iso.to_screen(Vector2(3.5, 20.5))
	return game._add_enemy(kind, at, PackedVector2Array(), 0.0, overrides.duplicate(true))


func _gone(e: Enemy) -> void:
	game.enemies.erase(e)
	e.cone.free()
	e.free()


## How many of `n` men of this kind come with a revolving shotgun.
func _count(kind: String, n: int, overrides := {}) -> int:
	var with := 0
	for i in n:
		var e := _add(kind, overrides)
		if "colt55" in e.loadout:
			with += 1
			check(e.loadout[0] == "colt55" and e.loadout.size() == 2 and e.loadout[1] in Enemy.PISTOLS,
				"a %s's revolving shotgun with %s" % [kind, e.loadout])
			check(not "coach" in e.loadout, "a %s with both" % kind)
		_gone(e)
	return with


func _carriers() -> void:
	step = "carriers"
	var rev := _count("revolucionario", 300)
	var sar := _count("sargento", 100)
	print("  revolucionarios: %d of 300 with one; sargentos: %d of 100" % [rev, sar])
	check(rev >= 5 and rev <= 40, "%d of 300 revolucionarios with one" % rev)
	check(sar >= 8 and sar <= 40, "%d of 100 sargentos with one" % sar)
	for kind in ["cowboy", "bandido", "soldadera", "tirador", "jefe", "general", "redscarf"]:
		check(_count(kind, 30) == 0, "a %s with one" % kind)
	check(_count("revolucionario", 60, {"pistols_only": true}) == 0, "a revolucionario out of his door with one")
	# the sargento's coach gun stays his type's for the next man
	check(game.enemy_type("sargento")["loadout"][0] == "coach", "the sargento's type lost its coach gun")


func _plan() -> void:
	var p: Player = game.player
	queue = [
		[0.2, func():
			step = "stranger"
			check(Player.SLOT["colt55"] == "coach" and "colt55" in Player.choices("coach"), "not on the shotgun card")
			p.arm(["colt", "colt55"])
			check(p.weapons["coach"].kind == "colt55" and "coach" in p.owned, "not in his shotgun slot")
			check(p.belt.get("powder", 0) == Player.RESERVE["colt55"], "his belt: %s" % p.belt)
			p.switch_to("coach")
			p.switch_t = 0.0
			for a in ["aim", "fire", "cock", "reload_open", "reload_eject", "reload_insert", "reload_close"]:
				check(p.has_anim(p._upper_key(a)), "no %s baked for it" % a)
			check(game.hud.BLURB.has("colt55"), "no line on the card")],
		[0.1, func():
			step = "bandit"
			var e := _add("revolucionario", {"revolving": 1.0, "loadouts": [{"guns": ["navy"], "weight": 1}],
				"champion": 0.0, "rollingblock": 0.0})
			e.process_mode = Node.PROCESS_MODE_DISABLED
			check(e.weapon.kind == "colt55", "came with %s" % e.weapon.kind)
			for a in ["aim", "fire", "cock", "reload_insert"]:
				check(e.has_anim(e._upper_key(a)), "no %s baked for a revolucionario" % a)
			e.hp = 2
			e.chain_burn()
			check(e.alive and e.hp == 1, "burnt: alive %s, hp %d" % [e.alive, e.hp])
			check(e.foe == null and e.st != Enemy.St.COMBAT, "he turned on himself")
			e.chain_burn()
			check(not e.alive and e.killed_with == "colt55", "burnt twice: alive %s, %s" % [e.alive, e.killed_with])
			var s := _add("sargento", {"revolving": 1.0, "loadouts": [{"guns": ["coach", "colt"], "weight": 1}]})
			check(s.loadout == ["colt55", "colt"] or s.loadout == ["colt55", "schofield"], "the sargento's %s" % [s.loadout])
			check(s.has_anim(s._upper_key("reload_insert")), "no reload baked for a sargento")
			_gone(s)],
		[0.1, func():
			step = "burnt"
			p.hp = 3
			p.chain_burn()
			check(p.alive and p.hp == 2, "burnt: alive %s, hp %d" % [p.alive, p.hp])
			Engine.remove_meta("no_last_stand")   # on his last bar: down in the dirt, as for any wound
			p.hp = 1
			p.chain_burn()
			check(p.alive and p.down, "burnt on his last bar: alive %s, down %s" % [p.alive, p.down])
			Engine.set_meta("no_last_stand", true)
			p.down = false   # (up again, by the test's hand: the last stand's tested in test_laststand)
			p.propped = false
			p.hp = 1
			p.chain_burn()
			check(not p.alive and p.death.get("how") == "chainfire", "burnt to death: %s" % p.death)
			var why: PackedStringArray = game.why_dead()
			check("all at once" in why[0] and why[1].contains("at once"), "the end screen says %s" % why)
			print("  %s %s" % [why[0], why[1]])],
	]
