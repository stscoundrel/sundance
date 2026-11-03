extends SceneTree
## Things gunfire breaks that are no cover (everyone held still, out of town):
##   town    - there are tables of bottles, chairs, clay jars, porch lanterns and
##             panes of glass about town; none of them blocks the way or the view.
##   rounds  - a round through a table takes the bottles and flies on; the next
##             breaks the table; a chair goes over, then to pieces; a jar shatters
##             at one; a lantern too.
##   window  - a round into a pane at standing height breaks it; into a shuttered
##             window it doesn't; low under one it doesn't.
##   blast   - dynamite clears the lot near it, windows included.
##   mayor   - all of it is damage for the mayor to tut over.
##   godot --headless --path . --fixed-fps 60 -s tests/test_fragile.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var queue: Array = []   # [[seconds to wait, callable], ...]


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	seed(4)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _of(kind: String) -> Array:
	return game.fragile.filter(func(i): return i["kind"] == kind)


## A round from 60 px off straight through `at`, at standing height.
func _shoot(at: Vector2, from_dir := Vector2(-1, 0.3), height := Iso.GUN_H) -> void:
	var d := from_dir.normalized()
	game.spawn_bullet(at + d * 60.0, -d * 900.0, 120.0, 2, game.player, height, false)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -4000)
		_town()
		_rounds()
	if frame <= 3:
		return false
	t += delta
	if queue.is_empty():
		print("stats: ", game.stats)
		print("fragile test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	if t >= queue[0][0]:
		t = 0.0
		var c: Callable = queue.pop_front()[1]
		c.call()
	return false


func _town() -> void:
	step = "town"
	var n := {}
	for i in game.fragile:
		n[i["kind"]] = n.get(i["kind"], 0) + 1
	print("fragile about town: ", n)
	for k in ["table", "chair", "olla", "lantern", "glass"]:
		check(n.get(k, 0) >= 3, "too few of %s (%d)" % [k, n.get(k, 0)])
	for k in ["table", "chair", "olla"]:
		check(game.meta["objects"][k]["collide"] == "none", "a %s blocks the way" % k)
		for i in _of(k):
			check(i["body"].collision_layer == Iso.LAYER_FRAGILE, "a %s stops more than rounds" % k)
			check(not game.props.any(func(p): return p["sprite"] == i["sprite"]), "a %s counts as cover" % k)


## One of these with a clear line for a round from that side.
func _open(kind: String, from_dir: Vector2) -> Dictionary:
	for i in _of(kind):
		var from: Vector2 = i["at"] + from_dir.normalized() * 60.0
		if game.ray(from, i["at"], Iso.LAYER_WALL | Iso.LAYER_COVER).is_empty():
			return i
	check(false, "no %s in the open" % kind)
	return _of(kind)[0]


func _rounds() -> void:
	var table: Dictionary = _open("table", Vector2(-1, 0.3))
	var chair: Dictionary = _open("chair", Vector2(-1, 0.3))
	var olla: Dictionary = _open("olla", Vector2(-1, 0.3))
	var lantern: Dictionary = _open("lantern", Vector2(1, -0.3))
	var w := 0.4
	queue = [
		[0.0, func(): step = "rounds"; _shoot(table["at"])],
		[w, func():
			check(table["state"] == 1, "the bottles should go first (%d)" % table["state"])
			_shoot(table["at"])],
		[w, func():
			check(table["state"] == 2 and table["body"] == null, "the table should be in pieces (%d)" % table["state"])
			_shoot(chair["at"])],
		[w, func():
			check(chair["state"] == 1, "the chair should go over (%d)" % chair["state"])
			_shoot(chair["at"])],
		[w, func():
			check(chair["state"] == 2, "the chair should be in pieces (%d)" % chair["state"])
			_shoot(olla["at"])],
		[w, func():
			check(olla["state"] == 1, "the jar should shatter")
			_shoot(lantern["at"], Vector2(1, -0.3))],
		[w, func():
			check(lantern["state"] == 1 and lantern["sprite"].frame == 1, "the lantern should break")
			_window()],
	]


## A pane on the street front of a wooden building, and a round at its middle.
func _pane(skip: Array) -> Dictionary:
	for i in _of("glass"):
		if i in skip or i["state"] > 0 or i["z"].x > 30.0 or i["shutter"] == null:
			continue
		var out: Vector2 = i["at"] + Vector2(0, 20)
		if game.is_free(out) and game.line_of_sight(out, i["at"] + Vector2(0, 2), false):
			return i
	return {}


func _window() -> void:
	step = "window"
	var pane := _pane([])
	var shut := _pane([pane])
	var low := _pane([pane, shut])
	check(not pane.is_empty() and not shut.is_empty() and not low.is_empty(), "no street windows")
	shut["shutter"].shut = true
	var mid: float = (pane["z"].x + pane["z"].y) * 0.5
	_shoot(pane["at"], Vector2(0.2, 1), mid)
	_shoot(shut["at"], Vector2(0.2, 1), (shut["z"].x + shut["z"].y) * 0.5)
	_shoot(low["at"], Vector2(0.2, 1), low["z"].x - 8.0)
	queue.append([0.4, func():
		check(pane["state"] == 1 and pane["sprite"].visible, "the pane wasn't shot out")
		check(shut["state"] == 0, "a pane broke behind shut shutters")
		check(low["state"] == 0, "a pane broke from a round under it")
		_blast(low)])


func _blast(pane: Dictionary) -> void:
	step = "blast"
	var at: Vector2 = pane["at"] + Vector2(0, 30)
	var near: Array = game.fragile.filter(func(i): return i["state"] < i["last"] and i["at"].distance_to(at) < 50.0 \
		and (i.get("shutter") == null or not i["shutter"].shut))
	game.blast(at, game.enemies[0])
	for i in near:
		check(i["state"] == i["last"], "the blast left a %s whole" % i["kind"])
	check(pane["state"] == 1, "the blast didn't take the window")
	queue.append([0.2, func(): _mayor()])


func _mayor() -> void:
	step = "mayor"
	var n: int = game.scars.filter(func(s): return s["prop"] is Dictionary and s["prop"].has("kind") \
		and s["prop"]["kind"] in ["table", "chair", "olla", "lantern", "glass"]).size()
	check(n >= 6, "the breakage isn't on the mayor's list (%d)" % n)
