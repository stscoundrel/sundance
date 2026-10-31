extends SceneTree
## Headless checks for the weapon state machines:
##   godot --headless --path . -s tests/test_weapons.gd

class MockGame:
	extends Node
	var shots := 0
	var sounds: Array[String] = []
	func sfx(n: String, _p = null, _v := 0.0, _pv := 0.0) -> void: sounds.append(n)
	func spawn_bullet(_o, _v, _r, _d, _s, _h, _p) -> void: shots += 1
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

	a.free()
	g.free()
	print("weapons: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
