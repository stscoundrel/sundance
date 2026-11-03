extends SceneTree
## The stranger's last stand (the test yard, its gang parked out of the way):
##   down     - the shot that should kill him puts him down instead: alive, one bar,
##              propped up with his Colt, slower; he fires from the dirt. He bleeds
##              out in the end, and the end screen counts his kills.
##   boot     - without a Colt, a revolver comes out of his boot. A bandage gets him
##              up, the gun he had back in his hand; the next killing shot kills: it's
##              once a level.
##              He can drag himself round to face behind him, but not at once.
##   finish   - a gunslinger who sees him lying there walks up to finish him; shot
##              from the dirt, and the rest of them after, it's a win.
##   rise     - three of them dropped from the dirt (one through take_hit, as a keg's
##              blast comes) and he's up: one bar, still bleeding, his bandage kept,
##              and the one left watching shaken; two isn't enough.
##   godot --headless --path . --fixed-fps 60 -s tests/test_laststand.gd

var game: Node
var phase := 0
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var shooter: Enemy
var walker: Enemy
var walker_from := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "test_yard")
	_start()


func _start() -> void:
	seed(40 + phase)
	if game:
		game.queue_free()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	frame = 0
	t = 0.0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		Engine.time_scale = 1.0
		var p: Player = game.player
		p.global_position = Iso.to_screen(Vector2(12, 12))
		for e in game.enemies:   # (out of the way, alive: or the yard's won)
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position = Iso.to_screen(Vector2(1.5, 22.5))
		shooter = game.enemies[0]
		[_down, _boot, _finish, _rise][phase].call()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		phase += 1
		if phase < 4:
			_start()
			return false
		print("last stand test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _down() -> void:
	step = "down"
	var p: Player = game.player
	p.arm(["colt", "coach"])
	p.switch_to("coach")
	p.hp = 1
	queue = [
		[0.2, func():
			p.take_hit(2, Vector2.RIGHT, shooter)
			check(p.alive and p.down and p.hp == 1, "not down (alive %s, down %s)" % [p.alive, p.down])
			check(p.weapon.kind == "colt" and p.weapon.slow > 1.0, "no Colt in his hand (%s)" % p.weapon.kind)
			check(p.held_before == "coach", "forgot the gun he had")
			check(p.lie_facing.dot(Vector2.LEFT) > 0.9, "not lying feet towards the shot")
			check(game.stats.get("last stand", 0) == 1, "not counted")],
		[1.8, func():
			var behind := -p.facing
			for i in 30:
				p.swing_to(behind, 1.0 / 60.0)
			check(p.facing.dot(behind) < 0.5, "turned right round in half a second")
			for i in 60:
				p.swing_to(behind, 1.0 / 60.0)
			check(p.facing.dot(behind) > 0.99, "can't face behind him (%.2f)" % p.facing.dot(behind))
			check(p.lie_facing.dot(behind) > 0.99, "his boots didn't come round with him")
			check(p._death.ends_with("gasp_aim"), "not up on his elbow with the gun (%s)" % p._death)
			p.weapon.trigger()
			check(p._death.ends_with("gasp_fire") and p.weapon.loaded() == 5, "didn't fire from the dirt")
			p.down_t = Player.STAND_BLEED - 1.0],
		[1.4, func():
			check(not p.alive and game.state == "lost", "never bled out (%s)" % game.state)
			check(game.stats.get("bled out", 0) == 1, "not counted as bleeding out")
			check(game.hud.sub.contains("by your hand"), "the end screen doesn't count his kills: %s" % game.hud.sub)],
	]


func _boot() -> void:
	step = "boot"
	var p: Player = game.player
	p.arm(["coach", "rifle"])
	p.switch_to("rifle")
	p.hp = 1
	p.bandages = 1
	queue = [
		[0.2, func():
			p.take_hit(2, Vector2.UP, shooter)
			check(p.down and p.boot != null and p.weapon == p.boot, "no gun from his boot")
			check(p.weapon.kind in Player.BOOT_GUNS and p.weapon.loaded() == 6, "the boot gun's a %s with %d in it" % [
				p.weapon.kind, p.weapon.loaded()])],
		[1.8, func():
			check(p.start_bandage(), "won't bandage lying there")],
		[Player.STAND_BANDAGE_T + 0.3, func():
			check(not p.down and p.alive and p.hp == 1 and p.bandages == 0, "didn't get up (down %s, hp %d)" % [p.down, p.hp])
			check(p.current == "rifle" and p.weapon == p.weapons["rifle"], "not his own gun back (%s)" % p.weapon.kind)
			check(p.legs_spr.visible and not p.propped, "still drawn lying down")
			p.take_hit(2, Vector2.UP, shooter)
			check(not p.alive and not p.down, "a second last stand")],
	]


func _finish() -> void:
	step = "finish"
	var p: Player = game.player
	p.arm(["colt"])
	p.hp = 1
	var at: Vector2 = p.global_position + Vector2(150, 0)
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	walker = game._add_enemy("gunslinger", at, PackedVector2Array(), 180.0)
	queue = [
		[0.3, func():
			walker.enter_combat(p.global_position, false, false)],
		[0.5, func():
			p.take_hit(2, (p.global_position - walker.global_position).normalized(), walker)
			check(p.down, "not down")
			check(walker.finishing, "the gunslinger didn't come to finish him")
			walker_from = walker.global_position.distance_to(p.global_position)],
		[3.5, func():
			var d := walker.global_position.distance_to(p.global_position)
			print("  the gunslinger walked from %.0f px to %.0f" % [walker_from, d])
			check(d < walker_from - 50.0, "he never came closer")
			check(p.down and p.alive, "he's dead already")
			for e in game.enemies:
				if e != walker:
					e.die(Vector2.RIGHT, p)
			walker.die(Vector2.RIGHT, p)],
		[0.5, func():
			check(game.state == "won", "not a win from the dirt (%s)" % game.state)
			check(game.stats.get("kills while down", 0) == 5 and game.stats.get("his kills", 0) == 5, "kills %s" % game.stats)
			check(game.hud.message == "FROM THE DIRT" and game.hud.sub.contains("5 of the gang by your hand (5 from the dirt)"),
				"the end screen says: %s / %s" % [game.hud.message, game.hud.sub])],
	]


func _rise() -> void:
	step = "rise"
	var p: Player = game.player
	p.arm(["colt"])
	p.hp = 1
	p.bandages = 1
	var watcher: Enemy = game.enemies[3]
	queue = [
		[0.2, func():
			watcher.global_position = game.free_point_near(p.global_position + Vector2(90, 0), 30.0)
			p.take_hit(2, Vector2.RIGHT, shooter)
			check(p.down, "not down")],
		[1.8, func():
			game.enemies[0].die(Vector2.RIGHT, p)
			game.enemies[1].take_hit(10, Vector2.RIGHT, p)],
		[0.3, func():
			check(p.down and p.dirt_drops == 2, "up after two (down %s, drops %d)" % [p.down, p.dirt_drops])
			game.enemies[2].die(Vector2.RIGHT, p)],
		[0.2, func():
			check(not p.down and p.alive and p.hp == 1, "not up after three (down %s, hp %d)" % [p.down, p.hp])
			check(p.bleeding, "the bleeding stopped on its own")
			check(p.bandages == 1, "used his bandage getting up")
			check(p.weapon == p.weapons["colt"] and p.weapon.slow == 1.0, "not his Colt, two-handed")
			check(game.stats.get("rose from the dirt", 0) == 1, "not counted")
			check(game.state == "play", "the fight's over (%s)" % game.state)
			check(watcher.shaken >= 0.5, "the one watching wasn't shaken (%.2f)" % watcher.shaken)
			check(p.start_bandage(), "won't bandage after")],
		[Player.BANDAGE_T + 0.3, func():
			check(not p.bleeding and p.bandages == 0, "the bandage didn't stop it")
			p.take_hit(p.hp + 1, Vector2.UP, shooter)
			check(not p.alive and not p.down, "a second last stand")
			check(game.hud.sub.contains("3 from the dirt, and up again"), "the end screen says: %s" % game.hud.sub)],
	]
