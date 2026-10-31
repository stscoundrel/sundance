extends SceneTree
## Headless checks for the weapon state machines:
##   godot --headless --path . -s tests/test_weapons.gd

class MockGame:
	extends Node
	var shots := 0
	var sounds: Array[String] = []
	func sfx(n: String, _p = null, _v := 0.0, _pv := 0.0) -> void: sounds.append(n)
	func spawn_bullet(_o, _v, _r, _d, _s, _h, _p, _pi := 0) -> void: shots += 1
	func muzzle_flash(_h, _d) -> void: pass
	func make_noise(_p, _r, _k, _s) -> void: pass

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func run(w: Weapon, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		w.update(0.02)
		t += 0.02


func _init() -> void:
	var g := MockGame.new()
	var a := Actor.new()
	a.game = g

	# Colt: six shots, cocking between them, then a dry click.
	var colt := Weapon.new("colt", a)
	colt.reserve = 10
	for i in 6:
		check(colt.can_fire(), "colt can fire shot %d" % (i + 1))
		colt.trigger()
		check(not colt.can_fire(), "colt must be cocked again after shot %d" % (i + 1))
		run(colt, 0.4)
	check(g.shots == 6, "colt fired 6 bullets (got %d)" % g.shots)
	check(colt.needs_reload(), "colt empty after 6")
	# Reload: eject and load each chamber one at a time.
	check(colt.start_reload(), "colt reload starts")
	run(colt, 10.0)
	check(colt.chambers.count(1) == 6, "colt fully reloaded (%s)" % [colt.chambers])
	check(colt.reserve == 4, "colt reserve 10 - 6 = 4 (got %d)" % colt.reserve)
	check(colt.can_fire(), "colt cocked after closing the gate")
	# Partial reload: fire 3, start reloading, interrupt after the first round.
	for i in 3:
		colt.trigger()
		run(colt, 0.4)
	colt.start_reload()
	run(colt, 0.7)
	colt.trigger()   # stop request
	run(colt, 2.0)
	check(colt.state == Weapon.S.READY, "colt ready after interrupted reload")
	check(colt.chambers.count(1) < 6 and colt.chambers.count(1) > 3, "colt partially reloaded (%s)" % [colt.chambers])
	# Fanning empties the cylinder quickly.
	colt.chambers = [1, 1, 1, 1, 1, 1]
	g.shots = 0
	colt.fanning = true
	run(colt, 1.0)
	check(g.shots == 6, "fanning fires 6 in a second (got %d)" % g.shots)
	colt.fanning = false

	# Coach gun: one barrel at a time, then both at once.
	var coach := Weapon.new("coach", a)
	coach.reserve = 4
	g.shots = 0
	coach.trigger()
	run(coach, 0.3)
	coach.trigger()
	run(coach, 0.3)
	check(g.shots == 18, "two barrels, 9 pellets each (got %d)" % g.shots)
	check(coach.needs_reload(), "coach empty")
	coach.start_reload()
	run(coach, 3.0)
	check(coach.barrels == [1, 1] and coach.reserve == 2, "coach reloaded both (%s, %d)" % [coach.barrels, coach.reserve])
	g.shots = 0
	coach.alt_trigger()
	check(g.shots == 18, "both barrels at once (got %d)" % g.shots)

	# Winchester: lever between shots, 13 rounds total.
	var rifle := Weapon.new("rifle", a)
	rifle.reserve = 5
	g.shots = 0
	var ejections := 0
	for i in 20:
		rifle.trigger()
		if rifle.ejecting:
			ejections += 1
		run(rifle, 0.5)
	check(g.shots == 13, "rifle holds 13 (got %d)" % g.shots)
	check(ejections == 13, "a case ejected per shot fired, none when empty (got %d)" % ejections)
	check(g.sounds.count("dry") >= 7, "empty rifle clicks dry")
	rifle.start_reload()
	run(rifle, 5.0)
	check(rifle.tube == 4 and rifle.chambered, "rifle loaded 5 and levered one in (tube %d, chambered %s)" % [rifle.tube, rifle.chambered])

	# Breech guns, all driven by the same data-described reload.
	var sharps := Weapon.new("sharps", a)
	sharps.reserve = 3
	g.shots = 0
	sharps.trigger()
	run(sharps, 0.6)
	check(g.shots == 1 and sharps.needs_reload(), "Sharps: one shot, then empty")
	sharps.trigger()
	run(sharps, 0.3)
	check(g.shots == 1, "Sharps clicks dry when empty")
	check(sharps.start_reload(), "Sharps reload starts")
	run(sharps, 3.0)
	check(sharps.loaded() == 1 and sharps.reserve == 2, "Sharps reloaded one round (%d, reserve %d)" % [sharps.loaded(), sharps.reserve])

	var howdah := Weapon.new("howdah", a)
	howdah.reserve = 2
	g.shots = 0
	howdah.alt_trigger()
	check(g.shots == 2 and howdah.needs_reload(), "howdah: both barrels at once")
	run(howdah, 1.0)
	howdah.start_reload()
	run(howdah, 4.0)
	check(howdah.loaded() == 2 and howdah.reserve == 0, "howdah reloaded both")

	var der := Weapon.new("derringer", a)
	der.reserve = 2
	g.shots = 0
	for i in 3:
		der.trigger()
		run(der, 0.6)
	check(g.shots == 2, "derringer holds two (got %d)" % g.shots)
	der.alt_trigger()
	check(g.shots == 2, "derringer has no volley")

	# A pair of Colts: twelve shots, right hand then left, quicker than one gun.
	var pair := Weapon.new("colts", a)
	pair.reserve = 20
	g.shots = 0
	var hands: Array[int] = []
	for i in 13:
		pair.trigger()
		hands.append(pair.hand)
		run(pair, 0.2)
	check(g.shots == 12, "pair fires 12 (got %d)" % g.shots)
	check(hands.slice(0, 4) == [0, 1, 0, 1], "pair alternates hands (%s)" % [hands])
	check(pair.needs_reload(), "pair empty after 12")
	check(pair.start_reload(), "pair reload starts")
	run(pair, 20.0)
	check(pair.loaded() == 12 and pair.reserve == 8, "pair reloaded 12 (%d, reserve %d)" % [pair.loaded(), pair.reserve])
	check(pair.can_fire(), "pair ready after reload")

	# Sawn-off: a coach gun cut short. Same shells and volley, a wider pattern that
	# dies off sooner, and a quicker reload.
	var sawn := Weapon.new("sawnoff", a)
	var cg: Dictionary = Weapon.DATA["coach"]
	check(sawn.is_shotgun() and coach.is_shotgun() and not colt.is_shotgun(), "shotguns know they're shotguns")
	check(sawn.d["ammo"] == "coach", "the sawn-off takes coach gun shells")
	check(sawn.d["spread"] > cg["spread"] and sawn.d["range"] < cg["range"], "sawn-off: wider and shorter than the coach gun")
	sawn.reserve = 4
	g.shots = 0
	sawn.alt_trigger()
	check(g.shots == 18, "sawn-off fires both barrels at once (got %d)" % g.shots)
	run(sawn, 0.5)
	var t0 := 0.0
	check(sawn.start_reload(), "sawn-off reload starts")
	while (sawn.is_reloading() or not sawn.can_fire()) and t0 < 10.0:
		run(sawn, 0.05)
		t0 += 0.05
	var tc: float = cg["open"][0] + cg["eject"][0] + cg["insert"][0] * 2 + cg["close"][0]
	check(t0 < tc, "sawn-off reloads quicker than the coach gun (%.2f vs %.2f s)" % [t0, tc])

	# Colt Navy, cap-and-ball: six, a little weaker, and an age to reload (a Colt
	# reloads all six in a few seconds).
	var navy := Weapon.new("navy", a)
	navy.reserve = 12
	check(navy.d["damage"] < Weapon.DATA["colt"]["damage"], "the Navy should hit softer than the Colt")
	g.shots = 0
	for i in 7:
		navy.trigger()
		run(navy, 0.5)
	check(g.shots == 6, "Navy fires 6 (got %d)" % g.shots)
	var navy_t := 0.0
	check(navy.start_reload(), "Navy reload starts")
	while navy.is_reloading() and navy_t < 30.0:
		run(navy, 0.1)
		navy_t += 0.1
	var colt_t := 0.0
	var colt2 := Weapon.new("colt", a)
	colt2.reserve = 12
	colt2.chambers.fill(2)
	colt2.start_reload()
	while colt2.is_reloading() and colt_t < 30.0:
		run(colt2, 0.1)
		colt_t += 0.1
	check(navy.loaded() == 6, "Navy reloaded all six (%d)" % navy.loaded())
	check(navy_t > colt_t * 2.0, "a cap-and-ball reload should take far longer (%.1f vs %.1f s)" % [navy_t, colt_t])

	a.free()
	g.free()
	print("weapons: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
