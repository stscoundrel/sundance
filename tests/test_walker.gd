extends SceneTree
## The Colt Walker 1847, the stranger's cheap hand cannon (the test yard, its gang
## parked out of the way):
##   card    - on the sidearm card for 3, after the Colt and the Schofield (4 now)
##             and before the Navy; the pair of Colts dearest at 7.
##   gun     - hits harder than the Colt, louder, more smoke than any revolver, and
##             can't be fanned.
##   heavy   - an old-timer, who takes two from the Colt, goes down to one ball.
##   rammer  - now and then the kick drops the loading lever: the next cocking waits
##             while he knocks it back up, RAMMER DOWN on the gun's line, and its own
##             animation; most shots it stays put.
##   reload  - powder and ball off the Navy's belt, slower even than the Navy.
##   godot --headless --path . --fixed-fps 60 -s tests/test_walker.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var men: Array[Enemy] = []


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	Engine.set_meta("no_downed", true)
	Engine.set_meta("no_gasp", true)
	seed(7)
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
		_card()
		_gun()
		_plan()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("walker test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		if c.call() == false:   # (not yet: ask again next frame)
			queue.push_front([0.0, c])
	return false


func _card() -> void:
	step = "card"
	var side := Player.choices("colt")
	check(side.slice(0, 5) == ["colts", "colt", "schofield", "walker", "navy"], "the sidearm card's top (%s)" % [side])
	check(Player.cost(["walker"]) == 3 and Player.cost(["colt"]) == 4 and Player.cost(["schofield"]) == 4
		and Player.cost(["colts"]) == 7, "the Walker 3, the Colt and Schofield 4, the pair 7")
	check(Player.SLOT["walker"] == "colt" and not "walker" in Player.TROPHIES, "the Walker isn't a sidearm on the card")


func _gun() -> void:
	step = "gun"
	var wd: Dictionary = Weapon.DATA["walker"]
	var colt: Dictionary = Weapon.DATA["colt"]
	check(wd["damage"] > colt["damage"], "the Walker hits no harder than the Colt")
	check(wd["noise"] > colt["noise"] + 60.0, "the Walker's no louder than the Colt (%d)" % wd["noise"])
	for k in Weapon.DATA:
		var o: Dictionary = Weapon.DATA[k]
		if k != "walker" and o["action"] == "revolver":
			check(wd["smoke"] > int(o.get("smoke", 9)), "the %s smokes as much as the Walker" % k)
	check(wd["smoke"] >= Weapon.DATA["coach"]["smoke"], "less smoke than a coach gun")
	check(wd.get("ammo", "") == "powder", "the Walker takes %s, not powder and ball" % wd.get("ammo", ""))


func _shoot_at(p: Player, kind: String, gun: String) -> Enemy:
	var at: Vector2 = p.global_position + Vector2(50, 0)
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	var e: Enemy = game._add_enemy(kind, at, PackedVector2Array(), 0.0, {})
	e.hurtbox.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE   # (still there to be hit)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	men.append(e)
	p.arm([gun])
	p.switch_to("colt")
	p.switch_t = 0.0
	p.facing = (e.global_position - p.global_position).normalized()
	p.weapons["colt"].trigger()
	return e


func _plan() -> void:
	var p: Player = game.player
	var e1: Array[Enemy] = []
	queue = [
		[0.1, func():
			step = "heavy"
			check(int(game.enemy_data["types"]["oldtimer"]["hp"]) == 3, "the old-timer isn't a three-hit man")
			e1.append(_shoot_at(p, "oldtimer", "colt"))],
		[0.6, func():
			check(e1[0].alive and e1[0].hp == 1, "one Colt round should leave an old-timer on 1 (alive %s, hp %d)" % [e1[0].alive, e1[0].hp])
			e1[0].queue_free()
			game.enemies.erase(e1[0])
			e1[0] = _shoot_at(p, "oldtimer", "walker")],
		[0.6, func():
			check(not e1[0].alive, "one Walker ball left an old-timer standing (hp %d)" % e1[0].hp)
			check(not p.has_anim(p._upper_key("fan")), "the Walker has a fanning animation")],
		[0.1, func():
			step = "rammer"
			p.arm(["walker"])
			p.switch_to("colt")
			p.switch_t = 0.0
			var w: Weapon = p.weapons["colt"]
			p.belt["powder"] = 1000
			check(p.has_anim(p._upper_key("rammer")), "no rammer animation for the Walker")
			var drops := 0
			var shots := 0
			var down_t := 0.0
			var up_t := 0.0
			var said := ""
			for i in 60:
				if w.needs_reload():
					w.start_reload()
					_time(w, func(): return w.state == Weapon.S.READY, 60.0)
				w.trigger()
				shots += 1
				var took := _time(w, func(): return w.state == Weapon.S.READY)
				if took > Weapon.DATA["walker"]["cycle"] + 0.4:
					drops += 1
					down_t = took
				else:
					up_t = took
			# one shot, watched: knock it down, and see the line and the wait
			w.rammer_down = false
			while not w.rammer_down:
				if w.needs_reload():
					w.start_reload()
					_time(w, func(): return w.state == Weapon.S.READY, 60.0)
				w.trigger()
				if not w.rammer_down:
					_time(w, func(): return w.state == Weapon.S.READY)
			said = w.status()
			check(said == "RAMMER DOWN", "a dropped rammer reads %s" % said)
			p.action_t = 0.0   # (past the kick)
			check(p._upper_choice() == "rammer", "he isn't seen to the rammer (%s)" % p._upper_choice())
			_time(w, func(): return w.state == Weapon.S.READY)
			check(not w.rammer_down and w.status() == "", "the rammer's still down after the wait")
			check(drops > 2 and drops < shots / 3, "the rammer dropped %d times in %d" % [drops, shots])
			check(down_t > up_t + 0.6, "a dropped rammer costs %.2f s against %.2f" % [down_t, up_t])
			print("  rammer down %d of %d shots, %.2f s to cock then against %.2f" % [drops, shots, down_t, up_t])],
		[0.1, func():
			step = "reload"
			p.arm(["walker"])
			var w: Weapon = p.weapons["colt"]
			check(p.belt.get("powder", 0) == Player.RESERVE["walker"], "its powder isn't on his belt (%s)" % p.belt)
			var navy := Weapon.new("navy", p)
			for g in [w, navy]:
				g.chambers.fill(0)
			p.belt["powder"] = 100
			w.start_reload()
			var wt := _time(w, func(): return w.state == Weapon.S.READY, 60.0)
			navy.start_reload()
			var nt := _time(navy, func(): return navy.state == Weapon.S.READY, 60.0)
			check(w.loaded() == 6 and navy.loaded() == 6, "not loaded (%d, %d)" % [w.loaded(), navy.loaded()])
			check(wt > nt * 1.1, "the Walker loads no slower than the Navy (%.1f vs %.1f s)" % [wt, nt])
			print("  six in: Walker %.1f s, Navy %.1f s" % [wt, nt])],
	]
