extends SceneTree
## Cruz Verde's later fight, and what helps the stranger through it:
##   waves    - seven waves; the sixth comes after a lull, announced ("rallying their
##              troops outside the fort"), and the last two walk in badly armed: Navies
##              and single-shot horse pistols (a coronel at their head with his own).
##   pickups  - a bandage or a stick of dynamite lying in the dirt is his for walking
##              over it, one of each at a time (a second stays lying there); the dead
##              leave them now and then.
##   dynamite - lit (G), a wind-up, lobbed where he's aiming: it lands, fizzes, and
##              the men there go up with it.
##   rabble   - with a crowd of them round him, some of the rank and file stand there
##              wasting it: a round at the sky, or bawling the others on.
##   godot --headless --path . --fixed-fps 60 -s tests/test_rally.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var d: Director
var crowd: Array = []


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "cruz_verde")
	Engine.set_meta("no_alarm", true)
	seed(52)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		d = game.director
		d.set_process(false)
		for e in game.enemies:
			e.die(Vector2.RIGHT)
		var p: Player = game.player
		p.hp = 100000
		p.global_position = Iso.to_screen(Vector2(33.0, 30.5))
		_waves()
		_plan()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("stats: ", game.stats)
		print("rally test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _waves() -> void:
	step = "waves"
	check(d.waves.size() == 7, "%d waves" % d.waves.size())
	var total := 15
	for w in d.waves:
		for gr in w["groups"]:
			total += int(gr.get("count", gr.get("kinds", []).size()))
	print("  %d of the gang in all" % total)
	# the lull: word of them rallying, a while after the fifth
	d.roused = 0.0
	d.next = 5
	d.clock = float(d.waves[4]["at"]) + Director.RALLY_AFTER - 0.5
	d._process(1.0)
	check(game.hud.banner_text.contains("rallying"), "no word of the rally: %s" % game.hud.banner_text)
	check(d.next_in() > 40.0, "no lull: the next in %.0f s" % d.next_in())
	# the last two: badly armed (the coronel aside)
	d._send(d.waves[5])
	var guns := {}
	while not d.queue.is_empty():
		d._walk_in(d.queue.pop_front())
	for e in game.enemies.slice(game.enemies.size() - 13):
		guns[e.weapon.kind] = guns.get(e.weapon.kind, 0) + 1
		if e.kind == "coronel":
			check(e.weapon.kind in ["colt", "schofield"], "the coronel came with a %s" % e.weapon.kind)
		elif e.weapon.kind == "champion":   # (now and then one slung beside the pistol)
			check(e.loadout[1] in ["navy", "pistola"], "a %s's Champion with a %s" % [e.kind, e.loadout[1]])
		else:
			check(e.weapon.kind in ["navy", "pistola"], "a %s came with a %s" % [e.kind, e.weapon.kind])
	print("  the sixth wave's guns: %s" % guns)
	check(guns.get("pistola", 0) > 0, "no horse pistols")
	for e in game.enemies:
		e.die(Vector2.RIGHT)


func _plan() -> void:
	var p: Player = game.player
	queue = [
		[0.3, func():
			step = "pickups"
			p.bandages = 0
			p.sticks = 0
			game._drop_ammo("bandage", p.global_position + Vector2(30, 0))
			game._drop_ammo("bandage", p.global_position + Vector2(-30, 0))
			game._drop_ammo("dynamite", p.global_position + Vector2(0, 14))
			game._drop_ammo("dynamite", p.global_position + Vector2(0, -14))],
		[0.3, func():
			p.global_position += Vector2(30, 0)],
		[0.3, func():
			p.global_position += Vector2(-60, 0)],
		[0.3, func():
			p.global_position += Vector2(30, 14)],
		[0.3, func():
			p.global_position += Vector2(0, -28)],
		[0.3, func():
			check(p.bandages == 1, "%d bandages (one at a time)" % p.bandages)
			check(p.sticks == 1, "%d sticks (one at a time)" % p.sticks)
			var lying := 0
			for n in game.world.get_children():
				if n is Pickup and n.kind in ["bandage", "dynamite"] and not n.is_queued_for_deletion() \
						and n.position.distance_to(p.global_position) < 60.0:
					lying += 1
			check(lying == 2, "%d left lying (the second of each should be)" % lying)
			# the dead leave them now and then
			var left := 0
			for i in 40:
				var e: Enemy = game._add_enemy("revolucionario", Iso.to_screen(Vector2(40, 40)) + Vector2(i * 3, 0), PackedVector2Array(), 0.0)
				e.die(Vector2.RIGHT)
			for n in game.world.get_children():
				if n is Pickup and n.kind in ["bandage", "dynamite"]:
					left += 1
			print("  40 dead left %d bandages and sticks" % left)
			check(left > 10 and left < 40, "%d left by 40 dead" % left)
			step = "dynamite"
			for n in game.world.get_children():
				if n is Pickup:
					n.queue_free()   # (the dead's leavings: not to be walked over now)
			p.global_position = Iso.to_screen(Vector2(33.0, 30.5))
			var at := Iso.to_screen(Vector2(36.5, 30.5))
			for off in [Vector2(0, 0), Vector2(14, 6), Vector2(-10, 8)]:
				var e: Enemy = game._add_enemy("bandido", at + off, PackedVector2Array(), 180.0)
				e.process_mode = Node.PROCESS_MODE_DISABLED   # (stood there: no dodging)
				crowd.append(e)
			game._args["throw-at"] = "36.5,30.5"
			check(p.light_stick(), "won't light it")
			check(p.sticks == 0, "the stick's still on him")],
		[1.0, func():
			check(p.stick == null, "never let go of it")],
		[3.0, func():
			check(game.stats.get("blasts", 0) >= 1, "it never went off")
			check(crowd.all(func(e): return not e.alive), "%d stood through it" % crowd.filter(func(e): return e.alive).size())
			check(game.stats.get("his kills", 0) >= 3, "not counted as his")
			game._args.erase("throw-at")
			step = "rabble"
			crowd.clear()
			for i in 9:
				var at: Vector2 = p.global_position + Vector2.from_angle(i * TAU / 9.0) * 150.0
				if not game.is_free(at):
					at = game.free_point_near(at, 30.0)
				var e: Enemy = game._add_enemy("revolucionario", at, PackedVector2Array(), 0.0, {"loadouts": [{"guns": ["navy"], "weight": 1}]})
				e.enter_combat(p.global_position, false, false)
				crowd.append(e)],
		[14.0, func():
			var sky: int = game.stats.get("rounds at the sky", 0)
			var cheers: int = game.stats.get("rabble cheers", 0)
			print("  nine revolucionarios round him, 14 s: %d rounds at the sky, %d cheers" % [sky, cheers])
			check(sky + cheers >= 2, "no rabble at all")
			check(sky + cheers < 30, "nothing but rabble")],
	]
