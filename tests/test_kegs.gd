extends SceneTree
## Powder kegs and crates of dynamite (Cruz Verde's):
##   keg      - a round into a keg: it fizzes about a second, then goes up, and the
##              men round it go with it; the barrel beside it is wrecked.
##   officer  - a coronel near a fizzing keg (the south gate's) runs for it and lives;
##              a revolucionario beside him blunders on.
##   chain    - a crate of dynamite shot burns a few seconds, then goes up and sets
##              off the keg by the north gate a moment after.
##   stray    - a round from one of the gang's own guns sets one off just the same.
##   godot --headless --path . --fixed-fps 60 -s tests/test_kegs.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var men: Array = []
var officer: Enemy
var private: Enemy
var officer_from := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "cruz_verde")
	Engine.set_meta("no_captive", true)   # (nobody at the pole: see test_captive)
	Engine.set_meta("no_alarm", true)
	seed(31)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _near(kind: String, gx: float, gy: float) -> Dictionary:
	var at := Iso.to_screen(Vector2(gx, gy))
	var best: Dictionary = {}
	for p in game.props:
		if p["kind"] == kind and (best.is_empty() or game.prop_centre(p).distance_to(at) < game.prop_centre(best).distance_to(at)):
			best = p
	return best


func _man(kind: String, at: Vector2) -> Enemy:
	if not game.is_free(at):
		at = game.free_point_near(at, 20.0)
	return game._add_enemy(kind, at, PackedVector2Array(), 90.0)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.director.set_process(false)   # (nobody out of the doors, no waves)
		for e in game.enemies:
			e.die(Vector2.RIGHT)
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(15.0, 26.2))
		_plan()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("stats: ", game.stats)
		print("kegs test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _plan() -> void:
	var west := _near("keg", 18.75, 27.25)
	var beside := _near("barrel", 19.4, 27.3)
	var north_crate := _near("dyn_crate", 28.2, 19.6)
	var north_keg := _near("keg", 29.35, 17.15)
	var east := _near("keg", 45.95, 32.75)
	var south := _near("keg", 28.85, 44.65)
	queue = [
		[0.2, func():
			step = "keg"
			var c: Vector2 = game.prop_centre(west)
			for off in [Vector2(20, 6), Vector2(-14, 18), Vector2(30, -4)]:
				men.append(_man("revolucionario", c + off))
			check(game.hit_prop(west, 2, 0, c, game.player) == false, "the round went through the keg")
			check(west.get("lit", false), "the keg isn't fizzing")],
		[0.8, func():
			check(west["state"] == 0 and game.stats.get("kegs blown", 0) == 0, "it went up too soon")],
		[0.4, func():
			check(west["state"] == 2 and game.stats.get("kegs blown", 0) == 1, "it never went up")
			check(men.all(func(e): return not e.alive), "%d lived through it" % men.filter(func(e): return e.alive).size())
			check(beside["state"] >= 1, "the barrel beside it is untouched")
			step = "officer"
			var c: Vector2 = game.prop_centre(south)
			officer = _man("coronel", c + Vector2(64, -16))
			private = _man("revolucionario", c + Vector2(40, -8))
			officer_from = officer.global_position.distance_to(c)
			game.hit_prop(south, 2, 0, c, game.player)],
		[1.3, func():
			var c: Vector2 = game.prop_centre(south)
			print("  the coronel %.0f px off when it went (from %.0f); the private %s" % [
				officer.global_position.distance_to(c), officer_from, "alive" if private.alive else "dead"])
			check(officer.alive, "the coronel didn't get clear")
			check(officer.global_position.distance_to(c) > officer_from + 20.0, "the coronel never ran")
			check(private.reaction != "clear", "the private ran too: he's meant to blunder")
			step = "chain"
			game.hit_prop(north_crate, 2, 0, game.prop_centre(north_crate), game.player)],
		[2.5, func():
			check(north_crate["state"] == 0, "the dynamite went up before it had burnt")],
		[0.7, func():
			check(north_crate["state"] == 2, "the dynamite crate never went up")
			check(north_keg.get("lit", false), "the blast didn't reach the north keg")],
		[0.5, func():
			check(north_keg["state"] == 2, "the north keg didn't follow")
			step = "stray"
			var c: Vector2 = game.prop_centre(east)
			var shooter := _man("revolucionario", c + Vector2(-70, 0))
			var dir := (c + Vector2(0, -2) - shooter.global_position).normalized()
			game.spawn_bullet(shooter.global_position, dir * 650.0, 380.0, 2, shooter, shooter.gun_height(), false, 0)],
		[1.8, func():
			check(east["state"] == 2, "the gang's stray round didn't set it off")],
	]
