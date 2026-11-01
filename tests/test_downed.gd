extends SceneTree
## Downed, not dead (every killing shot downs here; everyone else held still, out
## of town):
##   down    - a killing shot puts a bandido in the dirt: out of the fight (not
##             counted standing) but still there to hit.
##   bleed   - nobody comes for him: he bleeds out in 45 s.
##   finish  - another round finishes him (the stranger's tally of such kept, hidden).
##   rescue  - a comrade runs to him, drags him into cover and bandages him: the clock
##             stops while he's got him, and he gets up with 1 HP, gun in hand.
##   dropped - the rescuer shot dead mid-drag: he's left there, the clock running.
##   knife   - the knife finishes a downed man, quietly.
##   once    - a man who's been down and got up dies from the next one.
##   godot --headless --path . --fixed-fps 60 -s tests/test_downed.gd

const SPOT := Vector2(26.0, 31.4)   # open main street

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []
var used: Array[Enemy] = []
var a: Enemy
var b: Enemy
var at0 := Vector2.ZERO
var down0 := 0.0
var max_drag_t := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	Engine.set_meta("always_downed", true)
	seed(10)
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
		if x.alive:
			x.process_mode = Node.PROCESS_MODE_DISABLED
		x.global_position += Vector2(0, -4000)


func _here(dx := 0.0) -> Vector2:
	return Iso.to_screen(SPOT) + Vector2(dx, 0)


func _put(e: Enemy, at: Vector2) -> void:
	e.global_position = at
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.enter_combat(game.player.global_position, false, false)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.alerted_once = true
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		_down()
	if frame <= 3:
		return false
	t += delta
	if b and a and a.downed and a.rescuer == b and b.rescue_phase in ["drag", "treat"]:
		check(a.down_t <= down0 + 0.05, "his clock ran while his comrade had him (%.2f > %.2f)" % [a.down_t, down0])
		max_drag_t += delta
	elif a and a.downed:
		down0 = a.down_t
	if queue.is_empty():
		print("stats: ", game.stats)
		print("downed test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _down() -> void:
	step = "down"
	a = _take("bandido")
	_put(a, _here())
	var n0: int = game.alive_enemies()
	a.take_hit(5, Vector2.RIGHT, game.player)
	check(a.downed and not a.alive, "a killing shot should down him")
	check(game.alive_enemies() == n0 - 1, "a downed man still counts as standing")
	queue = [[0.2, func():
		check(a.hurtbox.collision_layer == Iso.LAYER_HURT, "a downed man can't be hit")
		_bleed()]]


func _bleed() -> void:
	step = "bleed"
	queue.append([44.0, func(): check(a.downed, "he bled out too soon (%.1f s)" % a.down_t)])
	queue.append([1.5, func():
		check(not a.downed and not a.alive, "he should have bled out")
		check(game.stats.get("bleeds out", 0) == 1, "no bleeding out counted")
		_finish()])


func _finish() -> void:
	step = "finish"
	_away()
	a = _take("bandido")
	_put(a, _here(30))
	a.take_hit(5, Vector2.RIGHT, game.player)
	queue.append([0.3, func():
		var from: Vector2 = a.global_position + Vector2(-60, 0)
		game.spawn_bullet(from, Vector2(900, 0), 120.0, 2, game.player, Iso.GUN_H, false)])
	queue.append([0.4, func():
		check(not a.downed and not a.alive, "a round should finish a downed man")
		check(game.stats.get("wounded men shot", 0) == 1, "the stranger's tally of wounded men shot")
		_rescue()])


func _rescue() -> void:
	step = "rescue"
	_away()
	a = _take("pistolero")
	b = _take("cowboy")
	_put(a, _here(60))
	_put(b, _here(60) + Vector2(100, 30))
	a.take_hit(5, Vector2.RIGHT, game.player)
	at0 = a.global_position
	max_drag_t = 0.0
	queue.append([40.0, func():
		print("rescue: dragged %.0f px, held %.1f s, %s" % [a.global_position.distance_to(at0), max_drag_t,
			"up again" if a.alive else ("still down" if a.downed else "dead")])
		check(game.stats.get("goes to get a downed man", 0) >= 1, "nobody went for him")
		check(a.alive and a.hp == 1 and not a.downed, "he should be back up with 1 HP")
		check(a.weapon != null and a.weapon.kind == a.loadout[0], "his gun back in hand")
		check(max_drag_t > 3.0, "he wasn't dragged or bandaged for long (%.1f s)" % max_drag_t)
		_dropped()])


func _dropped() -> void:
	step = "dropped"
	_away()
	b = null
	a = _take("pistolero")
	var r := _take("rifleman")
	_put(a, _here(120))
	_put(r, _here(120) + Vector2(110, 20))
	a.take_hit(5, Vector2.RIGHT, game.player)
	queue.append([0.2, func(): _wait_drag(r, 0.0)])


func _wait_drag(r: Enemy, waited: float) -> void:
	if r.rescue_phase != "drag" and waited < 20.0:
		queue.push_front([0.2, func(): _wait_drag(r, waited + 0.2)])
		return
	check(r.rescue_phase == "drag", "the rescuer never got to dragging")
	r.die(Vector2.RIGHT, game.player)
	var held: float = a.down_t
	queue.push_front([2.0, func():
		check(a.downed and a.rescuer == null, "he should be left lying there")
		check(a.down_t > held + 1.5, "his clock should run again")
		_knife()])


func _knife() -> void:
	step = "knife"
	var p: Player = game.player
	p.process_mode = Node.PROCESS_MODE_INHERIT
	a.global_position = Iso.to_screen(Vector2(30.0, 31.4))   # (out on the street: he'd been dragged in behind something)
	p.global_position = a.global_position + Vector2(-16, 0)
	queue.append([0.1, func():
		check(p.knife_cand == a and p.knife_silent, "the knife should find the downed man")
		check(p.knife(), "the knife didn't go")])
	queue.append([1.0, func():
		check(not a.downed and not a.alive, "the knife should finish him")
		p.process_mode = Node.PROCESS_MODE_DISABLED
		p.global_position = Iso.to_screen(Vector2(-40, -40))
		_once()])


func _once() -> void:
	step = "once"
	_away()
	a = _take("cowboy")
	_put(a, _here(180))
	a.take_hit(5, Vector2.RIGHT, game.player)
	a.revive()
	check(a.alive, "revive failed")
	a.take_hit(5, Vector2.RIGHT, game.player)
	check(not a.alive and not a.downed, "down once and up again: the next one kills him")
