extends SceneTree
## Levels and shuffled gangs (no townsfolk; nobody moves):
##   posts    - no guard post can see where the stranger rides in; one that's in
##              something (or walks through it) is never dealt a man.
##   shuffle  - a shuffled gang has the count asked for, one El Jefe, a mix like the
##              map's own, men kept apart; the same count deals the same town, another
##              count a different one.
##   scale    - a smaller gang bands together into a smaller posse, and drinks in a
##              smaller reserve; the hand-drawn town keeps its seven and its five.
##   picker   - the title gives way to the picker, which offers San Miguel, Cruz
##              Verde and Paso Esperanza (the rest are hidden, for the tests), each
##              note short enough for its row; picking another town
##              reloads with it, at the guns, and the drawn town keeps its 25 (and the hangman), its posse
##              of seven, its five; picking the town already loaded goes on to the guns.
##   godot --headless --path . --fixed-fps 60 -s tests/test_levels.gd

var game: Node
var frame := 0
var failures := 0
var step := ""


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("level", "san_miguel_15")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false   # (the walls settle into the physics world)
	if frame == 3:
		_posts()
		_entries()
		_shuffle()
		_scale()
		_picker()
		# another town: the scene reloads with it, straight to the guns
		step = "reload"
		current_scene = game
		Engine.remove_meta("level")
		game._to_levels()
		game.pick_level(0)
		return false
	if frame < 12:
		return false
	var g: Node = current_scene
	check(g != game and g.level_entry["id"] == "san_miguel", "the drawn town didn't load")
	check(g.state == "loadout", "a new town should open on the guns (%s)" % g.state)
	check(g.enemies.size() == 26 and g.hanging != null and g.posse_size == Posse.SIZE and g.level["reserve"]["squad"].size() == 5,
		"the drawn town: %d bandits, posse %d, reserve %d" % [g.enemies.size(), g.posse_size, g.level["reserve"]["squad"].size()])
	step = "picker"
	g._to_levels()
	check(g.levels[g.level_pick]["id"] == "san_miguel", "the cursor isn't on the town loaded")
	g.pick_level(g.level_pick)
	check(g.state == "loadout", "picking the town already loaded didn't go on to the guns (%s)" % g.state)
	print("levels test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true


func _posts() -> void:
	step = "posts"
	var lv: Dictionary = game.level
	var spawn := Iso.to_screen(Vector2(lv["player"]["x"], lv["player"]["y"]))
	var sight := Enemy.VIEW * 1.2
	print("%d guard posts" % lv["posts"].size())
	for p in lv["posts"]:
		var pts := [Vector2(p["x"], p["y"])]
		for q in p.get("patrol", []):
			pts.append(Vector2(q[0], q[1]))
		var blocked := pts.any(func(g): return not game.is_free(Iso.to_screen(g)))
		if blocked:   # (dealt to nobody: the game passes it over)
			check(not game.level["enemies"].any(func(e): return e["x"] == p["x"] and e["y"] == p["y"]),
				"a %s post at %s in something was dealt a man" % [p["tag"], pts[0]])
			continue
		for g in pts:
			var at := Iso.to_screen(g)
			check(at.distance_to(spawn) > sight or not game.line_of_sight(at, spawn, false),
				"a %s post at %s can see the spawn" % [p["tag"], g])


## The roads into town: on open ground, and a way from each to the middle of town.
func _entries() -> void:
	step = "entries"
	var lv: Dictionary = game.level
	var mid := Iso.to_screen(Vector2(lv["center"]["x"], lv["center"]["y"]))
	check(game.is_free(mid), "the middle of town is blocked")
	check(lv["entries"].size() >= 4, "only %d roads in" % lv["entries"].size())
	for e in lv["entries"]:
		var at := Iso.to_screen(Vector2(e["x"], e["y"]))
		check(game.is_free(at), "the %s comes in through something" % e["name"])
		var path: PackedVector2Array = game.find_path(at, mid)
		check(path.size() > 0 and path[path.size() - 1].distance_to(mid) < 20.0, "no way in from the %s" % e["name"])


func _shuffle() -> void:
	step = "shuffle"
	var lv: Dictionary = game.level
	var classic: Dictionary = game._load_json("res://data/town.json")
	for n in [10, 15, 25, 35, 45]:
		var gang: Array = game.shuffled_gang(classic, n)
		check(gang.size() == mini(n, classic["posts"].size()), "%d asked for, %d dealt" % [n, gang.size()])
		check(gang.filter(func(e): return e["kind"] == "jefe").size() == 1, "%d: not one El Jefe" % n)
		var kinds := {}
		for e in gang:
			kinds[e["kind"]] = kinds.get(e["kind"], 0) + 1
		var closest := INF
		for i in gang.size():
			for j in range(i + 1, gang.size()):
				closest = minf(closest, Vector2(gang[i]["x"], gang[i]["y"]).distance_to(Vector2(gang[j]["x"], gang[j]["y"])))
		print("%d bandits: %s; closest two %.1f tiles apart" % [n, kinds, closest])
		check(n > 30 or closest >= 4.0, "%d: men bunched up (%.1f tiles)" % [n, closest])
		if n >= 25:
			check(kinds.get("bandido", 0) >= 3 and kinds.get("rifleman", 0) >= 2, "%d: the mix is off" % n)
		check(game.shuffled_gang(classic, n) == gang, "%d: the same count dealt a different town" % n)
	check(game.shuffled_gang(classic, 25) != classic["enemies"], "shuffled 25 is just the drawn town")
	check(game.shuffled_gang(classic, 25).map(func(e): return [e["x"], e["y"]]) \
		!= game.shuffled_gang(classic, 26).slice(0, 25).map(func(e): return [e["x"], e["y"]]), "25 and 26 dealt alike")
	# the level loaded is the shuffled 15
	check(game.level_entry["id"] == "san_miguel_15" and game.enemies.size() == 15, "loaded %s with %d" % [
		game.level_entry["id"], game.enemies.size()])
	check(lv["enemies"] == game.shuffled_gang(classic, 15, game.usable_post), "the loaded 15 aren't the count's own deal")


func _scale() -> void:
	step = "scale"
	print("15 bandits: posse of %d, reserve of %d" % [game.posse_size, game.level["reserve"]["squad"].size()])
	check(game.posse_size < Posse.SIZE and game.posse_size >= 3, "posse of %d for 15" % game.posse_size)
	check(game.level["reserve"]["squad"].size() == 3, "reserve of %d for 15" % game.level["reserve"]["squad"].size())


func _picker() -> void:
	step = "picker"
	check(game.state == "title", "starts at %s" % game.state)
	game._to_levels()
	check(game.state == "levels", "the title didn't give way to the picker")
	check(game.levels.map(func(l): return l["id"]) == ["san_miguel", "cruz_verde", "train"],
		"the picker offers %s" % [game.levels.map(func(l): return l["id"])])
	for l in game.levels:   # (each note on one line in its row: a short one)
		var w: float = game.hud.small.get_string_size(l.get("note", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		check(w <= game.hud.ROW.size.x - 46.0, "%s's note runs out of its row (%d px)" % [l["id"], w])
