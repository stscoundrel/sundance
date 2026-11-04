extends SceneTree
## Paso Esperanza, the stopped train (the place; its cargo is test_cargo's):
##   map     - the train is there, its long things in pieces that fade as one
##             (each boxcar, the tender, the engine), the boxcars' doors open on both
##             sides; the dead lie where they fell (scenery: nothing hits them);
##             three sticks of dynamite in the breastwork, smoke going up; the
##             army's ways in (the south-east from the corner), each one used.
##   ways    - from the breastwork the stranger can get under the engine's nose to
##             the west pocket, up to the post by the tender, round to the
##             revolution's side of the line, out to each of the wagons, to the far
##             end of the train and down the east road.
##   lines   - a moment in, the stranger says his line ("Pintamos de rojo sol y
##             cielo"), and then the comandante calls to his carriers ("¡Estudiantes,
##             rebeldes, bandoleros!").
##   quiet   - with no gang there it isn't won (or lost) by the count of them: it goes on.
##   sticks  - he picks a stick up, but only one at a time.
##   godot --headless --path . --fixed-fps 60 -s tests/test_train.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "train")
	Engine.set_meta("no_waves", true)   # (the army's test_federales')
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _reaches(a: Vector2, b: Vector2) -> bool:
	var path: PackedVector2Array = game.find_path(Iso.to_screen(a), Iso.to_screen(b))
	return path.size() > 0 and path[path.size() - 1].distance_to(Iso.to_screen(b)) < 20.0


func _map() -> void:
	step = "map"
	check(game.enemies.is_empty() and game.civilians.size() == 7, "who's there: %d, %d" % [game.enemies.size(), game.civilians.size()])   # (the carriers and their comandante)
	var groups := {}
	for b in game.buildings:
		groups[b["group"]] = groups.get(b["group"], 0) + 1
	var sizes := groups.values()
	sizes.sort()
	check(sizes.count(3) == 3 and sizes.count(2) == 1, "the fading pieces: %s" % [sizes])   # two boxcars and the engine; the tender
	for i in 3:
		check((game.meta["objects"]["boxcar_a_%d" % i]["doors"] as Array).size() == (2 if i == 1 else 0),
			"boxcar_a_%d doors: %s" % [i, game.meta["objects"]["boxcar_a_%d" % i]["doors"]])
	var dead := 0
	var smoke := 0
	var sticks := 0
	for n in game.world.get_children():
		if n is Corpse:
			dead += 1
			check(not n.alive and n.collision_layer == 0 and n.hurtbox.collision_layer == 0, "a body that can be hit")
		if n is Pickup and n.kind == "dynamite":
			sticks += 1
	for n in game.get_children():
		if n is Smoulder:
			smoke += 1
	check(dead == 20, "%d dead" % dead)
	check(sticks == 3, "%d sticks" % sticks)
	check(smoke == 3, "%d smoke" % smoke)
	check(game.director == null, "a director with nothing to direct")
	# the army's ways in: every wave's road is one of the map's, and the south-east
	# comes from the corner, between the east road and the south
	var ways := {}
	for e in game.level["entries"]:
		ways[e["name"]] = Vector2(e["x"], e["y"])
	check(ways.has("south-east") and ways["south-east"].x > 60.0 and ways["south-east"].y > 60.0, "no way in from the corner: %s" % [ways])
	var used := {}
	for w in game.level_entry["waves"]:
		for gr in w["groups"]:
			check(ways.has(gr["from"]), "a wave from \"%s\", which isn't on the map" % gr["from"])
			used[gr["from"]] = true
	check(used.size() == ways.size(), "ways in nobody comes by: %s of %s" % [used.keys(), ways.keys()])


func _ways() -> void:
	step = "ways"
	var start := Vector2(game.level["player"]["x"], game.level["player"]["y"])
	for to in [Vector2(20.0, 21.0), Vector2(7.0, 27.0), Vector2(7.0, 14.0), Vector2(14.0, 3.0), Vector2(30.0, 0.5),
			Vector2(27.0, 9.0), Vector2(45.0, 50.0), Vector2(24.2, 38.6), Vector2(34.0, 25.4), Vector2(62.0, 36.9), Vector2(26.6, 29.4)]:
		check(_reaches(start, to), "no way from the breastwork to %s" % to)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		_map()
		_ways()
		game.begin()
	if frame <= 3:
		return false
	t += delta
	if t < 20.0:
		step = "lines"
		if t > 3.5 and t < 3.6:
			check(game.player.shout == "Pintamos de rojo sol y cielo" and game.player.shout_t > 0.0,
				"the stranger's line: '%s'" % game.player.shout)
		if t > 6.5 and t < 6.6:
			var c: Civilian = game.cargo.leader
			check(c.called and c.shout == "¡Estudiantes, rebeldes, bandoleros!", "the comandante's call: '%s'" % c.shout)
		return false
	step = "quiet"
	check(game.state == "play", "it ended by itself: %s" % game.state)
	if game.player.sticks == 0 and t < 30.0:
		step = "sticks"
		for n in game.world.get_children():
			if n is Pickup and n.kind == "dynamite":
				game.player.global_position = n.global_position
				break
		return false
	if t < 31.0:
		return false
	step = "sticks"
	check(game.player.sticks == 1, "%d sticks on him" % game.player.sticks)
	var left := 0
	for n in game.world.get_children():
		if n is Pickup and n.kind == "dynamite":
			left += 1
			game.player.global_position = n.global_position   # (walk over another: he can't carry it)
	if t < 32.0:
		return false
	check(game.player.sticks == 1 and left == 2, "%d on him, %d left lying" % [game.player.sticks, left])
	print("train test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
