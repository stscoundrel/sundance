extends SceneTree
## The last gasp (every killing shot downs here, and every man who can, tries it;
## everyone else held still, out of town):
##   gasp    - a downed pistolero with the stranger in sight takes his Colt back from
##             the dirt, pushes himself up (slowly) and fires one to three rounds, well
##             apart, then sinks back: either dead of it or still down, his clock run on.
##   sidearm - a rifleman leaves his rifle lying and draws the Colt he never used.
##   no pistol - a poacher with only his Sharps never tries it.
##   shot    - one shot while he's up is finished, the gun falling, and it isn't
##             counted against the stranger as shooting a wounded man.
##   walk-up - the stranger right on a bandido whose comrade is on his way to drag him
##             clear: he doesn't wait for help, and the comrade's let off.
##   hope    - with a comrade close enough to come for him, he's less likely to try;
##             with the stranger right on him, likelier, comrade or no.
##   godot --headless --path . --fixed-fps 60 -s tests/test_lastgasp.gd

const SPOT := Vector2(26.0, 31.4)   # open main street

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var used: Array[Enemy] = []
var a: Enemy
var rise_at := -1.0
var shot_at: Array[float] = []
var shots0 := 0
var clock := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	Engine.set_meta("always_downed", true)
	Engine.set_meta("always_gasp", true)
	seed(12)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _take(kind: String) -> Enemy:
	for x in game.enemies:
		if x.alive and not x in used and x.kind == kind:
			used.append(x)
			return x
	return null


func _away() -> void:
	for x in used:
		if x.alive or x.downed:
			x.process_mode = Node.PROCESS_MODE_DISABLED
		x.global_position += Vector2(0, -4000)


func _here(dx := 0.0) -> Vector2:
	return Iso.to_screen(SPOT) + Vector2(dx, 0)


