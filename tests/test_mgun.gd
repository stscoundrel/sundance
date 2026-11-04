extends SceneTree
## The Colt-Browning at Paso Esperanza (scripts/mgun.gd), and the machine guns carried
## off the train:
##   gun      - in its nest at the breastwork's corner, one belt of 250; the stranger
##              gets on it from his place behind, and off again.
##   arc      - it swings only so fast, and no further than half a circle to the south
##              and east, whatever he wants.
##   fire     - held, seven or eight rounds a second; over its own nest (no harm to
##              it), into the men in front; a round through a man and into the next.
##   belt     - spent, it's silent; and off it, his own guns shoot as true as ever
##              (a belt through the gun is no bloom on his hands').
##   carried  - the machine-gun carrier takes the guns off first, each worth three
##              loads, then goes on to the cases.
##   godot --headless --path . --fixed-fps 60 -s tests/test_mgun.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var phase := "gun"
var mark := 0.0
var g: MGun
var line: Array = []
var fired0 := 0
var nest_hp := {}
var mg_man: Civilian
var loaded_before := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "train")
	Engine.set_meta("no_waves", true)
	seed(5)
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
		game.player.hp = 100000
	if frame <= 3:
		return false
	t += delta
	if t < 6.0:
		return false   # (the opening)
	if t > 300.0:
		check(false, "stuck in %s" % phase)
		return _finish()
	var p: Player = game.player
	match phase:
		"gun":
			step = "gun"
			g = game.mgun
			check(g != null and g.belt == 250, "no gun, or not a full belt")
			p.global_position = g.seat + Vector2(40, 0)
			check(not g.can_man(p.global_position), "on it from 40 px off")
			p.global_position = g.seat + Vector2(6, 3)
			check(g.can_man(p.global_position), "can't get on it from behind it")
			p.get_on(g)
			check(p.gun == g and g.gunner == p and p.anim_gun == "mgun", "not on it")
			p.set_physics_process(false)   # (the test has the gun, not his cursor)
			for prop in game.props:
				if prop["kind"] in ["nest_x", "nest_y"]:
					nest_hp[prop] = prop["hp"]
			check(nest_hp.size() == 5, "the nest isn't round it (%d pieces)" % nest_hp.size())
			phase = "arc"
			mark = t
		"arc":
			step = "arc"
			var before := g.aim
			g.drive(0.1, Vector2.UP, false)   # (straight back over his shoulder: no)
			check(absf(before.angle_to(g.aim)) <= MGun.TRAVERSE * 0.1 + 0.001, "swung %.2f rad in a tenth of a second" % absf(before.angle_to(g.aim)))
			if t - mark > 3.0:
				check(absf(g.centre.angle_to(g.aim)) <= MGun.ARC + 0.01, "out of its arc: %.2f rad off straight out" % g.centre.angle_to(g.aim))
				# a file of levas out on the east road, along where it's pointing
				g.aim = g.centre
				var dir := g.centre.rotated(-0.5)
				for i in 3:
					var e: Enemy = game._add_enemy("leva", g.global_position + dir * (110.0 + i * 14.0), PackedVector2Array(), 270.0, {})
					e.reaction = "cower"   # (held where they are)
					e.reaction_t = 99.0
					line.append(e)
				fired0 = game.stats.get("mg rounds", 0)
				phase = "aim"
				mark = t
		"aim":
			step = "fire"
			var dir2: Vector2 = (line[0].global_position - g.global_position).normalized()
			g.drive(delta, dir2, false)
			if absf(g.aim.angle_to(dir2)) < 0.01 or t - mark > 3.0:
				phase = "fire"
				mark = t
		"fire":
			step = "fire"
			var dir3: Vector2 = (line[0].global_position - g.global_position).normalized()
			if t - mark < 1.0:
				g.drive(delta, dir3, true)
				return false
			if t - mark < 2.0:
				return false   # (a second for the rounds to land)
			var n: int = game.stats.get("mg rounds", 0) - fired0
			check(n >= 6 and n <= 9, "%d rounds in a second" % n)
			check(g.belt == 250 - n, "the belt says %d" % g.belt)
			var dead := 0
			for e in line:
				if not e.alive:
					dead += 1
			check(dead >= 2, "only %d of the file down" % dead)
			for prop in nest_hp:
				check(prop["hp"] == nest_hp[prop], "its own rounds into its nest (%s %d -> %d)" % [prop["kind"], nest_hp[prop], prop["hp"]])
			g.belt = 3
			fired0 = game.stats.get("mg rounds", 0)
			phase = "belt"
			mark = t
		"belt":
			step = "belt"
			if t - mark < 1.5:
				g.drive(delta, g.aim, true)
				return false
			check(g.belt == 0 and game.stats.get("mg rounds", 0) - fired0 == 3, "%d left, %d fired" % [g.belt, game.stats.get("mg rounds", 0) - fired0])
			p.set_physics_process(true)
			p.get_off()
			check(p.gun == null and g.gunner == null and p.anim_gun == "", "still on it")
			check(p.bloom < 0.1, "off it, his own guns throw wide (bloom %.1f after a belt)" % p.bloom)
			for c in game.cargo.carriers:
				if c.kind == "cargador_mg":
					mg_man = c
			check(mg_man != null and mg_man.carries == "mg" and mg_man.anim_gun == "mgcarry", "no machine-gun carrier")
			loaded_before = game.cargo.loaded
			phase = "carried"
			mark = t
		"carried":
			step = "carried"
			if mg_man.carries == "case":
				check(mg_man.anim_gun == "case", "on to the cases, carrying them like machine guns")
				check(game.stats.get("loads", 0) >= 9, "three machine guns in, and only %d loads" % game.stats.get("loads", 0))
				return _finish()
			if t - mark > 200.0:
				check(false, "the machine guns never all went (%s, %d loaded)" % [mg_man.carries, game.cargo.loaded])
				return _finish()
	return false


func _finish() -> bool:
	print("mgun test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
