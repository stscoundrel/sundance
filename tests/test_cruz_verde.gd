extends SceneTree
## Cruz Verde, the walled garrison:
##   map      - the five on guard and the townsfolk are on open ground; none of them
##              (nor any guard post) can see where the stranger starts, outside the
##              west gate; he can get from there to the plaza.
##   ambush   - the rest are indoors: fifteen on the title, five to be seen. Waiting
##              outside, nothing stirs and no waves come. The first shot brings them
##              out of their doors: two at once, then three at twelve seconds, three
##              at twenty and two (El General last) at thirty; and starts the waves'
##              clock, the first of them a minute off.
##   padre    - the padre goes to the dead with the shooting still going on.
##   ways in  - from every road there's a way to the plaza, and each gate and
##              breach is a way through the walls on its own.
##   fight    - the autopilot holds out a few minutes: the waves keep coming down
##              the roads, every half minute for the first five, and nothing goes wrong.
##   godot --headless --path . --fixed-fps 60 -s tests/test_cruz_verde.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var shot_at := -1.0
var first_out := -1.0
var all_out := -1.0
var blessed_under_fire := 0
var blessings := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "cruz_verde")
	Engine.set_meta("no_captive", true)   # (nobody at the pole: see test_captive)
	seed(19)
	game = load("res://scenes/main.tscn").instantiate()
	game._args["bot"] = "1"
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _reaches(a: Vector2, b: Vector2) -> bool:
	var path: PackedVector2Array = game.find_path(a, b)
	return path.size() > 0 and path[path.size() - 1].distance_to(b) < 20.0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		_map()
		_ways_in()
		step = "ambush"
		check(game.enemies.size() == 5 and game.director.indoors() == 10, "%d out, %d in" % [game.enemies.size(),
			game.director.indoors()])
		game.begin()
		game.player.hp = 100000
	if frame <= 3:
		return false
	t += delta
	var d: Director = game.director
	for c in game.civilians:   # (gone to the dead, or knelt by them, with the shooting going on)
		if c.priest and c.alive and c.st in [Civilian.St.TO_BLESS, Civilian.St.BLESS] and game.quiet_for() < game.quiet_after:
			blessed_under_fire += 1
	blessings = game.stats.get("blessings", 0)
	if t < 10.0:
		if d.next_in() >= 0.0 or game.enemies.size() != 5 or game.last_gunfire > -1e8:
			check(false, "it stirred with the stranger waiting outside (%.1f to a wave, %d about)" % [d.next_in(), game.enemies.size()])
			t = 10.0
		return false
	if shot_at < 0.0:   # into the plaza: the autopilot opens up on the first he sees
		if game.player.global_position.distance_to(Iso.to_screen(Vector2(15, 26.2))) < 2.0:
			game.player.global_position = Iso.to_screen(Vector2(24.0, 28.6))
		if game.last_gunfire > -1e8:
			shot_at = t
		return false
	if first_out < 0.0 and game.stats.get("out of doors", 0) > 0:
		first_out = t
	if all_out < 0.0 and d.indoors() == 0:
		all_out = t
		var jefe: bool = game.enemies.any(func(e): return e.kind == "general")
		print("first shot at %.1f s; first out %.1f s after, all ten %.1f s after; next wave in %.0f s" % [
			shot_at, first_out - shot_at, all_out - shot_at, d.next_in()])
		check(first_out - shot_at < 3.0, "the ready ones took %.1f s" % (first_out - shot_at))
		check(all_out - shot_at > 28.0 and all_out - shot_at < 31.5, "all out %.1f s after the shot" % (all_out - shot_at))
		check(jefe, "El General never came out")
		check(game.stats.get("roused by", "") == "the shooting", "roused by %s" % game.stats.get("roused by", ""))
		check(d.next_in() > 0.0 and d.next_in() < 60.0 - (all_out - shot_at) + 1.0, "the waves' clock didn't start with the shot")
		step = "fight"
		for e in game.enemies:   # one for the padre, in the middle of it all
			if e.kind == "revolucionario" and e.alive:
				e.die(Vector2.RIGHT, null, "death_slump")
	if t < 210.0 and game.state == "play":
		return false
	print("after %.0f s: %s; %d of %d down, %d walked in; stats %s" % [t, game.state,
		game.enemies.filter(func(e): return not e.alive).size(), game.enemies.size(), game.stats.get("arrivals", 0), game.stats])
	check(game.stats.get("arrivals", 0) >= 12, "only %d walked in by %.0f s" % [game.stats.get("arrivals", 0), t])
	check(game.stats.get("waves warned", 0) >= 5, "too few warnings")
	check(blessed_under_fire >= 1, "the padre never went to the dead under fire (%d blessings)" % blessings)
	print("the padre with the dead under fire for %.0f s; %d blessings" % [blessed_under_fire / 60.0, blessings])
	print("Cruz Verde test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true


func _map() -> void:
	step = "map"
	var lv: Dictionary = game.level
	check(lv["name"] == "Cruz Verde", "loaded %s" % lv["name"])
	var start := Iso.to_screen(Vector2(lv["player"]["x"], lv["player"]["y"]))
	check(game.is_free(start), "the stranger starts in something")
	var sight := Enemy.VIEW * 1.2
	var spots: Array = []
	for e in lv["enemies"]:
		spots.append([e["kind"], Vector2(e["x"], e["y"])])
	for e in lv["sleepers"]:
		check(game.is_free(Iso.to_screen(Vector2(e["x"], e["y"]))), "a %s's door is blocked" % e["kind"])
		for p in e.get("patrol", []):
			spots.append([e["kind"] + " on his rounds", Vector2(p[0], p[1])])
	for p in lv["posts"]:
		if game.usable_post(p):
			spots.append(["a %s post" % p["tag"], Vector2(p["x"], p["y"])])
	for s in spots:
		var at := Iso.to_screen(s[1])
		check(game.is_free(at), "%s at %s is in something" % s)
		check(at.distance_to(start) > sight or not game.line_of_sight(at, start, false),
			"%s at %s can see the stranger's start" % s)
	for c in game.civilians:
		check(game.is_free(c.global_position), "a %s is in something" % c.kind)
	var mid := Iso.to_screen(Vector2(lv["center"]["x"], lv["center"]["y"]))
	check(_reaches(start, mid), "no way from the start to the plaza")


func _ways_in() -> void:
	step = "ways in"
	var lv: Dictionary = game.level
	var mid := Iso.to_screen(Vector2(lv["center"]["x"], lv["center"]["y"]))
	for e in lv["entries"]:
		check(_reaches(Iso.to_screen(Vector2(e["x"], e["y"])), mid), "no way in from the %s" % e["name"])
	# through each gap in the walls: a step outside to a step inside
	var gaps := {"north gate": [Vector2(32.5, 12.5), Vector2(32.5, 17.6)], "south gate": [Vector2(32.5, 48.6), Vector2(32.5, 45.0)],
		"west gate": [Vector2(14.6, 30.5), Vector2(17.8, 30.5)], "east gate": [Vector2(50.4, 30.5), Vector2(47.2, 30.5)],
		"south breach": [Vector2(42.3, 48.6), Vector2(42.3, 45.0)], "east breach": [Vector2(50.4, 36.3), Vector2(47.2, 36.3)]}
	for k in gaps:
		var a := Iso.to_screen(gaps[k][0])
		var b := Iso.to_screen(gaps[k][1])
		var path: PackedVector2Array = game.find_path(a, b)
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i].distance_to(path[i - 1])
		check(path.size() > 0 and length < a.distance_to(b) * 1.6, "the %s isn't a way through (%.0f px for %.0f)" % [
			k, length, a.distance_to(b)])