## Down in the street, the stranger up it in plain sight.
func _down(kind: String) -> Enemy:
	_away()
	var e := _take(kind)
	e.global_position = _here()
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.enter_combat(game.player.global_position, false, false)
	game.player.global_position = Iso.to_screen(SPOT - Vector2(4.5, 0))   # (up the street)
	e.take_hit(5, Vector2.RIGHT, game.player)
	check(e.downed, "a %s didn't go down" % kind)
	return e


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.alerted_once = true
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		_gasp()
	if frame <= 3:
		return false
	t += delta
	clock += delta
	if a and a.gasp != "" and rise_at < 0.0:
		rise_at = clock
	var n: int = game.stats.get("last gasp shot", 0)
	if n > shots0:
		shots0 = n
		shot_at.append(clock)
	if queue.is_empty():
		print("stats: ", game.stats)
		print("last gasp test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _gasp() -> void:
	step = "gasp"
	a = _down("pistolero")
	var hp0: int = game.player.hp
	queue = [[3.5, func():
		check(rise_at >= 0.0, "he never tried it")
		check(a.gasp_gun == "colt", "with a %s" % a.gasp_gun)
		check(not game.loose_guns.any(func(g): return g["under"] == a), "his Colt is still lying in the dirt")],
		[12.5, func():
			print("rose at %.1f s; shots at %s" % [rise_at, shot_at.map(func(x): return "%.1f" % (x - rise_at))])
			check(shot_at.size() >= 1 and shot_at.size() <= 3, "%d shots" % shot_at.size())
			check(rise_at >= 1.5, "he came up the moment he fell")
			check(shot_at.is_empty() or shot_at[0] - rise_at >= 1.8, "he fired too soon after coming up")
			for i in range(1, shot_at.size()):
				check(shot_at[i] - shot_at[i - 1] >= 2.3, "shots too close together")
			check(game.player.hp < hp0 or shot_at.size() > 0, "nothing fired")
			check(a.gasp == "", "still at it")
			var dead: bool = not a.downed and not a.alive
			var down: bool = a.downed and a.down_t > 14.0 + Enemy.GASP_COST - 0.5   # (16 s down, plus the cost)
			print("after: %s" % ("dead of it" if dead else "still down (%.1f s on the clock)" % a.down_t))
			check(dead or down, "neither dead nor down with his clock run on")
			check(game.loose_guns.any(func(g): return g["under"] == a), "the gun didn't fall from his hand")
			_sidearm()]]


func _sidearm() -> void:
	step = "sidearm"
	rise_at = -1.0
	a = _down("rifleman")
	queue.append([3.5, func():
		check(a.gasp_gun == "colt", "a rifleman should draw his Colt (%s)" % a.gasp_gun)
		check(game.loose_guns.any(func(g): return g["under"] == a and g["kind"] == "rifle"), "his rifle should stay lying")
		_no_pistol()])


func _no_pistol() -> void:
	step = "no pistol"
	var n0: int = game.stats.get("last gasp", 0)
	a = _down("poacher")
	queue.append([5.0, func():
		check(a.gasp == "" and game.stats.get("last gasp", 0) == n0, "a poacher came up with his Sharps")
		_shot()])


func _shot() -> void:
	step = "shot"
	a = _down("cowboy")
	queue.append([0.1, func(): _wait_aim(0.0)])


func _wait_aim(waited: float) -> void:
	if a.gasp != "aim" and waited < 5.0:
		queue.push_front([0.1, func(): _wait_aim(waited + 0.1)])
		return
	check(a.gasp == "aim", "he never got his gun up")
	var p: Player = game.player
	var wounded0: int = game.stats.get("wounded men shot", 0)
	var aim: Vector2 = a.aim_point()
	game.spawn_bullet(p.global_position, (aim - p.global_position).normalized() * 900.0, 400.0, 2, p, Iso.GUN_H, false)
	queue.push_front([0.5, func():
		check(not a.downed and not a.alive, "a round while he was up didn't finish him")
		check(game.stats.get("shot with his gun up", 0) == 1, "not counted as shooting a man with his gun up")
		check(game.stats.get("wounded men shot", 0) == wounded0, "counted as shooting a wounded man")
		check(game.loose_guns.any(func(g): return g["under"] == a), "his gun didn't fall")
		_walk_up()])


func _walk_up() -> void:
	step = "walk-up"
	_away()
	a = _take("bandido")
	a.global_position = _here()
	a.process_mode = Node.PROCESS_MODE_INHERIT
	game.player.global_position = Iso.to_screen(SPOT - Vector2(20.0, 0))   # (well off, round the corner)
	a.take_hit(5, Vector2.RIGHT, game.player)
	var mate := _take("bandido")
	mate.global_position = Iso.to_screen(SPOT + Vector2(9.0, 0))
	mate.process_mode = Node.PROCESS_MODE_INHERIT
	mate.start_rescue(a)
	queue.append([0.3, func():
		check(a.rescuer == mate and a.gasp == "", "the setup: his comrade should be on his way")
		game.player.global_position = Iso.to_screen(SPOT - Vector2(3.0, 0))])   # walks right up on him
	queue.append([4.0, func():
		check(a.gasp != "", "he waited for his comrade with the stranger right on him")
		check(a.rescuer == null and mate.rescuing == null, "his comrade's still coming for him")
		mate.process_mode = Node.PROCESS_MODE_DISABLED
		_hope()])


func _hope() -> void:
	step = "hope"
	Engine.remove_meta("always_gasp")
	_away()
	var e := _take("pistolero")
	if e == null:
		e = _take("cowboy")
	e.global_position = _here(300)
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.take_hit(5, Vector2.RIGHT, game.player)
	var alone: float = e.gasp_chance()
	var mate := _take("bandido")
	mate.global_position = e.global_position + Vector2(60, 0)
	var hoping: float = e.gasp_chance()
	print("chance alone %.2f, with a comrade near %.2f" % [alone, hoping])
	check(alone > 0.0 and hoping < alone * 0.75, "a comrade near should make him wait to be saved")
	check(e.gasp_chance(true) > alone, "the stranger right on him should make him likelier to try")
	Engine.set_meta("always_gasp", true)
